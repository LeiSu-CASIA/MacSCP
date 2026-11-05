import Foundation
@main struct SyncDeletionTests {
 static func check(_ value:Bool,file:StaticString = #file,line:UInt = #line){precondition(value,file:file,line:line)}
 static func refused(_ action:()throws->Void){do{try action();fatalError("unsafe cleanup accepted")}catch{}}
 static func main()throws {
  let fm=FileManager.default,root=fm.temporaryDirectory.appendingPathComponent("sync-deletion-"+UUID().uuidString),local=root.appendingPathComponent("local"),remote=root.appendingPathComponent("remote"),bin=root.appendingPathComponent("fixture-recycle")
  for dir in [local,remote,bin]{try fm.createDirectory(at:dir,withIntermediateDirectories:true)};defer{try? fm.removeItem(at:root)}
  let client=try SFTPClient(command:"/usr/libexec/sftp-server",arguments:[]);defer{client.close()}
  func put(_ base:URL,_ path:String,_ text:String="old")throws{let file=base.appendingPathComponent(path);try fm.createDirectory(at:file.deletingLastPathComponent(),withIntermediateDirectories:true);try Data(text.utf8).write(to:file)}
  func plan(_ path:String,_ mode:SyncDirection = .upload,_ digest:Bool=false)throws->SyncDeletionPlan{
   var l=try SyncPlanner.local(local.path),r=try SyncPlanner.remote(remote.path,client:client)
   if digest{l=try SyncChecksums.local(l,root:local.path);r=try SyncChecksums.remote(r,root:remote.path,client:client)}
   let actions=SyncComparison.candidates(local:l,remote:r,direction:mode,deleteExtraneous:true)
   let action=actions.first{$0.relative==path && $0.deletion}!
   return try SyncDeletionPlan.prepare(action,localRoot:local.path,remoteRoot:remote.path,localSnapshot:l,remoteSnapshot:r,client:client)
  }
  func execute(_ plan:SyncDeletionPlan,_ checkpoint:()throws->Void = {})throws{try plan.execute(client:client,checkpoint:checkpoint,trash:{url in try fm.moveItem(at:url,to:bin.appendingPathComponent(UUID().uuidString+"-"+url.lastPathComponent))})}
  let node=SyncNode(directory:false,size:3,modified:1),dir=SyncNode(directory:true,size:0,modified:1)
  let ls=["local":node],rs=["remote":node,"tree":dir,"tree/a":node]
  check(!SyncComparison.candidates(local:ls,remote:rs,direction:.upload).contains{$0.deletion})
  check(!SyncComparison.candidates(local:ls,remote:rs,direction:.both,deleteExtraneous:true).contains{$0.deletion})
  let actions=SyncComparison.candidates(local:ls,remote:rs,direction:.upload,deleteExtraneous:true)
  check(actions.filter{$0.deletion}.map{$0.relative}==["remote","tree"] && actions.first{$0.relative=="tree"}!.directory)
  var deletion=actions.first{$0.deletion}!;SyncComparison.resolve(&deletion,upload:false);check(deletion.deletion && deletion.upload==true)
  let masked=["folder":dir,"folder/drop.txt":node,"folder/keep.bin":node,"folder/private":dir,"folder/private/keep.txt":node]
  let rule=TransferPolicy(include:"*.txt",exclude:"private/");let permits=try rule.predicate()
  let filtered=SyncComparison.candidates(local:[:],remote:masked,direction:.upload,deleteExtraneous:true,allows:{permits($0,($0 as NSString).lastPathComponent,$1)})
  check(filtered.count==1 && filtered[0].relative=="folder/drop.txt" && filtered[0].deletion)
  for bad in ["", "/", "/abs", "a/../b", "a//b", "a/.", "\0"]{refused{try SyncDeletionPlan.checkedRelative(bad)}}

  try put(remote,"masked/drop.txt");try put(remote,"masked/keep.bin");try put(remote,"masked/private/keep.txt")
  let maskLocal=try SyncPlanner.local(local.path),maskRemote=try SyncPlanner.remote(remote.path,client:client)
  let maskActions=SyncComparison.candidates(local:maskLocal,remote:maskRemote,direction:.upload,deleteExtraneous:true,allows:{permits($0,($0 as NSString).lastPathComponent,$1)})
  check(maskActions.count==1 && maskActions[0].relative=="masked/drop.txt")
  let maskPlan=try SyncDeletionPlan.prepare(maskActions[0],localRoot:local.path,remoteRoot:remote.path,localSnapshot:maskLocal,remoteSnapshot:maskRemote,client:client)
  try execute(maskPlan);check(!fm.fileExists(atPath:remote.appendingPathComponent("masked/drop.txt").path) && fm.fileExists(atPath:remote.appendingPathComponent("masked/keep.bin").path) && fm.fileExists(atPath:remote.appendingPathComponent("masked/private/keep.txt").path))
  try put(remote,"tree/a");try put(remote,"tree/nested/b");let ready=try plan("tree")
  try execute(ready);check(!fm.fileExists(atPath:remote.appendingPathComponent("tree").path))
  try put(remote,"changed/a");try put(remote,"changed/b");let changed=try plan("changed")
  try put(remote,"changed/b","new bytes")
  refused{try execute(changed)};check(fm.fileExists(atPath:remote.appendingPathComponent("changed/a").path))
  try put(remote,"new-child/a");let added=try plan("new-child");try put(remote,"new-child/later")
  refused{try execute(added)};check(fm.fileExists(atPath:remote.appendingPathComponent("new-child/a").path))
  try put(remote,"appeared");let appeared=try plan("appeared");try put(local,"appeared","protect source")
  refused{try execute(appeared)};check(fm.fileExists(atPath:remote.appendingPathComponent("appeared").path))
  try put(remote,"dangling");let dangling=try plan("dangling")
  try fm.createSymbolicLink(atPath:local.appendingPathComponent("dangling").path,withDestinationPath:root.appendingPathComponent("missing").path)
  refused{try execute(dangling)};check(fm.fileExists(atPath:remote.appendingPathComponent("dangling").path));try fm.removeItem(at:local.appendingPathComponent("dangling"))
  try put(remote,"digest","abc");let digest=try plan("digest",.upload,true),time=try fm.attributesOfItem(atPath:remote.appendingPathComponent("digest").path)[.modificationDate] as! Date
  try put(remote,"digest","xyz");try fm.setAttributes([.modificationDate:time],ofItemAtPath:remote.appendingPathComponent("digest").path)
  refused{try execute(digest)};check(try Data(contentsOf:remote.appendingPathComponent("digest"))==Data("xyz".utf8))

  try put(local,"recycle/nested/file");let recycle=try plan("recycle",.download)
  try execute(recycle);check(!fm.fileExists(atPath:local.appendingPathComponent("recycle").path));check(try fm.contentsOfDirectory(at:bin,includingPropertiesForKeys:nil).contains{fm.fileExists(atPath:$0.appendingPathComponent("nested/file").path)})
  try put(local,"identity/a");let identity=try plan("identity",.download),target=local.appendingPathComponent("identity/a"),attrs=try fm.attributesOfItem(atPath:target.path)
  try fm.moveItem(at:target,to:root.appendingPathComponent("held"));try put(local,"identity/a");try fm.setAttributes([.modificationDate:attrs[.modificationDate]!],ofItemAtPath:target.path)
  refused{try execute(identity)};check(fm.fileExists(atPath:target.path))
  try put(local,"recycle-new/a");let recycleNew=try plan("recycle-new",.download);try put(local,"recycle-new/late")
  refused{try execute(recycleNew)};check(fm.fileExists(atPath:local.appendingPathComponent("recycle-new/a").path))
  try put(local,"parent/item");try fm.createDirectory(at:remote.appendingPathComponent("parent"),withIntermediateDirectories:true)
  let parent=try plan("parent/item",.download)
  try fm.moveItem(at:local.appendingPathComponent("parent"),to:root.appendingPathComponent("held-parent"));try fm.createSymbolicLink(atPath:local.appendingPathComponent("parent").path,withDestinationPath:root.appendingPathComponent("held-parent").path)
  refused{try execute(parent)};check(fm.fileExists(atPath:root.appendingPathComponent("held-parent/item").path));try fm.removeItem(at:local.appendingPathComponent("parent"))

  try put(remote,"cancel/a");try put(remote,"cancel/b");let cancel=try plan("cancel")
  let job=TransferJob(up:true,source:"unused",destination:"unused",directory:true,size:0);job.customAction="删除远程";job.retryAllowed=false;job.factory={try SFTPClient(command:"/usr/libexec/sftp-server",arguments:[])}
  job.customOperation={c,checkpoint in try cancel.execute(client:c,checkpoint:{if !fm.fileExists(atPath:remote.appendingPathComponent("cancel/a").path){job.cancel()};try checkpoint()},trash:{_ in fatalError("real trash must never be used")})}
  job.execute({});check(job.wasCancelled && job.finished && fm.fileExists(atPath:remote.appendingPathComponent("cancel/b").path) && job.column("direction")=="删除远程")
  job.recoverySite=Session(name:"fixture",host:"example.invalid",user:"fixture",port:22,key:"");check(job.recoveryRecord()==nil)
  let never=TransferJob(up:true,source:"unused",destination:"unused",directory:false,size:0);never.factory={fatalError("cancelled cleanup opened transport")};never.customOperation={_,_ in fatalError()};never.cancel();never.execute({});check(never.wasCancelled)
  print("PASS: opt-in one-way cleanup, grouped directories and exclusion masks, actual local SFTP recursive deletion, fixture recycling only, whole-tree drift/source appearance/dangling links/checksums/inode and ancestor changes rejected, queued cancellation and no deletion recovery")
 }
}
