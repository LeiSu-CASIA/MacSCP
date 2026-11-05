import Foundation
import Darwin

enum RelayStorage {
 static var directory:URL{FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/MacSCP/RelayStaging",isDirectory:true)}
 static func prepare(at root:URL=directory)throws->URL{
  try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
  let attrs=try FileManager.default.attributesOfItem(atPath:root.path)
  guard attrs[.type] as? FileAttributeType == .typeDirectory,(attrs[.ownerAccountID] as? NSNumber)?.uint32Value==geteuid(),let mode=attrs[.posixPermissions] as? NSNumber,mode.intValue & 0o077==0 else{throw SFTPError.message("中转存储目录类型、所有者或权限无效")}
  return root
 }
}

struct RelayRecord:Codable {
 let id:UUID;let staging:String;let download:TransferRecord;let upload:TransferRecord
 func validated()throws->RelayRecord{
  _ = try download.validated();_ = try upload.validated()
  let root=URL(fileURLWithPath:staging),parent=root.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL
  let allowed=[FileManager.default.temporaryDirectory,RelayStorage.directory].map{$0.resolvingSymlinksInPath().standardizedFileURL}
  let prefix="MacSCP-Relay-",name=root.lastPathComponent
  guard allowed.contains(parent),name.hasPrefix(prefix),UUID(uuidString:String(name.dropFirst(prefix.count))) != nil,
    root.path==staging,download.source != "/",upload.destination != "/",!download.up,upload.up,download.id != upload.id,
    download.directory==upload.directory,download.destination==upload.source,
    upload.source==root.appendingPathComponent((download.source as NSString).lastPathComponent).path else{throw SFTPError.message("中转恢复记录的阶段或暂存路径无效")}
  return self
 }
 func checkStaging(inspectContents:Bool=true)throws{
  _ = try validated()
  let attrs=try FileManager.default.attributesOfItem(atPath:staging)
  guard attrs[.type] as? FileAttributeType == .typeDirectory,
    (attrs[.ownerAccountID] as? NSNumber)?.uint32Value==geteuid(),
    let permissions=attrs[.posixPermissions] as? NSNumber,permissions.intValue & 0o077==0 else{throw SFTPError.message("中转目录已被替换或权限不安全，停止恢复")}
  guard inspectContents else{return}
  var files=Set(download.completed+download.resumes.flatMap{[$0.destination,$0.temporaryPath]})
  var directories=Set(download.created+(download.plannedDirectories ?? [])+[staging])
  for path in files.union(directories){var parent=URL(fileURLWithPath:path).deletingLastPathComponent();while parent.path.hasPrefix(staging+"/"){directories.insert(parent.path);parent=parent.deletingLastPathComponent()}}
  files.subtract(directories)
  var inspected=0
  func inspect(_ path:String)throws{
   for child in try FileManager.default.contentsOfDirectory(atPath:path){inspected+=1;guard inspected<=100000 else{throw SFTPError.message("中转目录项目数过多")};let full=URL(fileURLWithPath:path).appendingPathComponent(child).path;let type=try FileManager.default.attributesOfItem(atPath:full)[.type] as? FileAttributeType
    if type == .typeDirectory{guard directories.contains(full) else{throw SFTPError.message("中转目录出现未记录的文件夹，停止恢复")};try inspect(full)}
    else{guard type == .typeRegular,files.contains(full) else{throw SFTPError.message("中转目录出现链接或未记录文件，停止恢复")}}
   }
  }
  try inspect(staging)
 }
 func discardLocal()throws{
  _ = try validated()
  // attributesOfItem also sees a broken symlink, which must not be followed.
  do{try checkStaging(inspectContents:false)}catch let error as NSError where error.domain==NSCocoaErrorDomain && error.code==NSFileReadNoSuchFileError{return}
  try FileManager.default.removeItem(atPath:staging)
 }
}

final class RelayJournal {
 private let url:URL;private let lock=NSLock();private var records=[UUID:RelayRecord]();private var lastWrite=Date.distantPast;private var descriptor:Int32 = -1
 init(url:URL)throws{
  self.url=url;try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
  descriptor=Darwin.open(url.path+".lock",O_CREAT|O_RDWR,0o600)
  guard descriptor>=0 else{throw SFTPError.message("无法创建中转恢复锁")}
  guard flock(descriptor,LOCK_EX|LOCK_NB)==0 else{Darwin.close(descriptor);descriptor = -1;throw SFTPError.message("另一实例正在管理中转恢复记录")}
  do{if FileManager.default.fileExists(atPath:url.path){let handle=try FileHandle(forReadingFrom:url);defer{try? handle.close()};let data=try handle.read(upToCount:32*1024*1024+1) ?? Data();guard data.count<=32*1024*1024 else{throw SFTPError.message("中转恢复文件过大")};let list=try JSONDecoder().decode([RelayRecord].self,from:data);guard list.count<=5000 else{throw SFTPError.message("中转恢复记录数量过多")};for record in list{let item=try record.validated();guard records[item.id]==nil else{throw SFTPError.message("中转恢复记录重复")};records[item.id]=item}}}catch{flock(descriptor,LOCK_UN);Darwin.close(descriptor);descriptor = -1;throw error}
 }
 deinit{if descriptor>=0{flock(descriptor,LOCK_UN);Darwin.close(descriptor)}}
 func list()->[RelayRecord]{lock.lock();defer{lock.unlock()};return records.values.sorted{$0.id.uuidString<$1.id.uuidString}}
 func save(_ record:RelayRecord,force:Bool=false)throws{let item=try record.validated();lock.lock();defer{lock.unlock()};guard records[item.id] != nil || records.count<5000 else{throw SFTPError.message("中转恢复任务达到数量上限")};records[item.id]=item;if force || Date().timeIntervalSince(lastWrite)>=1{try persist()}}
 func remove(_ id:UUID)throws{lock.lock();defer{lock.unlock()};records.removeValue(forKey:id);try persist()}
 func flush()throws{lock.lock();defer{lock.unlock()};try persist()}
 private func persist()throws{let data=try JSONEncoder().encode(records.values.sorted{$0.id.uuidString<$1.id.uuidString});guard data.count<=32*1024*1024 else{throw SFTPError.message("中转恢复记录超过文件大小上限")};try data.write(to:url,options:.atomic);try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:url.path);lastWrite=Date()}
}
