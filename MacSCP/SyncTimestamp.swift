import Foundation
import Darwin

// A preview binds each metadata-only action to its two files and parent paths.
struct SyncTimestampPlan {
 let candidate:SyncCandidate,localRoot:String,remoteRoot:String
 let requestedLocalRoot:String,requestedRemoteRoot:String
 let localPlan:LocalTrashPlan,remoteParents:[(String,UInt32)],remoteExpected:RemoteFileAttributes
 var desired:UInt32{UInt32(floor((candidate.upload == true ? candidate.local : candidate.remote)!.modified))}
 var localPath:String{SyncDeletionPlan.join(localRoot,candidate.relative)}
 var remotePath:String{SyncDeletionPlan.join(remoteRoot,candidate.relative)}
 static func prepare(_ candidate:SyncCandidate,localRoot:String,remoteRoot:String,client:RemoteFileClient)throws->Self {
  try SyncDeletionPlan.checkedRelative(candidate.relative)
  guard candidate.timestampOnly,!candidate.deletion,candidate.executable,!candidate.directory,let l=candidate.local,let r=candidate.remote,!l.directory,!r.directory,client.capabilities.contains(.timestampOnly) else{throw SFTPError.message("仅 SFTP 对应的普通文件支持只同步修改时间")}
  let source=candidate.upload == true ? l : r
  guard source.modified.isFinite,floor(source.modified)>=0,floor(source.modified)<=Double(UInt32.max) else{throw SFTPError.message("源时间超出 SFTP v3 的有效范围（1970–2106）")}
  let local=try LocalTrashPlan.canonicalDirectory(localRoot),remote=try client.canonical(remoteRoot)
  guard remote.hasPrefix("/"),!remote.contains("\0"),!remote.split(separator:"/").contains("..") else{throw SFTPError.message("远程同步根路径无效")}
  let file=SyncDeletionPlan.join(local,candidate.relative),parent=(file as NSString).deletingLastPathComponent
  let localPlan=try LocalTrashPlan.prepare(directory:parent,names:[(file as NSString).lastPathComponent])
  guard localPlan.directory==parent,localPlan.items.first?.signature.type==FileAttributeType.typeRegular.rawValue else{throw SFTPError.message("本地同步路径包含链接或被替换")}
  var remoteParents=[(String,UInt32)](),cursor=remote
  guard let rootNode=try client.attributes(cursor),rootNode.mode&0o170000==0o040000 else{throw SFTPError.message("远程同步目录不可用")};remoteParents.append((cursor,rootNode.mode))
  for component in candidate.relative.split(separator:"/").dropLast(){cursor=SyncDeletionPlan.join(cursor,String(component));guard let node=try client.attributes(cursor),node.mode&0o170000==0o040000 else{throw SFTPError.message("远程同步父路径含链接或非目录")};remoteParents.append((cursor,node.mode))}
  guard let expected=try client.attributes(SyncDeletionPlan.join(remote,candidate.relative)),expected.mode&0o170000==0o100000 else{throw SFTPError.message("远程同步文件不可用")}
  let plan=Self(candidate:candidate,localRoot:local,remoteRoot:remote,requestedLocalRoot:localRoot,requestedRemoteRoot:remoteRoot,localPlan:localPlan,remoteParents:remoteParents,remoteExpected:expected)
  try plan.validate(client:client);return plan
 }
 func selectingSource(upload:Bool)throws->Self {
  var selected=candidate;guard SyncComparison.resolve(&selected,upload:upload) else{throw SFTPError.message("所选源时间超出 SFTP v3 范围，请重新比较")}
  return Self(candidate:selected,localRoot:localRoot,remoteRoot:remoteRoot,requestedLocalRoot:requestedLocalRoot,requestedRemoteRoot:requestedRemoteRoot,localPlan:localPlan,remoteParents:remoteParents,remoteExpected:remoteExpected)
 }
 func validate(client:RemoteFileClient)throws {
  try client.checkpoint?()
  guard client.capabilities.contains(.timestampOnly),try LocalTrashPlan.canonicalDirectory(requestedLocalRoot)==localRoot,try client.canonical(requestedRemoteRoot)==remoteRoot else{throw SFTPError.message("时间戳预览后根路径或协议发生变化")}
  try localPlan.validateAncestors();for item in localPlan.items{try localPlan.validate(item)}
  for (path,mode) in remoteParents{try client.checkpoint?();guard try client.attributes(path)?.mode==mode else{throw SFTPError.message("时间戳预览后远程父路径发生变化")}}
  try SyncComparison.verify(candidate,localRoot:localRoot,remoteRoot:remoteRoot,localSnapshot:[:],remoteSnapshot:[:],client:client)
  guard let now=try client.attributes(remotePath),now.mode==remoteExpected.mode,now.size==remoteExpected.size,now.modified==remoteExpected.modified else{throw SFTPError.message("时间戳预览后远程文件发生变化")}
 }
 private func matches(_ value:stat,_ expected:LocalTrashSignature,modified:UInt32?=nil)->Bool {
  guard UInt32(value.st_mode)&0o170000==0o100000,UInt32(bitPattern:value.st_dev)==UInt32(truncatingIfNeeded:expected.device),UInt64(value.st_ino)==expected.inode,value.st_size>=0,UInt64(value.st_size)==expected.size,UInt32(value.st_mode)&0o7777==expected.permissions&0o7777 else{return false}
  let time=Double(value.st_mtimespec.tv_sec)+Double(value.st_mtimespec.tv_nsec)/1_000_000_000
  if let modified=modified{return value.st_mtimespec.tv_sec==modified && value.st_mtimespec.tv_nsec==0}
  return expected.modified.map{abs($0.timeIntervalSince1970-time)<0.000001} ?? false
 }
 func execute(client:RemoteFileClient,checkpoint:()throws->Void)throws {
  try checkpoint();try validate(client:client);try checkpoint()
  if candidate.upload == true {
   try withoutActuallyEscaping(checkpoint){point in try client.setModificationTime(remotePath,to:desired,expected:remoteExpected,beforeCommit:{try point();try self.validate(client:client)})}
  }else{
   // Anchor the directory descriptor and never follow the final component; no read permission on file data is needed.
   let parent=open(localPlan.directory,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC)
   guard parent>=0 else{throw NSError(domain:NSPOSIXErrorDomain,code:Int(errno))};defer{close(parent)}
   var directory=stat();guard fstat(parent,&directory)==0,let expectedParent=localPlan.ancestors.last?.signature,UInt32(bitPattern:directory.st_dev)==UInt32(truncatingIfNeeded:expectedParent.device),UInt64(directory.st_ino)==expectedParent.inode else{throw SFTPError.message("打开后本地父目录被替换")}
   let name=(localPath as NSString).lastPathComponent,signature=localPlan.items[0].signature
   var before=stat();guard fstatat(parent,name,&before,AT_SYMLINK_NOFOLLOW)==0,matches(before,signature) else{throw SFTPError.message("提交时间前本地文件被替换")}
   try validate(client:client);try checkpoint()
   var current=stat();guard fstatat(parent,name,&current,AT_SYMLINK_NOFOLLOW)==0,matches(current,signature) else{throw SFTPError.message("提交时间前本地文件发生变化")}
   let values=[timespec(tv_sec:0,tv_nsec:Int(UTIME_OMIT)),timespec(tv_sec:time_t(desired),tv_nsec:0)]
   let result=values.withUnsafeBufferPointer{utimensat(parent,name,$0.baseAddress,AT_SYMLINK_NOFOLLOW)}
   guard result==0 else{throw NSError(domain:NSPOSIXErrorDomain,code:Int(errno))}
   var after=stat();guard fstatat(parent,name,&after,AT_SYMLINK_NOFOLLOW)==0,matches(after,signature,modified:desired),after.st_atimespec.tv_sec==current.st_atimespec.tv_sec,after.st_atimespec.tv_nsec==current.st_atimespec.tv_nsec else{throw SFTPError.message("修改后本地文件或时间无法确认，请重新比较")}
   try localPlan.validateAncestors()
  }
 }
}
