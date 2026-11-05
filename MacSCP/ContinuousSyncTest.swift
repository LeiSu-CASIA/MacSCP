import Foundation
import Darwin
@main struct ContinuousSyncTests {
 static func check(_ value:Bool,file:StaticString = #file,line:UInt = #line){precondition(value,file:file,line:line)}
 static func refused(_ action:()throws->Void){do{try action();fatalError("unsafe continuous action accepted")}catch{}}
 static func main()throws {
  let fm=FileManager.default,root=fm.temporaryDirectory.appendingPathComponent("continuous-test-"+UUID().uuidString)
  try fm.createDirectory(at:root,withIntermediateDirectories:false);defer{try? fm.removeItem(at:root)}
  let local=root.appendingPathComponent("local"),remote=root.appendingPathComponent("remote"),resources=root.appendingPathComponent("resources")
  for path in [local,remote,resources]{try fm.createDirectory(at:path,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])}
  let client=try SFTPClient(command:"/usr/libexec/sftp-server",arguments:[]);defer{client.close()}
  let roots=try ContinuousRootGuard(local:local.path,remote:remote.path,client:client)
  func put(_ base:URL,_ path:String,_ text:String,_ time:TimeInterval=1700000000)throws{let url=base.appendingPathComponent(path);try fm.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true);try Data(text.utf8).write(to:url);try fm.setAttributes([.modificationDate:Date(timeIntervalSince1970:time)],ofItemAtPath:url.path)}
  func scope(_ options:ContinuousOptions=ContinuousOptions(),_ policy:TransferPolicy=TransferPolicy(),selected:Set<String>=[])throws->ContinuousScope{try ContinuousScope(options:options,policy:policy,selected:selected)}
  func localState(_ scope:ContinuousScope)throws->ContinuousLocalSnapshot{try ContinuousScanner.local(roots,scope:scope)}
  func remoteState(_ scope:ContinuousScope)throws->[String:ContinuousRemoteNode]{try ContinuousScanner.remote(roots,scope:scope,client:client)}
  func plan(_ scope:ContinuousScope,previous:ContinuousLocalSnapshot?=nil,accepted:[String:ContinuousRemoteNode]?=nil,forced:Set<String>=[],initial:Bool=true)throws->ContinuousPlan{let l=try localState(scope),r=try remoteState(scope);return try ContinuousPlan.prepare(roots:roots,scope:scope,local:l,previous:previous ?? l,remote:r,accepted:accepted ?? r,forced:forced,initial:initial,eventVersion:0,copyPermissions:true,client:client)}
  func execute(_ plan:ContinuousPlan)throws->ContinuousOutcome{let out=ContinuousOutcome();try plan.execute(client:client,resources:resources,outcome:out,checkpoint:{});check(try fm.contentsOfDirectory(atPath:resources.path).isEmpty);return out}
  let standard=try scope()
  try put(local,"file.txt","first");try put(remote,"file.txt","older",1690000000)
  check(try plan(standard,initial:false).actions.isEmpty)
  let initial=try plan(standard);check(initial.actions.count==1);_ = try execute(initial)
  check(try Data(contentsOf:remote.appendingPathComponent("file.txt"))==Data("first".utf8))
  check(try plan(standard).actions.isEmpty)
  // Same length and modification time still transfers a write detected by the change timestamp.
  let before=try localState(standard),accepted=try remoteState(standard)
  try put(local,"file.txt","saved")
  let changed=try plan(standard,previous:before,accepted:accepted,initial:false);check(changed.actions.count==1);_ = try execute(changed)
  check(try Data(contentsOf:remote.appendingPathComponent("file.txt"))==Data("saved".utf8))
  let previous=try localState(standard),baseline=try remoteState(standard)
  try put(local,"nested/中文.txt","nested");try fm.createDirectory(at:local.appendingPathComponent("empty"),withIntermediateDirectories:true)
  _ = try execute(plan(standard,previous:previous,accepted:baseline,initial:false))
  check(fm.fileExists(atPath:remote.appendingPathComponent("empty").path));check(try Data(contentsOf:remote.appendingPathComponent("nested/中文.txt"))==Data("nested".utf8))
  var shallow=ContinuousOptions();shallow.recursive=false
  check(try localState(scope(shallow)).signatures.keys.allSatisfy{!$0.contains("/") && $0 != "nested"})
  var selected=ContinuousOptions();selected.selectedOnly=true
  refused{_ = try scope(selected)}
  check(try localState(scope(selected,selected:["nested"])).signatures.keys.allSatisfy{$0=="nested" || $0.hasPrefix("nested/")})
  let masked=try scope(ContinuousOptions(),TransferPolicy(include:"*.txt",exclude:"empty/"));check(try localState(masked).signatures["empty"]==nil)
  // Symbols and private publication stages are never mirrored or deleted.
  let stage="work.macscp-resume-"+UUID().uuidString
  try put(local,stage,"private");try put(remote,stage,"private")
  for marker in [".macscp-download-",".macscp-promise-",".macscp-backup-",".macscp-"]{check(ContinuousScope.internalName(marker+UUID().uuidString))}
  check(try localState(standard).signatures[stage]==nil)
  try fm.createSymbolicLink(atPath:local.appendingPathComponent("symbol").path,withDestinationPath:remote.path)
  refused{_ = try localState(standard)};try fm.removeItem(at:local.appendingPathComponent("symbol"))
  var existing=ContinuousOptions();existing.existingOnly=true;try put(local,"not-on-target","skip")
  check(try plan(scope(existing)).actions.isEmpty)
  // Remote changes since the accepted baseline stop a local edit rather than silently replacing them.
  let oldLocal=try localState(standard),oldRemote=try remoteState(standard)
  try put(local,"file.txt","local change",1700000001);try put(remote,"file.txt","foreign remote",1700000002)
  refused{_ = try plan(standard,previous:oldLocal,accepted:oldRemote,initial:false)}
  let stale=try plan(standard,forced:["file.txt"],initial:false)
  try put(local,"file.txt","changed again",1700000003)
  refused{_ = try execute(stale)};check(try Data(contentsOf:remote.appendingPathComponent("file.txt"))==Data("foreign remote".utf8))
  // A concurrent target writer during payload transfer is detected before publication.
  let racing=try plan(standard,forced:["file.txt"],initial:false);var injected=false
  client.progress={_ in if !injected{injected=true;try! put(remote,"file.txt","concurrent writer",1700000004)}}
  refused{_ = try execute(racing)};client.progress=nil
  check(injected);check(try Data(contentsOf:remote.appendingPathComponent("file.txt"))==Data("concurrent writer".utf8))
  check(try fm.contentsOfDirectory(atPath:resources.path).isEmpty)
  // Strict comparison detects equal-size/equal-mtime changes in remote content.
  var strictOptions=ContinuousOptions();strictOptions.strictRemote=true
  let strict=try scope(strictOptions),strictBefore=try localState(strict),strictRemote=try remoteState(strict)
  try put(remote,"file.txt",String(repeating:"x",count:17),1700000004);try put(local,"file.txt","trigger",1700000005)
  refused{_ = try plan(strict,previous:strictBefore,accepted:strictRemote,initial:false)}
  // Default never deletes. Explicit cleanup removes remote-only entries but protects stages.
  try put(remote,"extra/sub/file","remove");check(try plan(standard,initial:false).deletions.isEmpty)
  var cleanup=ContinuousOptions();cleanup.cleanup=true
  let cleanupScope=try scope(cleanup),cleanupPlan=try plan(cleanupScope)
  check(cleanupPlan.deletions.contains("extra") && !cleanupPlan.deletions.contains(stage))
  _ = try execute(cleanupPlan);check(!fm.fileExists(atPath:remote.appendingPathComponent("extra").path) && fm.fileExists(atPath:remote.appendingPathComponent(stage).path))
  let deleteLocal=try localState(cleanupScope),deleteRemote=try remoteState(cleanupScope)
  try fm.removeItem(at:local.appendingPathComponent("nested"))
  let deletion=try plan(cleanupScope,previous:deleteLocal,accepted:deleteRemote,initial:false)
  check(deletion.deletions==["nested"]);_ = try execute(deletion);check(!fm.fileExists(atPath:remote.appendingPathComponent("nested").path))
  // Changing source during snapshot construction leaves the published destination untouched.
  try Data(repeating:42,count:3*1024*1024).write(to:local.appendingPathComponent("large"))
  let growing=try plan(standard,forced:["large"],initial:false),outcome=ContinuousOutcome();var checkpoints=0
  refused{try growing.execute(client:client,resources:resources,outcome:outcome,checkpoint:{checkpoints+=1;if checkpoints==3{try put(local,"large","changed")}})}
  check(!fm.fileExists(atPath:remote.appendingPathComponent("large").path));check(try fm.contentsOfDirectory(atPath:resources.path).isEmpty)
  var continuing=ContinuousOptions();continuing.continueOnError=true
  let continueScope=try scope(continuing)
  try put(local,"blocked/file","cannot publish");try fm.createDirectory(at:remote.appendingPathComponent("blocked"),withIntermediateDirectories:true)
  try fm.setAttributes([.posixPermissions:0o555],ofItemAtPath:remote.appendingPathComponent("blocked").path)
  try put(local,"z-success","remaining job")
  let continuePlan=try plan(continueScope),continued=ContinuousOutcome()
  do{try continuePlan.execute(client:client,resources:resources,outcome:continued,checkpoint:{})}catch{try? fm.setAttributes([.posixPermissions:0o755],ofItemAtPath:remote.appendingPathComponent("blocked").path);throw error}
  try fm.setAttributes([.posixPermissions:0o755],ofItemAtPath:remote.appendingPathComponent("blocked").path)
  check(continued.skipped==1 && !continued.messages.isEmpty);check(try Data(contentsOf:remote.appendingPathComponent("z-success"))==Data("remaining job".utf8))
  let job=TransferJob(up:true,source:"owned",destination:"owned",directory:false,size:0);var callbacks=0
  job.observeCompletion{callbacks+=1};job.observeCompletion{callbacks+=1};job.cancel();job.cancel();job.observeCompletion{callbacks+=1};check(callbacks==3)
  print("PASS: real local SFTP continuous plans, initial/off/same-time atomic saves, nested/empty directories, scope/masks/private stages, source and remote writer refusal, strict hash conflict, explicit cleanup, snapshot cleanup and exactly-once completion; owned fixtures only")
 }
}
