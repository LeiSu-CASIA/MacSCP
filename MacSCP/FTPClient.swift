import Foundation
import CryptoKit

enum FTPPublicationPolicy {case requireAtomic,allowNonAtomic}
final class FTPClient:RemoteFileClient {
 private let publicationPolicy:FTPPublicationPolicy,preserveUploadTime:Bool,preserveUploadPermissions:Bool;private var stagingSources=[String:(FTPUploadSource,String)]()
 let transport:FTPCurlTransport;private let reader:FTPDirectoryReader
 var progress:((UInt64)->Void)?,resumedProgress:((UInt64)->Void)?,phase:((String)->Void)?,auxiliaryProgress:((UInt64)->Void)?,checkpoint:(()throws->Void)?
 var capabilities:RemoteFileCapabilities{var value:RemoteFileCapabilities=[.checksum,.downloadResume];if publicationPolicy == .allowNonAtomic{value.formUnion([.resume,.remoteCopy]);if preserveUploadTime{value.insert(.timestamps)}};return value}
 init(_ connection:FTPConnection,publicationPolicy:FTPPublicationPolicy = .requireAtomic,preserveUploadTime:Bool=true,preserveUploadPermissions:Bool=true)throws{self.publicationPolicy=publicationPolicy;self.preserveUploadTime=preserveUploadTime;self.preserveUploadPermissions=preserveUploadPermissions;transport=try FTPCurlTransport(connection);reader=FTPDirectoryReader(transport:transport);transport.checkpoint={[weak self] in try self?.checkpoint?()}}
 func close(){transport.close();stagingSources.removeAll()};func interrupt(){transport.interrupt()}
 func canonical(_ path:String)throws->String{try reader.canonical(path)}
 private func resolved(_ item:FTPDirectoryEntry,in path:String)throws->RemoteFile{
  if item.directory || item.symbolicLink{return item.file}
  guard item.mode&0o170000==0o100000 else{return item.file}
  if item.sizeKnown && item.modifiedKnown{return item.file}
  let metadata=try transport.perform(.metadata(path));guard let size=metadata.length,let modified=metadata.modified,modified<=Int64(UInt32.max) else{throw SFTPError.message("FTP 服务器未提供可验证的文件大小或修改时间")}
  return RemoteFile(name:item.name,size:UInt64(size),directory:false,modified:UInt32(modified),mode:item.mode,permissionsKnown:item.permissionsKnown)
 }
 func list(_ path:String,resolveLinks:Bool,maximumEntries:Int?)throws->[RemoteFile]{
  let root=try canonical(path),items=try reader.list(root,maximumEntries:maximumEntries ?? 100000)
  return try items.map{item in let full=(root=="/" ? "/" : root+"/")+item.name;var value=try resolved(item,in:full);if value.symbolicLink{value.linkUnavailable=true};return value}.sorted{if $0.directory != $1.directory{return $0.directory};return $0.name.localizedStandardCompare($1.name) == .orderedAscending}
 }
 func attributes(_ path:String)throws->RemoteFileAttributes?{
  let path=try canonical(path);if path=="/"{_ = try transport.perform(.entryDirectory);return(0,0o040000,0)}
  let parent=(path as NSString).deletingLastPathComponent,name=(path as NSString).lastPathComponent
  guard let item=try reader.list(parent).first(where:{$0.name==name}) else{return nil};let file=try resolved(item,in:path);return(file.size,file.mode,file.modified)
 }
 func followedAttributes(_ path:String)throws->RemoteFileAttributes?{let attrs=try attributes(path);guard (attrs?.mode ?? 0)&0o170000 != 0o120000 else{throw unsupported("跟随符号链接")};return attrs}
 func readLink(_ path:String)throws->String{let path=try canonical(path),parent=(path as NSString).deletingLastPathComponent;guard let item=try reader.list(parent).first(where:{$0.name==(path as NSString).lastPathComponent}),item.symbolicLink,let target=item.linkTarget else{throw unsupported("读取此链接目标")};return target}
 private func signature(_ attrs:RemoteFileAttributes,path:String)->String{let identity=[transport.connection.host,String(transport.connection.port),transport.connection.security.rawValue,transport.connection.user,path,String(attrs.size),String(attrs.modified),String(attrs.mode)].joined(separator:"\0");return "ftp:"+SHA256.hash(data:Data(identity.utf8)).map{String(format:"%02x",$0)}.joined()}
 private func regular(_ path:String)throws->RemoteFileAttributes{guard let attrs=try attributes(path),attrs.mode&0o170000==0o100000,attrs.size<=UInt64(Int64.max) else{throw SFTPError.message("FTP 下载或校验源必须是可验证的普通文件")};return attrs}
 private enum PrefixComplete:Error{case verified}
 private func verifyPrefix(_ path:String,target:FTPDownloadTarget,bytes:UInt64)throws{
  guard bytes>0 else{return};phase?("校验已下载前缀…");try target.file.seek(toOffset:0);var remaining=bytes
  do{_ = try transport.perform(.retrieve(path),maximumBytes:UInt64.max,sink:{chunk in
   let count=Int(min(UInt64(chunk.count),remaining));guard let local=try target.file.read(upToCount:count),local==Data(chunk.prefix(count)) else{throw SFTPError.message("FTP 暂存前缀与远程源不同，拒绝续传")};remaining-=UInt64(count);self.auxiliaryProgress?(UInt64(count));if remaining==0{throw PrefixComplete.verified}
  });guard remaining==0 else{throw SFTPError.message("FTP 远程源小于已下载前缀")}}catch PrefixComplete.verified{}
 }
 private func receive(_ remote:String,to local:URL,state:TransferResume,overwrite:Bool,verifyChecksum:Bool,maximumBytes:UInt64?,resume:Bool)throws{
  let path=try canonical(remote);guard !state.upload,state.source==remote,state.destination==local.path else{throw SFTPError.message("FTP 续传记录与源或目标不匹配")}
  let attrs=try regular(path),baseline=signature(attrs,path:path)
  if let maximum=maximumBytes,attrs.size>maximum{throw SFTPError.message("FTP 远程文件超过读取上限")}
  if let old=state.remoteSignature,old != baseline{throw SFTPError.message("FTP 远程源属性或端点变化，不能续传")};state.remoteSignature=baseline
  let target=try FTPDownloadTarget(destination:local,temporary:URL(fileURLWithPath:state.temporaryPath),overwrite:overwrite,resume:resume,retainPartial:resume)
  guard target.size<=attrs.size else{throw SFTPError.message("FTP 暂存大于远程文件")}
  try verifyPrefix(path,target:target,bytes:target.size);guard try signature(regular(path),path:path)==baseline else{throw SFTPError.message("FTP 源在前缀校验时变化")}
  resumedProgress?(target.size);try target.file.seek(toOffset:target.size);var written=target.size;phase?("下载中…")
  if written<attrs.size || attrs.size==0{
   _ = try transport.perform(.retrieveRange(path,Int64(written)),maximumBytes:attrs.size-written,sink:{chunk in try target.file.write(contentsOf:chunk);written+=UInt64(chunk.count);self.progress?(UInt64(chunk.count))})
  }
  guard written==attrs.size,try signature(regular(path),path:path)==baseline else{throw SFTPError.message("FTP 源在下载期间变化，未发布目标")}
  if verifyChecksum{phase?("校验 SHA-256…");try target.file.seek(toOffset:0);var hash=SHA256();while let chunk=try target.file.read(upToCount:1024*1024),!chunk.isEmpty{try checkpoint?();hash.update(data:chunk)};let actual=hash.finalize().map{String(format:"%02x",$0)}.joined();guard try actual==checksum(path) else{throw SFTPError.message("FTP 下载校验不一致，未发布目标")}}
  try checkpoint?();try target.publish(expectedSize:attrs.size,modified:attrs.modified)
 }
 func download(_ remote:String,to local:URL,maximumBytes:UInt64?)throws{let state=TransferResume(source:remote,destination:local.path,upload:false);try receive(remote,to:local,state:state,overwrite:true,verifyChecksum:false,maximumBytes:maximumBytes,resume:false)}
 func downloadResumable(_ remote:String,to local:URL,state:TransferResume,overwrite:Bool,verifyChecksum:Bool)throws{try receive(remote,to:local,state:state,overwrite:overwrite,verifyChecksum:verifyChecksum,maximumBytes:nil,resume:true)}
 func checksum(_ path:String)throws->String{let path=try canonical(path),before=try regular(path),baseline=signature(before,path:path);var hash=SHA256(),count:UInt64=0
  _ = try transport.perform(.retrieve(path),maximumBytes:before.size,sink:{chunk in hash.update(data:chunk);count+=UInt64(chunk.count);self.auxiliaryProgress?(UInt64(chunk.count))})
  guard count==before.size,try signature(regular(path),path:path)==baseline else{throw SFTPError.message("FTP 源在校验时变化")};return hash.finalize().map{String(format:"%02x",$0)}.joined()
 }
 private func unsupported(_ operation:String)->Error{SFTPError.message("FTP \(operation) 尚未接入；未执行远程写入")}
 private func writeAllowed()throws{guard publicationPolicy == .allowNonAtomic else{throw SFTPError.message("FTP 无 SFTP 式原子发布保证；需明确允许非原子操作后才能写入")}}
 private func version(_ path:String)throws->FTPRemoteVersion?{guard let before=try attributes(path) else{return nil};guard before.mode&0o170000==0o100000 else{throw SFTPError.message("FTP 发布路径不是普通文件")};let hash=try checksum(path);guard let after=try attributes(path),before.size==after.size,before.modified==after.modified,before.mode==after.mode else{throw SFTPError.message("FTP 文件在读取发布版本时变化")};return FTPRemoteVersion(size:before.size,modified:before.modified,mode:before.mode,digest:hash)}
 private func permissionsKnown(_ path:String)throws->Bool{let parent=(path as NSString).deletingLastPathComponent,name=(path as NSString).lastPathComponent;return try reader.list(parent).first{$0.name==name}?.permissionsKnown==true}
 private func cleanupUnpublished(_ state:TransferResume)throws{
  guard let record=state.ftpPublication,record.phase == .transferring || record.phase == .ready else{return}
  let cleaner=try independent();defer{cleaner.close()};let backup=try FTPFilePublisher.backup(destination:state.destination,temporary:state.temporaryPath)
  guard try cleaner.version(state.destination)==record.original,try cleaner.attributes(backup)==nil else{throw SFTPError.message("FTP 目标或回滚状态变化，保留暂存："+state.temporaryPath)}
  if try cleaner.attributes(state.temporaryPath) != nil{try remove(state.temporaryPath,directory:false)}
  stagingSources.removeValue(forKey:state.temporaryPath)
 }
 private func operations()->FTPPublicationOperations{FTPPublicationOperations(snapshot:{try self.version($0)},rename:{a,b in _ = try self.transport.perform(.commands([.rename(a,b)]))},remove:{_ = try self.transport.perform(.commands([.removeFile($0)]))})}
 private func independent()throws->FTPClient{try FTPClient(transport.connection,publicationPolicy:.allowNonAtomic,preserveUploadTime:preserveUploadTime,preserveUploadPermissions:preserveUploadPermissions)}
 private func binding(_ path:String,_ stage:String)->String{let text=[transport.connection.host,String(transport.connection.port),transport.connection.security.rawValue,transport.connection.user,path,stage].joined(separator:"\0");return SHA256.hash(data:Data(text.utf8)).map{String(format:"%02x",$0)}.joined()}
 private func verifyUploadPrefix(_ path:String,source:FTPUploadSource,bytes:UInt64)throws{guard bytes>0 else{return};try source.file.seek(toOffset:0);var remaining=bytes;phase?("校验已上传前缀…")
  do{_ = try transport.perform(.retrieve(path),maximumBytes:UInt64.max,sink:{chunk in let count=Int(min(UInt64(chunk.count),remaining));guard let local=try source.file.read(upToCount:count),local==Data(chunk.prefix(count)) else{throw SFTPError.message("FTP 已上传前缀与本地源不同，拒绝续传")};remaining-=UInt64(count);self.auxiliaryProgress?(UInt64(count));if remaining==0{throw PrefixComplete.verified}});guard remaining==0 else{throw SFTPError.message("FTP 已上传前缀不足")}}catch PrefixComplete.verified{}
 }
 private func send(_ local:URL,to remote:String,state:TransferResume,overwrite:Bool,permissions:UInt32?,beforeCommit:(()throws->Void)?)throws{
  try writeAllowed();let path=try canonical(remote);guard path==remote,path != "/",state.upload,state.source==local.path,state.destination==path else{throw SFTPError.message("FTP 上传续传路径不匹配")};_ = try FTPFilePublisher.backup(destination:path,temporary:state.temporaryPath)
  let source=try FTPUploadSource(local),digest=try source.digest(checkpoint:checkpoint),bound=binding(path,state.temporaryPath)
  if let old=state.sourceDigest,old != digest{throw SFTPError.message("FTP 本地源内容变化，不能续传")}
  if let record=state.ftpPublication{try record.validated();guard record.original==nil || overwrite else{throw SFTPError.message("FTP 恢复覆盖必须保留明确的覆盖许可")};guard record.binding==bound else{throw SFTPError.message("FTP 上传端点与发布记录不一致")}}
  else{guard try attributes(state.temporaryPath)==nil else{throw SFTPError.message("FTP 暂存已存在但没有所有权记录")};let original=try version(path);guard original==nil || overwrite else{throw SFTPError.message("FTP 目标已存在，未覆盖")};state.sourceDigest=digest;try state.persistPublication(FTPPublicationRecord(binding:bound,original:original,phase:.transferring))}
  if state.ftpPublication?.original != nil,preserveUploadPermissions,permissions==nil,state.ftpPublication?.phase != .published{
   let backup=try FTPFilePublisher.backup(destination:path,temporary:state.temporaryPath)
   let originalPath=try attributes(path)==nil ? backup : path
   guard try permissionsKnown(originalPath) else{throw SFTPError.message("FTP 服务器未提供原目标权限；关闭保留权限或指定权限后重试")}
  }
  let recovery:()throws->FTPPublicationOperations={try self.independent().operations()}
  func publish()throws{try state.beforePublication?();try source.check();guard try source.digest(checkpoint:self.checkpoint)==digest else{throw SFTPError.message("FTP 本地源在发布前变化")};try beforeCommit?();try FTPFilePublisher.commit(destination:path,state:state,binding:bound,digest:digest,size:source.size,operations:self.operations(),recovery:recovery,checkpoint:{try self.checkpoint?()});self.stagingSources.removeValue(forKey:state.temporaryPath)}
  if state.ftpPublication?.phase != .transferring,try attributes(state.temporaryPath)==nil{try publish();return}
  stagingSources[state.temporaryPath]=(source,digest)
  let staged=try attributes(state.temporaryPath);if let staged=staged{guard staged.mode&0o170000==0o100000,staged.size<=source.size else{throw SFTPError.message("FTP 暂存类型或大小不匹配")}}
  let offset=staged?.size ?? 0;try verifyUploadPrefix(state.temporaryPath,source:source,bytes:offset);try source.check();resumedProgress?(offset)
  if offset<source.size || staged==nil{
   let previous=transport.progress;var last:UInt64=0;let remaining=source.size-offset;transport.progress={_,count in let current=min(count,remaining);if current>last{self.progress?(current-last);last=current}};defer{transport.progress=previous};phase?("上传到远程暂存…")
   _ = try transport.perform(.storeResumable(state.temporaryPath,local,Int64(offset),source.descriptor))
  }
  try source.check();guard try source.digest(checkpoint:checkpoint)==digest else{throw SFTPError.message("FTP 本地源在上传期间变化")}
  phase?("校验 FTP 上传暂存…");guard let verified=try version(state.temporaryPath),verified.size==source.size,verified.digest==digest else{throw SFTPError.message("FTP 暂存校验不一致，未发布")}
  if preserveUploadTime{do{_ = try transport.perform(.commands([.setModified(state.temporaryPath,source.modified)]))}catch{throw SFTPError.message("FTP 无法保留修改时间（MFMT），未发布目标："+error.localizedDescription)}}
  let desired=permissions ?? (preserveUploadPermissions ? (state.ftpPublication?.original?.mode.mapPermissions ?? source.permissions) : nil)
  if let desired=desired{_ = try transport.perform(.commands([.setPermissions(state.temporaryPath,desired)]))}
  guard let ready=try version(state.temporaryPath),ready.digest==digest,ready.size==source.size,!preserveUploadTime || ready.modified==source.modified,desired==nil || ready.mode&0o7777==desired! else{throw SFTPError.message("FTP 暂存属性未通过发布检查")}
  var record=state.ftpPublication!;record.staged=ready;record.phase = .ready;try state.persistPublication(record);try publish()
 }
 func upload(_ local:URL,to remote:String,overwrite:Bool,permissions:UInt32?,beforeCommit:(()throws->Void)?)throws{let path=try canonical(remote),state=TransferResume(source:local.path,destination:path,upload:true);do{try send(local,to:path,state:state,overwrite:overwrite,permissions:permissions,beforeCommit:beforeCommit)}catch{let original=error;do{try cleanupUnpublished(state)}catch{throw SFTPError.message(original.localizedDescription+"；暂存清理未完成："+error.localizedDescription)};throw original}}
 func uploadResumable(_ local:URL,to remote:String,state:TransferResume,overwrite:Bool,verifyChecksum:Bool)throws{try send(local,to:remote,state:state,overwrite:overwrite,permissions:nil,beforeCommit:nil)}
 func mkdir(_ path:String)throws{try writeAllowed();_ = try transport.perform(.commands([.makeDirectory(try canonical(path))]))}
 func rename(_ source:String,to destination:String)throws{try writeAllowed();let a=try canonical(source),b=try canonical(destination);guard try attributes(b)==nil else{throw SFTPError.message("FTP 移动目标已存在")};_ = try transport.perform(.commands([.rename(a,b)]))}
 func remove(_ path:String,directory:Bool)throws{try writeAllowed();let path=try canonical(path)
  if let owned=stagingSources[path]{let cleaner=try independent();defer{cleaner.close()};guard try owned.0.digest(checkpoint:nil)==owned.1 else{throw SFTPError.message("FTP 源变化，保留无法确认的暂存")};if let item=try cleaner.attributes(path){guard item.mode&0o170000==0o100000,item.size<=owned.0.size else{throw SFTPError.message("FTP 暂存变化，未清理")};try cleaner.verifyUploadPrefix(path,source:owned.0,bytes:item.size);_ = try cleaner.transport.perform(.commands([.removeFile(path)]))};stagingSources.removeValue(forKey:path);return}
  _ = try transport.perform(.commands([directory ? .removeDirectory(path) : .removeFile(path)]))
 }
 func chmod(_ path:String,mode:UInt32)throws{try writeAllowed();guard let item=try attributes(path),item.mode&0o170000 != 0o120000 else{throw unsupported("修改链接权限")};_ = try transport.perform(.commands([.setPermissions(path,mode)]))}
 func createSymbolicLink(target:String,path:String)throws{throw unsupported("创建符号链接")}
 func copyRemoteFile(_ source:String,to destination:String)throws{try writeAllowed();guard let original=try version(source) else{throw SFTPError.message("FTP 复制源不存在")};let path=try canonical(source),parent=(path as NSString).deletingLastPathComponent;let known=try reader.list(parent).first{$0.name==(path as NSString).lastPathComponent}?.permissionsKnown==true
  if preserveUploadPermissions && !known{throw SFTPError.message("FTP 无法确认复制源权限")}
  let workspace=FileManager.default.temporaryDirectory.appendingPathComponent("ftp-copy-"+UUID().uuidString);try FileManager.default.createDirectory(at:workspace,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700]);defer{try? FileManager.default.removeItem(at:workspace)};let local=workspace.appendingPathComponent("content");try download(source,to:local,maximumBytes:nil);try upload(local,to:destination,overwrite:false,permissions:preserveUploadPermissions ? original.mode&0o777 : nil,beforeCommit:{guard try self.version(source)==original else{throw SFTPError.message("FTP 复制源在发布前变化")}})
 }
}
private extension UInt32{var mapPermissions:UInt32{self&0o777}}
