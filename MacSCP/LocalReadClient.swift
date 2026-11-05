import Foundation
import Darwin

// A read-only local source lets ordinary queued downloads copy files without an SSH process.
final class LocalReadClient:RemoteFileClient {
 let capabilities:RemoteFileCapabilities=[.checksum,.downloadResume]
 var progress:((UInt64)->Void)?,resumedProgress:((UInt64)->Void)?,phase:((String)->Void)?,auxiliaryProgress:((UInt64)->Void)?,checkpoint:(()throws->Void)?
 private let lock=NSLock();private var stopped=false
 func close(){lock.lock();stopped=true;lock.unlock()}
 func interrupt(){close()}
 private func point()throws{lock.lock();let stopped=stopped;lock.unlock();guard !stopped else{throw SFTPError.message("本地复制已停止")};try checkpoint?()}
 private func path(_ value:String)throws{guard value.hasPrefix("/"),!value.contains("\0") else{throw SFTPError.message("本地路径无效")}}
 func canonical(_ value:String)throws->String{try point();try path(value);guard let resolved=realpath(value,nil) else{throw NSError(domain:NSPOSIXErrorDomain,code:Int(errno))};defer{free(resolved)};return String(cString:resolved)}
 func attributes(_ value:String)throws->RemoteFileAttributes?{try point();try path(value);var info=stat();if lstat(value,&info) != 0{if errno==ENOENT{return nil};throw NSError(domain:NSPOSIXErrorDomain,code:Int(errno))};return(UInt64(max(0,info.st_size)),UInt32(info.st_mode),UInt32(clamping:info.st_mtimespec.tv_sec))}
 func followedAttributes(_ value:String)throws->RemoteFileAttributes?{try attributes(canonical(value))}
 func list(_ value:String,resolveLinks:Bool,maximumEntries:Int?)throws->[RemoteFile]{
  try point();guard let info=try attributes(value),info.mode&0o170000==0o040000 else{throw SFTPError.message("本地源不是普通目录")}
  let urls=try FileManager.default.contentsOfDirectory(at:URL(fileURLWithPath:value),includingPropertiesForKeys:nil)
  if let limit=maximumEntries,urls.count>limit{throw SFTPError.message("本地目录项超过限制")}
  return try urls.map{url in try point();guard let attrs=try attributes(url.path) else{throw SFTPError.message("本地源目录在扫描时变化")};return RemoteFile(name:url.lastPathComponent,size:attrs.size,directory:attrs.mode&0o170000==0o040000,modified:attrs.modified,mode:attrs.mode)}
 }
 func checksum(_ value:String)throws->String{try point();let source=try FTPUploadSource(URL(fileURLWithPath:value));return try source.digest(checkpoint:{try self.point()})}
 func download(_ value:String,to local:URL,maximumBytes:UInt64?)throws{let state=TransferResume(source:value,destination:local.path,upload:false);try receive(value,to:local,state:state,overwrite:true,verify:false,resume:false,maximumBytes:maximumBytes)}
 func downloadResumable(_ value:String,to local:URL,state:TransferResume,overwrite:Bool,verifyChecksum:Bool)throws{try receive(value,to:local,state:state,overwrite:overwrite,verify:verifyChecksum,resume:true,maximumBytes:nil)}
 private func receive(_ value:String,to local:URL,state:TransferResume,overwrite:Bool,verify:Bool,resume:Bool,maximumBytes:UInt64?)throws{
  try point();guard state.source==value,state.destination==local.path,!state.upload else{throw SFTPError.message("本地复制续传状态不匹配")}
  let source=try FTPUploadSource(URL(fileURLWithPath:value))
  if let maximumBytes=maximumBytes,source.size>maximumBytes{throw SFTPError.message("本地文件超过读取限制")}
  let digest=try source.digest(checkpoint:{try self.point()})
  if let expected=state.sourceDigest,expected != digest{throw SFTPError.message("本地复制源发生变化，不能复用旧暂存")};state.sourceDigest=digest
  let target=try FTPDownloadTarget(destination:local,temporary:URL(fileURLWithPath:state.temporaryPath),overwrite:overwrite,resume:resume,retainPartial:resume)
  guard target.size<=source.size else{throw SFTPError.message("本地复制暂存长于源文件")}
  try source.file.seek(toOffset:0);try target.file.seek(toOffset:0)
  var remaining=target.size
  while remaining>0{try point();let length=Int(min(remaining,65536)),a=try source.file.read(upToCount:length) ?? Data(),b=try target.file.read(upToCount:length) ?? Data();guard a.count==length,a==b else{throw SFTPError.message("本地复制暂存前缀不匹配")};remaining-=UInt64(length)}
  if target.size>0{resumedProgress?(target.size)}
  var copied=target.size
  while copied<source.size{try point();let chunk=try source.file.read(upToCount:Int(min(source.size-copied,65536))) ?? Data();guard !chunk.isEmpty else{throw SFTPError.message("本地复制源提前结束")};try target.file.write(contentsOf:chunk);copied+=UInt64(chunk.count);progress?(UInt64(chunk.count))}
  try point();try source.check()
  if verify{try target.file.synchronize();let staged=try FTPUploadSource(URL(fileURLWithPath:state.temporaryPath));guard staged.size==source.size,try staged.digest(checkpoint:{try self.point()})==digest else{throw SFTPError.message("本地复制校验失败")}}
  try point();try source.check();try state.beforePublication?();try target.publish(expectedSize:source.size,modified:source.modified,permissions:source.permissions)
 }
 private func readOnly()throws{throw SFTPError.message("本地复制来源只读，不执行源端写入")}
 func upload(_ local:URL,to remote:String,overwrite:Bool,permissions:UInt32?,beforeCommit:(()throws->Void)?)throws{try readOnly()}
 func uploadResumable(_ local:URL,to remote:String,state:TransferResume,overwrite:Bool,verifyChecksum:Bool)throws{try readOnly()}
 func mkdir(_ path:String)throws{try readOnly()}
 func rename(_ source:String,to destination:String)throws{try readOnly()}
 func remove(_ path:String,directory:Bool)throws{try readOnly()}
 func chmod(_ path:String,mode:UInt32)throws{try readOnly()}
 func readLink(_ path:String)throws->String{try point();return try FileManager.default.destinationOfSymbolicLink(atPath:path)}
 func createSymbolicLink(target:String,path:String)throws{try readOnly()}
 func copyRemoteFile(_ source:String,to destination:String)throws{try readOnly()}
}
