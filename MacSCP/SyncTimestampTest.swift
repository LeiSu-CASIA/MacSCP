import Foundation
import Darwin
@main struct SyncTimestampTests {
 static func check(_ value:Bool,file:StaticString = #file,line:UInt = #line){precondition(value,file:file,line:line)}
 static func refused(_ action:()throws->Void){do{try action();fatalError("invalid timestamp action accepted")}catch{}}
 static func main()throws {
  let old=SyncNode(directory:false,size:3,modified:100,checksum:"cached-a"),new=SyncNode(directory:false,size:7,modified:200,checksum:"cached-b"),dir=SyncNode(directory:true,size:0,modified:10)
  func settings(_ direction:SyncDirection = .upload,sameSize:Bool=false)->SyncSettings{SyncSettings(direction:direction,comparison:SyncComparisonOptions(fileMode:.timestamps,timeTolerance:0,timestampSameSizeOnly:sameSize))}
  let local=["file":old,"local-only":new,"folder":dir,"folder/child":new,"type":dir],remote=["file":new,"remote-only":old,"folder":dir,"folder/child":old,"type":old]
  let upload=try SyncComparison.plannedCandidates(local:local,remote:remote,settings:settings())
  check(upload.count==3 && upload.filter{$0.executable}.count==2 && upload.allSatisfy{$0.timestampOnly && !$0.deletion})
  let file=upload.first{$0.relative=="file"}!;check(file.upload==true && file.local?.checksum==nil && file.remote?.checksum==nil && file.label.contains("仅设置远程"))
  let both=try SyncComparison.plannedCandidates(local:local,remote:remote,settings:settings(.both))
  check(both.first{$0.relative=="file"}?.upload==false && both.first{$0.relative=="folder/child"}?.upload==true)
  let same=try SyncComparison.plannedCandidates(local:local,remote:remote,settings:settings(sameSize:true));check(same.filter{$0.executable}.isEmpty)
  var item=file;check(SyncComparison.resolve(&item,upload:false) && item.upload==false)
  var invalid=SyncCandidate(relative:"range",local:SyncNode(directory:false,size:3,modified:Double(UInt32.max)+1),remote:old,upload:false,selected:true,typeConflict:false,timestampOnly:true);check(!SyncComparison.resolve(&invalid,upload:true) && invalid.upload==false)
  check(try SyncComparison.plannedCandidates(local:["file":old],remote:["file":new],settings:settings(.download)).first?.upload==false)
  let rules=TransferPolicy(exclude:"folder/"),predicate=try rules.predicate(),allows:(String,Bool)->Bool={predicate($0,($0 as NSString).lastPathComponent,$1)}
  check(try SyncComparison.plannedCandidates(local:local,remote:remote,settings:settings(),allows:allows).count==2)
  for config in [SyncComparisonOptions(fileMode:.timestamps,modificationTime:false),SyncComparisonOptions(fileMode:.timestamps,size:true),SyncComparisonOptions(fileMode:.timestamps,checksum:true),SyncComparisonOptions(fileMode:.timestamps,existingOnly:true),SyncComparisonOptions(timestampSameSizeOnly:true)]{refused{_ = try SyncSettings(comparison:config).validated()}}
  refused{_ = try SyncSettings(comparison:settings().comparison,cleanup:true).validated()}
  for value in [-1.0,Double(UInt32.max)+1,.infinity]{refused{_ = try SyncComparison.plannedCandidates(local:["file":SyncNode(directory:false,size:3,modified:value)],remote:["file":old],settings:settings())}}
  let suite="timestamp-migration-"+UUID().uuidString,defaults=UserDefaults(suiteName:suite)!
  defer{defaults.removePersistentDomain(forName:suite)}
  let saved=settings(.both,sameSize:true);try saved.save(to:defaults);check(SyncSettings.load(from:defaults)==saved)
  let legacy=SyncSettings(direction:.download,comparison:SyncComparisonOptions(fileMode:.mirror,size:true),cleanup:true)
  var object=try JSONSerialization.jsonObject(with:JSONEncoder().encode(legacy)) as! [String:Any],comparison=object["comparison"] as! [String:Any];comparison.removeValue(forKey:"timestampSameSizeOnly");object["comparison"]=comparison
  defaults.set(try JSONSerialization.data(withJSONObject:object),forKey:"syncOptions");check(SyncSettings.load(from:defaults)==legacy)

  let fm=FileManager.default,root=fm.temporaryDirectory.appendingPathComponent("sync-timestamp-"+UUID().uuidString),l=root.appendingPathComponent("local"),r=root.appendingPathComponent("remote"),outside=root.appendingPathComponent("outside")
  for base in [l,r,outside]{try fm.createDirectory(at:base,withIntermediateDirectories:true)};defer{try? fm.removeItem(at:root)}
  let client=try SFTPClient(command:"/usr/libexec/sftp-server",arguments:[]);defer{client.close()};var progress:UInt64=0,auxiliary:UInt64=0
  client.progress={progress+=$0};client.auxiliaryProgress={auxiliary+=$0}
  func put(_ base:URL,_ name:String,_ text:String,_ mtime:Int)throws{let path=base.appendingPathComponent(name);try fm.createDirectory(at:path.deletingLastPathComponent(),withIntermediateDirectories:true);try Data(text.utf8).write(to:path);let times=[timespec(tv_sec:1600000000,tv_nsec:123456789),timespec(tv_sec:mtime,tv_nsec:0)];let result=times.withUnsafeBufferPointer{utimensat(AT_FDCWD,path.path,$0.baseAddress,AT_SYMLINK_NOFOLLOW)};guard result==0 else{throw NSError(domain:NSPOSIXErrorDomain,code:Int(errno))}}
  func statFile(_ file:URL)throws->stat{var value=stat();guard lstat(file.path,&value)==0 else{throw NSError(domain:NSPOSIXErrorDomain,code:Int(errno))};return value}
  func plan(_ name:String,_ direction:SyncDirection = .upload)throws->SyncTimestampPlan{let ls=try SyncPlanner.local(l.path),rs=try SyncPlanner.remote(r.path,client:client);let rows=try SyncComparison.plannedCandidates(local:ls,remote:rs,settings:settings(direction));return try SyncTimestampPlan.prepare(rows.first{$0.relative==name}!,localRoot:l.path,remoteRoot:r.path,client:client)}
  try put(l,"upload.txt","source content",1700000000);try put(r,"upload.txt","target different",1800000000)
  let up=try plan("upload.txt"),before=try statFile(r.appendingPathComponent("upload.txt"))
  try up.execute(client:client,checkpoint:{})
  let after=try statFile(r.appendingPathComponent("upload.txt"));check(after.st_ino==before.st_ino && after.st_size==before.st_size && after.st_mode==before.st_mode && after.st_mtimespec.tv_sec==1700000000 && after.st_atimespec.tv_sec==1600000000)
  check(try Data(contentsOf:r.appendingPathComponent("upload.txt"))==Data("target different".utf8))
  try put(l,"download.txt","keep local",1800000000);try put(r,"download.txt","remote source",1700000000)
  let down=try plan("download.txt",.download),localBefore=try statFile(l.appendingPathComponent("download.txt"))
  try down.execute(client:client,checkpoint:{})
  let localAfter=try statFile(l.appendingPathComponent("download.txt"));check(localAfter.st_ino==localBefore.st_ino && localAfter.st_mode==localBefore.st_mode && localAfter.st_mtimespec.tv_sec==1700000000 && localAfter.st_atimespec.tv_sec==localBefore.st_atimespec.tv_sec && localAfter.st_atimespec.tv_nsec==123456789)
  check(try Data(contentsOf:l.appendingPathComponent("download.txt"))==Data("keep local".utf8))
  for direction in [SyncDirection.upload,.download]{let name=direction == .upload ? "remote-no-read" : "local-no-read";try put(l,name,"local",1700000000);try put(r,name,"remote",1800000000);let target=direction == .upload ? r.appendingPathComponent(name) : l.appendingPathComponent(name);try fm.setAttributes([.posixPermissions:0],ofItemAtPath:target.path);let action=try plan(name,direction);try action.execute(client:client,checkpoint:{});let changed=try statFile(target);check(changed.st_mode&0o777==0 && changed.st_mtimespec.tv_sec==(direction == .upload ? 1700000000 : 1800000000));try fm.setAttributes([.posixPermissions:0o600],ofItemAtPath:target.path)}
  try put(l,"stale","source",1700000000);try put(r,"stale","target",1800000000);let stale=try plan("stale");try put(r,"stale","changed target",1800000001)
  refused{try stale.execute(client:client,checkpoint:{})};check(try statFile(r.appendingPathComponent("stale")).st_mtimespec.tv_sec==1800000001)
  try put(l,"cancel","source",1700000000);try put(r,"cancel","target",1800000000);let cancelled=try plan("cancel")
  refused{try cancelled.execute(client:client,checkpoint:{throw SFTPError.message("fixture stopped")})};check(try statFile(r.appendingPathComponent("cancel")).st_mtimespec.tv_sec==1800000000)
  try put(l,"changed-source","source",1700000000);try put(r,"changed-source","target",1800000000);let changedSource=try plan("changed-source");var points=0
  refused{try changedSource.execute(client:client,checkpoint:{points+=1;if points==3{try put(l,"changed-source","changed source",1700000001)}})}
  check(try statFile(r.appendingPathComponent("changed-source")).st_mtimespec.tv_sec==1800000000)
  try put(l,"identity","keep",1800000000);try put(r,"identity","source",1700000000);let identity=try plan("identity",.download),held=root.appendingPathComponent("held-file")
  try fm.moveItem(at:l.appendingPathComponent("identity"),to:held);try put(l,"identity","keep",1800000000)
  refused{try identity.execute(client:client,checkpoint:{})};check(try statFile(l.appendingPathComponent("identity")).st_mtimespec.tv_sec==1800000000)
  try put(l,"nested/file","local",1800000000);try put(r,"nested/file","remote",1700000000);try put(outside,"file","outside",1800000000);let parent=try plan("nested/file",.download)
  try fm.moveItem(at:l.appendingPathComponent("nested"),to:root.appendingPathComponent("held-parent"));try fm.createSymbolicLink(atPath:l.appendingPathComponent("nested").path,withDestinationPath:outside.path)
  refused{try parent.execute(client:client,checkpoint:{})};check(try statFile(outside.appendingPathComponent("file")).st_mtimespec.tv_sec==1800000000)
  check(progress==0 && auxiliary==0)
  print("PASS: timestamp-only directions and same-size/missing/type/mask rules, invalid state/range rejection, 0.1.21 preference migration; real local SFTP metadata changes preserve bytes/inode/mode and reported access time, nonreadable owned files work, stale/cancel/source/inode/ancestor changes refused, no transfer progress")
 }
}
