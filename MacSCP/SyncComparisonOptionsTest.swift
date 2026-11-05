import Foundation
@main struct SyncComparisonOptionsTests {
 static func check(_ value:Bool,file:StaticString = #file,line:UInt = #line){precondition(value,file:file,line:line)}
 static func refused(_ action:()throws->Void){do{try action();fatalError("invalid comparison accepted")}catch{}}
 static func main()throws {
  let old=SyncNode(directory:false,size:3,modified:100,checksum:"old"),new=SyncNode(directory:false,size:8,modified:200,checksum:"new"),sameTime=SyncNode(directory:false,size:8,modified:100,checksum:"new"),dir=SyncNode(directory:true,size:0,modified:0)
  func plan(_ local:SyncNode,_ remote:SyncNode,_ comparison:SyncComparisonOptions=SyncComparisonOptions(),_ direction:SyncDirection = .upload)throws->[SyncCandidate]{try SyncComparison.plannedCandidates(local:["file":local],remote:["file":remote],settings:SyncSettings(direction:direction,comparison:comparison))}
  check(try plan(old,new).isEmpty)
  check(try plan(new,old).count==1)
  let mirror=SyncComparisonOptions(fileMode:.mirror)
  let mirrored=try plan(old,new,mirror);check(mirrored.count==1 && mirrored[0].mirror && mirrored[0].label.contains("镜像替换"))
  check(try plan(new,old,mirror,.download).first?.upload==false)
  check(try plan(old,sameTime).isEmpty)
  check(try plan(old,sameTime,SyncComparisonOptions(size:true)).count==1)
  check(try plan(old,new,SyncComparisonOptions(size:true)).isEmpty) // Older source is protected by time precedence.
  check(try plan(old,new,SyncComparisonOptions(modificationTime:false,size:true)).count==1)
  check(try plan(old,sameTime,SyncComparisonOptions(modificationTime:false,checksum:true)).count==1)
  check(try plan(old,new,SyncComparisonOptions(checksum:true)).isEmpty)
  check(try plan(old,sameTime,SyncComparisonOptions(checksum:true)).first?.selected==true)
  let sameHash=SyncNode(directory:false,size:3,modified:200,checksum:"old")
  check(try plan(old,sameHash,SyncComparisonOptions(fileMode:.mirror,checksum:true)).count==1)
  check(try plan(old,sameHash,SyncComparisonOptions(modificationTime:false,checksum:true)).isEmpty)
  check(try plan(old,new,SyncComparisonOptions(fileMode:.mirror,modificationTime:false)).isEmpty)
  let missing=try SyncComparison.plannedCandidates(local:["new/file":old,"new":dir],remote:[:],settings:SyncSettings(comparison:SyncComparisonOptions(modificationTime:false)))
  check(missing.count==1 && missing[0].directory && missing[0].relative=="new")
  check(try SyncComparison.plannedCandidates(local:["new":dir,"new/file":old],remote:[:],settings:SyncSettings(comparison:SyncComparisonOptions(existingOnly:true))).isEmpty)
  let existing=try SyncComparison.plannedCandidates(local:["update":new,"left":old],remote:["update":old,"right":old],settings:SyncSettings(comparison:SyncComparisonOptions(existingOnly:true),cleanup:true))
  check(existing.count==2 && existing.contains{$0.relative=="update" && !$0.deletion} && existing.contains{$0.relative=="right" && $0.deletion})
  let both=try SyncComparison.plannedCandidates(local:["update":new,"left":old],remote:["update":old,"right":old],settings:SyncSettings(direction:.both,comparison:SyncComparisonOptions(existingOnly:true)))
  check(both.count==1 && both[0].relative=="update" && both[0].upload==true)
  let equalSecond=SyncNode(directory:false,size:3,modified:100.999),justNewer=SyncNode(directory:false,size:3,modified:101)
  check(try plan(equalSecond,old,SyncComparisonOptions(timeTolerance:0)).isEmpty)
  check(try plan(justNewer,old,SyncComparisonOptions(timeTolerance:0)).count==1)
  check(try plan(justNewer,old,SyncComparisonOptions(timeTolerance:2)).isEmpty)
  check(try plan(justNewer,old,SyncComparisonOptions(timeTolerance:0),.both).first?.upload==true)
  for tolerance in [-1.0,301,.infinity,.nan]{refused{_ = try SyncSettings(comparison:SyncComparisonOptions(timeTolerance:tolerance)).validated()}}
  for config in [SyncComparisonOptions(fileMode:.mirror),SyncComparisonOptions(modificationTime:false),SyncComparisonOptions(size:true),SyncComparisonOptions(checksum:true)]{refused{_ = try SyncSettings(direction:.both,comparison:config).validated()}}
  refused{_ = try SyncSettings(direction:.both,cleanup:true).validated()}
  let noHash=SyncNode(directory:false,size:3,modified:100)
  refused{_ = try plan(noHash,noHash,SyncComparisonOptions(checksum:true))}
  let rule=TransferPolicy(exclude:"private/;*.bin"),predicate=try rule.predicate(),allows:(String,Bool)->Bool={predicate($0,($0 as NSString).lastPathComponent,$1)}
  let snapshot=["a.txt":old,"private":dir,"private/secret.txt":noHash,"data.bin":noHash]
  check(SyncComparison.checksumPaths(snapshot,allows:allows)==["a.txt"])
  check(try SyncComparison.plannedCandidates(local:snapshot,remote:snapshot,settings:SyncSettings(comparison:SyncComparisonOptions(checksum:true)),allows:allows).isEmpty)

  let suite="sync-settings-"+UUID().uuidString,defaults=UserDefaults(suiteName:suite)!
  defer{defaults.removePersistentDomain(forName:suite)}
  check(SyncSettings.load(from:defaults)==nil)
  let settings=SyncSettings(direction:.download,comparison:SyncComparisonOptions(fileMode:.mirror,modificationTime:false,size:true,checksum:true,existingOnly:true,timeTolerance:0),cleanup:true)
  try settings.save(to:defaults);check(SyncSettings.load(from:defaults)==settings)
  let invalid=Data("{\"direction\":\"unknown\"}".utf8);defaults.set(invalid,forKey:"syncOptions");check(SyncSettings.load(from:defaults)==nil)
  refused{try SyncSettings(direction:.both,cleanup:true).save(to:defaults)};check(defaults.data(forKey:"syncOptions")==invalid)

  // A partially hashed subtree must revalidate exactly the preview's hash set.
  let fm=FileManager.default,root=fm.temporaryDirectory.appendingPathComponent("sync-partial-hash-"+UUID().uuidString),local=root.appendingPathComponent("local"),remote=root.appendingPathComponent("remote")
  try fm.createDirectory(at:local.appendingPathComponent("folder"),withIntermediateDirectories:true);try fm.createDirectory(at:remote,withIntermediateDirectories:true);defer{try? fm.removeItem(at:root)}
  try Data("visible".utf8).write(to:local.appendingPathComponent("folder/keep.txt"));try Data("excluded".utf8).write(to:local.appendingPathComponent("folder/data.bin"))
  let client=try SFTPClient(command:"/usr/libexec/sftp-server",arguments:[]);defer{client.close()}
  let plain=try SyncPlanner.local(local.path),l=try SyncChecksums.local(plain,root:local.path,paths:SyncComparison.checksumPaths(plain,allows:allows)),r=try SyncPlanner.remote(remote.path,client:client)
  check(l["folder/keep.txt"]?.checksum != nil && l["folder/data.bin"]?.checksum==nil)
  let grouped=try SyncComparison.plannedCandidates(local:l,remote:r,settings:SyncSettings(comparison:SyncComparisonOptions(checksum:true)),allows:allows)
  check(grouped.count==1 && grouped[0].directory)
  try SyncComparison.verify(grouped[0],localRoot:local.path,remoteRoot:remote.path,localSnapshot:l,remoteSnapshot:r,client:client)
  let time=try fm.attributesOfItem(atPath:local.appendingPathComponent("folder/keep.txt").path)[.modificationDate]!
  try Data("changed".utf8).write(to:local.appendingPathComponent("folder/keep.txt"));try fm.setAttributes([.modificationDate:time],ofItemAtPath:local.appendingPathComponent("folder/keep.txt").path)
  refused{try SyncComparison.verify(grouped[0],localRoot:local.path,remoteRoot:remote.path,localSnapshot:l,remoteSnapshot:r,client:client)}
  print("PASS: mirror versus newer-only, time/size/hash precedence and zero-criteria rules, existing-only with cleanup, both-direction/tolerance validation, incomplete hash refusal, explicit preference roundtrip, ancestor mask hash scope and real SFTP partial-hash stale subtree checks")
 }
}
