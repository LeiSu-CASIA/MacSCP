import Foundation
@main struct SyncRecompareTests {
 static func check(_ value:Bool,file:StaticString = #file,line:UInt = #line){precondition(value,file:file,line:line)}
 static func refused(_ action:()throws->Void){do{try action();fatalError("unsafe retry comparison accepted")}catch{}}
 static func main()throws{
  let fm=FileManager.default,root=fm.temporaryDirectory.appendingPathComponent("sync-recompare-"+UUID().uuidString),local=root.appendingPathComponent("local"),remote=root.appendingPathComponent("remote")
  for path in [local.appendingPathComponent("tree/sub"),local.appendingPathComponent("empty"),remote]{try fm.createDirectory(at:path,withIntermediateDirectories:true)};defer{try? fm.removeItem(at:root)}
  func put(_ base:URL,_ path:String,_ text:String)throws{let url=base.appendingPathComponent(path);try fm.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true);try Data(text.utf8).write(to:url)}
  try put(local,"tree/sub/keep","chosen");try put(local,"tree/sub/skip","unselected")
  let client=try SFTPClient(command:"/usr/libexec/sftp-server",arguments:[]);defer{client.close()}
  let site=Session(name:"fixture",host:"fixture.invalid",user:"fixture",port:22,key:"")
  func context(_ settings:SyncSettings=SyncSettings())throws->SyncRetryContext{try SyncRetryContext(site:site,socket:"fixture",settings:settings,policy:TransferPolicy(),local:local.path,remote:remote.path,client:client)}
  func compare(_ context:SyncRetryContext,_ intents:[SyncRetryIntent])throws->SyncRecompareResult{try SyncRecompare.prepare(context:context,intents:intents,client:client,checkpoint:{})}
  let original=try SyncPlanner.local(local.path),ctx=try context();var folder=SyncCandidate(relative:"tree",local:original["tree"],remote:nil,upload:true,selected:true,typeConflict:false)
  var subset=try SyncContents(root:"tree",snapshot:original,policy:TransferPolicy());subset.setAll(false);subset.set("tree/sub/keep",on:true);folder.contents=subset
  let intent=try SyncRetryIntent(context:ctx,action:folder),fresh=try compare(ctx,[intent])
  check(fresh.candidates.count==1 && fresh.candidates[0].relative=="tree" && fresh.candidates[0].contents!.selected==["tree/sub/keep"])
  check(!fm.fileExists(atPath:remote.appendingPathComponent("tree").path))
  // A partially completed directory becomes a file action, not a blind replay of the root copy.
  try fm.createDirectory(at:remote.appendingPathComponent("tree/sub"),withIntermediateDirectories:true)
  let existingParent=try compare(ctx,[intent]);check(existingParent.candidates.count==1 && existingParent.candidates[0].relative=="tree/sub/keep")
  try put(remote,"tree/sub/keep","chosen");try fm.setAttributes([.modificationDate:Date(timeIntervalSince1970:original["tree/sub/keep"]!.modified)],ofItemAtPath:remote.appendingPathComponent("tree/sub/keep").path)
  check(try compare(ctx,[intent]).candidates.isEmpty)
  // Multiple original file actions share a newly required parent but never add unselected siblings.
  try fm.removeItem(at:remote.appendingPathComponent("tree"))
  let a=try SyncRetryIntent(context:ctx,action:SyncCandidate(relative:"tree/sub/keep",local:original["tree/sub/keep"],remote:nil,upload:true,selected:true,typeConflict:false))
  let b=try SyncRetryIntent(context:ctx,action:SyncCandidate(relative:"tree/sub/skip",local:original["tree/sub/skip"],remote:nil,upload:true,selected:true,typeConflict:false))
  check(try compare(ctx,[a,b,a]).candidates[0].contents!.selected==["tree/sub/keep","tree/sub/skip"])
  // New contents under an originally selected empty directory are not silently transferred.
  let empty=try SyncRetryIntent(context:ctx,action:SyncCandidate(relative:"empty",local:original["empty"],remote:nil,upload:true,selected:true,typeConflict:false,contents:SyncContents(root:"empty",snapshot:original,policy:TransferPolicy())))
  try put(local,"empty/new","new data");let changedEmpty=try compare(ctx,[empty]);check(changedEmpty.candidates.isEmpty && !changedEmpty.notices.isEmpty)
  // Partial cleanup preserves its original file roots even after the unchecked sibling disappears.
  try put(remote,"obsolete/sub/drop","drop");try put(remote,"obsolete/sub/keep","keep")
  let rs=try SyncPlanner.remote(remote.path,client:client),deleteContext=try context(SyncSettings(cleanup:true));var deletion=SyncCandidate(relative:"obsolete",local:nil,remote:rs["obsolete"],upload:true,selected:true,typeConflict:false,deletion:true)
  var deletionSubset=try SyncContents(root:"obsolete",snapshot:rs,policy:TransferPolicy());deletionSubset.setAll(false);deletionSubset.set("obsolete/sub/drop",on:true);deletion.contents=deletionSubset
  let deleteIntent=try SyncRetryIntent(context:deleteContext,action:deletion);try fm.removeItem(at:remote.appendingPathComponent("obsolete/sub/keep"))
  let retryDelete=try compare(deleteContext,[deleteIntent]);check(retryDelete.candidates.map{$0.relative}==["obsolete/sub/drop"] && retryDelete.deletions.count==1)
  try retryDelete.deletions["obsolete/sub/drop"]!.execute(client:client,checkpoint:{},trash:{_ in fatalError("no real Trash")})
  check(fm.fileExists(atPath:remote.appendingPathComponent("obsolete/sub").path))
  try put(remote,"down/sub/keep","remote chosen");try put(remote,"down/sub/skip","remote unselected")
  let downRS=try SyncPlanner.remote(remote.path,client:client),downContext=try context(SyncSettings(direction:.download));var downAction=SyncCandidate(relative:"down",local:nil,remote:downRS["down"],upload:false,selected:true,typeConflict:false)
  var downContents=try SyncContents(root:"down",snapshot:downRS,policy:TransferPolicy());downContents.setAll(false);downContents.set("down/sub/keep",on:true);downAction.contents=downContents
  let downResult=try compare(downContext,[SyncRetryIntent(context:downContext,action:downAction)]);check(downResult.candidates[0].upload==false && downResult.candidates[0].contents!.selected==["down/sub/keep"] && !fm.fileExists(atPath:local.appendingPathComponent("down").path))
  try put(local,"version","local version");try put(remote,"version","remote newer")
  try fm.setAttributes([.modificationDate:Date(timeIntervalSince1970:1700000000)],ofItemAtPath:local.appendingPathComponent("version").path);try fm.setAttributes([.modificationDate:Date(timeIntervalSince1970:1800000000)],ofItemAtPath:remote.appendingPathComponent("version").path)
  let versionsL=try SyncPlanner.local(local.path),versionsR=try SyncPlanner.remote(remote.path,client:client),versionAction=SyncCandidate(relative:"version",local:versionsL["version"],remote:versionsR["version"],upload:true,selected:true,typeConflict:false)
  let mirrorContext=try context(SyncSettings(comparison:SyncComparisonOptions(fileMode:.mirror,timeTolerance:0)))
  check(try compare(mirrorContext,[SyncRetryIntent(context:mirrorContext,action:versionAction)]).candidates[0].mirror)
  let timeContext=try context(SyncSettings(comparison:SyncComparisonOptions(fileMode:.timestamps,timeTolerance:0))),timeAction=SyncCandidate(relative:"version",local:versionsL["version"],remote:versionsR["version"],upload:true,selected:true,typeConflict:false,timestampOnly:true)
  let timeResult=try compare(timeContext,[SyncRetryIntent(context:timeContext,action:timeAction)]);check(timeResult.candidates[0].timestampOnly && timeResult.timestamps["version"]!.desired==1700000000)
  // Unrelated protected payloads are not read for a scoped content comparison.
  try put(local,"outside","must not read");try put(remote,"outside","must not read");try put(local,"hashed","first");try put(remote,"hashed","wrong")
  try fm.setAttributes([.posixPermissions:0],ofItemAtPath:local.appendingPathComponent("outside").path);try fm.setAttributes([.posixPermissions:0],ofItemAtPath:remote.appendingPathComponent("outside").path)
  let hashL=try SyncPlanner.local(local.path),hashR=try SyncPlanner.remote(remote.path,client:client),hashContext=try context(SyncSettings(comparison:SyncComparisonOptions(modificationTime:false,checksum:true)))
  let hashAction=SyncCandidate(relative:"hashed",local:hashL["hashed"],remote:hashR["hashed"],upload:true,selected:true,typeConflict:false)
  check(try compare(hashContext,[SyncRetryIntent(context:hashContext,action:hashAction)]).candidates.map{$0.relative}==["hashed"])
  try fm.setAttributes([.posixPermissions:0o600],ofItemAtPath:local.appendingPathComponent("outside").path);try fm.setAttributes([.posixPermissions:0o600],ofItemAtPath:remote.appendingPathComponent("outside").path)
  // Private transmission files are excluded from both fresh payload and cleanup plans.
  let privateName="stage.macscp-resume-"+UUID().uuidString;try put(remote,"reserved/"+privateName,"private");try put(remote,"reserved/drop","drop")
  let privateRS=try SyncPlanner.remote(remote.path,client:client),privateAction=SyncCandidate(relative:"reserved",local:nil,remote:privateRS["reserved"],upload:true,selected:true,typeConflict:false,deletion:true)
  let privateRetry=try compare(deleteContext,[SyncRetryIntent(context:deleteContext,action:privateAction)])
  check(privateRetry.candidates.map{$0.relative}==["reserved/drop"] && fm.fileExists(atPath:remote.appendingPathComponent("reserved/"+privateName).path))
  try put(local,privateName,"explicit ordinary transfer")
  let explicitJob=TransferJob(up:true,source:local.appendingPathComponent(privateName).path,destination:remote.appendingPathComponent("explicit-private-name").path,directory:false,size:26);explicitJob.factory={try SFTPClient(command:"/usr/libexec/sftp-server",arguments:[])};explicitJob.execute({});check(!explicitJob.failed);check(try Data(contentsOf:remote.appendingPathComponent("explicit-private-name"))==Data("explicit ordinary transfer".utf8))
  let indexed=SyncSnapshotIndex(["a":SyncNode(directory:true,size:0,modified:1),"a-b":SyncNode(directory:false,size:1,modified:1),"a/x":SyncNode(directory:false,size:1,modified:1)]);check(indexed.hasChildren("a"))
  let operation=SyncRecompareOperation(context:ctx,intents:[intent],socket:"fixture");operation.cancel();var factories=0
  refused{_ = try operation.run{factories+=1;return try SFTPClient(command:"/usr/libexec/sftp-server",arguments:[])}};check(factories==0)
  // A new directory at the same path does not inherit the old root's authorization.
  try fm.moveItem(at:local,to:root.appendingPathComponent("held-local"));try fm.createDirectory(at:local,withIntermediateDirectories:false)
  refused{_ = try compare(ctx,[intent])}
  print("PASS: read-only recompare of exact original scopes, partial directory completion, missing-parent promotion without sibling expansion, completed/no-op handling, empty-dir changes, partial cleanup never deletes a parent, private-stage protection, cancellation before factory and original root identity refusal; local fixtures only")
 }
}
