import Foundation
import Darwin

// Conversion uses a bounded buffer and never modifies the user's source.
// Unsupported binary encodings are rejected in forced mode; Automatic preserves them byte for byte.
enum TextTransfer {
 enum ConversionError:Error{case binaryData}
 static func convert(_ input:FTPUploadSource,to output:FileHandle,options:TextTransferOptions,upload:Bool,checkpoint:(()throws->Void)?)throws->UInt64 {
  func copy()throws->UInt64{try input.file.seek(toOffset:0);try output.seek(toOffset:0);try output.truncate(atOffset:0);var count:UInt64=0;while let data=try input.file.read(upToCount:65536),!data.isEmpty{try checkpoint?();try output.write(contentsOf:data);count+=UInt64(data.count)};return count}
  try input.check();try input.file.seek(toOffset:0)
  let ending=upload ? options.remote : options.local,removeBOM=upload && options.removeBOM,removeEOF=upload && options.removeEOF
  var buffer=Data(),count:UInt64=0,pendingCR=false,trailingEOF:UInt64=0
  func flush()throws{if !buffer.isEmpty{try output.write(contentsOf:buffer);count+=UInt64(buffer.count);buffer.removeAll(keepingCapacity:true)}}
  func emit(_ byte:UInt8)throws{buffer.append(byte);if buffer.count>=65536{try flush()}}
  func newline()throws{if ending == .crlf{try emit(13)};try emit(10)}
  func byte(_ value:UInt8)throws{
   guard value != 0 else{throw ConversionError.binaryData}
   if removeEOF && value==26{if pendingCR{try newline();pendingCR=false};trailingEOF+=1;return}
   while trailingEOF>0{try emit(26);trailingEOF-=1}
   if pendingCR{try newline();pendingCR=false;if value==10{return}}
   if value==13{pendingCR=true}else if value==10{try newline()}else{try emit(value)}
  }
  do{
   let prefix=try input.file.read(upToCount:4) ?? Data(),head=Array(prefix)
   if head.starts(with:[255,254]) || head.starts(with:[254,255]){throw ConversionError.binaryData}
   for value in removeBOM && head.starts(with:[239,187,191]) ? Array(head.dropFirst(3)) : head{try byte(value)}
   while let data=try input.file.read(upToCount:65536),!data.isEmpty{try checkpoint?();try input.check();for value in data{try byte(value)}}
   if pendingCR{try newline()};try flush();try input.check();return count
  }catch ConversionError.binaryData{
   guard options.mode == .automatic else{throw SFTPError.message("文本转换不支持含 NUL 的二进制文件或 UTF-16/32；请选择二进制模式")}
   let count=try copy();try input.check();return count
  }
 }
 static func withSnapshot<T>(_ source:String,options:TextTransferOptions,upload:Bool,checkpoint:(()throws->Void)?,_ body:(URL,FTPUploadSource)throws->T)throws->T{
  let input=try FTPUploadSource(URL(fileURLWithPath:source)),root=FileManager.default.temporaryDirectory.appendingPathComponent("macscp-text-"+UUID().uuidString,isDirectory:true)
  try FileManager.default.createDirectory(at:root,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700]);defer{try? FileManager.default.removeItem(at:root)}
  let converted=root.appendingPathComponent("content");guard FileManager.default.createFile(atPath:converted.path,contents:nil,attributes:[.posixPermissions:0o600]) else{throw SFTPError.message("无法创建文本转换暂存")}
  let output=try FileHandle(forWritingTo:converted);defer{try? output.close()};_ = try convert(input,to:output,options:options,upload:upload,checkpoint:checkpoint);try output.synchronize();try output.close()
  try FileManager.default.setAttributes([.modificationDate:Date(timeIntervalSince1970:Double(input.modified)),.posixPermissions:input.permissions],ofItemAtPath:converted.path)
  return try body(converted,input)
 }
 static func upload(_ source:String,to destination:String,state:TransferResume,client:RemoteFileClient,options:TextTransferOptions,overwrite:Bool,verify:Bool,preparedSize:((UInt64)throws->Void)?=nil,checkpoint:@escaping()throws->Void)throws{
  client.phase?("正在转换上传文本…");try withSnapshot(source,options:options,upload:true,checkpoint:checkpoint){converted,input in
   try preparedSize?((try FileManager.default.attributesOfItem(atPath:converted.path)[.size] as! NSNumber).uint64Value)
   let old=state.record(),wire=TransferResume(record:ResumeRecord(source:converted.path,destination:destination,upload:true,temporaryPath:old.temporaryPath,sourceDigest:old.sourceDigest,remoteSignature:old.remoteSignature,ftpPublication:old.ftpPublication))
   wire.onChange={[weak wire,weak state] in guard let wire=wire,let state=state else{return};let record=wire.record();state.sourceDigest=record.sourceDigest;state.remoteSignature=record.remoteSignature;state.ftpPublication=record.ftpPublication}
   wire.publicationBarrier={try state.publicationBarrier?()};wire.beforePublication={try checkpoint();try input.check()}
   client.phase?("转换文本并上传…");try client.uploadResumable(converted,to:destination,state:wire,overwrite:overwrite,verifyChecksum:verify)
  }
 }
 static func signature(_ attrs:RemoteFileAttributes)->String{"\(attrs.size):\(attrs.modified):\(attrs.mode)"}
 static func withRemoteSnapshot<T>(_ source:String,client:RemoteFileClient,verify:Bool,checkpoint:()throws->Void,_ body:(URL,RemoteFileAttributes)throws->T)throws->T{
  guard let before=try client.attributes(source),before.mode&0o170000==0o100000 else{throw SFTPError.message("文本下载源必须是普通文件")}
  let root=FileManager.default.temporaryDirectory.appendingPathComponent("macscp-text-download-"+UUID().uuidString,isDirectory:true)
  try FileManager.default.createDirectory(at:root,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700]);defer{try? FileManager.default.removeItem(at:root)}
  let raw=root.appendingPathComponent("content"),resume=TransferResume(source:source,destination:root.appendingPathComponent("content").path,upload:false)
  try client.downloadResumable(source,to:raw,state:resume,overwrite:false,verifyChecksum:verify);try checkpoint()
  guard let after=try client.attributes(source),signature(before)==signature(after) else{throw SFTPError.message("文本下载源发生变化，未发布目标")}
  return try body(raw,before)
 }
 static func download(_ source:String,to destination:String,client:RemoteFileClient,options:TextTransferOptions,overwrite:Bool,verify:Bool,checkpoint:@escaping()throws->Void)throws{
  let target=URL(fileURLWithPath:destination),temporary=target.deletingLastPathComponent().appendingPathComponent(".macscp-resume-"+UUID().uuidString)
  let publisher=try FTPDownloadTarget(destination:target,temporary:temporary,overwrite:overwrite,resume:false,retainPartial:false)
  try withRemoteSnapshot(source,client:client,verify:verify,checkpoint:checkpoint){raw,attributes in
   client.phase?("转换下载文本…");let input=try FTPUploadSource(raw),size=try convert(input,to:publisher.file,options:options,upload:false,checkpoint:checkpoint);try checkpoint()
   guard let after=try client.attributes(source),signature(after)==signature(attributes) else{throw SFTPError.message("文本转换时源发生变化，未发布目标")}
   let permissions=(try FileManager.default.attributesOfItem(atPath:raw.path)[.posixPermissions] as? NSNumber)?.uint32Value;try publisher.publish(expectedSize:size,modified:attributes.modified,permissions:permissions)
  }
 }
 static func completed(_ source:String,destination:String,upload:Bool,client:RemoteFileClient,options:TextTransferOptions,preparedSize:((UInt64)throws->Void)?=nil,checkpoint:@escaping()throws->Void)throws->Bool{
  let progress=client.progress;client.progress={amount in client.auxiliaryProgress?(amount)};defer{client.progress=progress}
  if upload{return try withSnapshot(source,options:options,upload:true,checkpoint:checkpoint){converted,_ in try preparedSize?((try FileManager.default.attributesOfItem(atPath:converted.path)[.size] as! NSNumber).uint64Value);return try StableChecksum.local(converted.path,checkpoint:checkpoint)==client.checksum(destination)}}
  return try withRemoteSnapshot(source,client:client,verify:true,checkpoint:checkpoint){raw,_ in try withSnapshot(raw.path,options:options,upload:false,checkpoint:checkpoint){converted,_ in try StableChecksum.local(converted.path,checkpoint:checkpoint)==StableChecksum.local(destination,checkpoint:checkpoint)}}
 }
}
