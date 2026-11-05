import Foundation
@main struct TextTransferTests {
 static func check(_ value:Bool,file:StaticString = #file,line:UInt = #line){precondition(value,file:file,line:line)}
 static func main()throws {
  let fm=FileManager.default,root=fm.temporaryDirectory.appendingPathComponent("text-transfer-test-"+UUID().uuidString)
  for name in ["local","remote","download","monitor","monitor-remote","resources"]{try fm.createDirectory(at:root.appendingPathComponent(name),withIntermediateDirectories:true)};defer{try? fm.removeItem(at:root)}
  let local=root.appendingPathComponent("local"),remote=root.appendingPathComponent("remote"),download=root.appendingPathComponent("download"),client=try SFTPClient(command:"/usr/libexec/sftp-server",arguments:[]);defer{client.close()}
  let input=Data([239,187,191])+Data("中文\r\nline\rlast\n".utf8)+Data([26]),expected=Data("中文\nline\nlast\n".utf8),binary=Data([0,13,10,255,254])
  try input.write(to:local.appendingPathComponent("test.txt"));try binary.write(to:local.appendingPathComponent("binary.dat"));try binary.write(to:local.appendingPathComponent("utf16.txt"))
  let options=TextTransferOptions(mode:.automatic,remote:.lf,local:.crlf,removeBOM:true,removeEOF:true),policy=TransferPolicy(verifyChecksum:true,text:options)
  let up=TransferJob(up:true,source:local.path,destination:remote.appendingPathComponent("tree").path,directory:true,size:0);up.policy=policy;up.factory={try SFTPClient(command:"/usr/libexec/sftp-server",arguments:[])};up.execute({});check(!up.failed && up.finished)
  check(try Data(contentsOf:remote.appendingPathComponent("tree/test.txt"))==expected && Data(contentsOf:local.appendingPathComponent("test.txt"))==input)
  check(try Data(contentsOf:remote.appendingPathComponent("tree/utf16.txt"))==binary && Data(contentsOf:remote.appendingPathComponent("tree/binary.dat"))==binary)
  try fm.setAttributes([.posixPermissions:0o750],ofItemAtPath:remote.appendingPathComponent("tree/test.txt").path)
  let down=TransferJob(up:false,source:remote.appendingPathComponent("tree").path,destination:download.appendingPathComponent("tree").path,directory:true,size:0);down.policy=policy;down.factory={try SFTPClient(command:"/usr/libexec/sftp-server",arguments:[])};down.execute({});check(!down.failed)
  check(try Data(contentsOf:download.appendingPathComponent("tree/test.txt"))==Data("中文\r\nline\r\nlast\r\n".utf8))
  check((try fm.attributesOfItem(atPath:download.appendingPathComponent("tree/test.txt").path)[.posixPermissions] as? NSNumber)?.intValue==0o750)
  let protected=download.appendingPathComponent("protected");try Data("keep".utf8).write(to:protected)
  let bad=TransferJob(up:false,source:remote.appendingPathComponent("tree/utf16.txt").path,destination:protected.path,directory:false,size:0);bad.policy=TransferPolicy(text:TextTransferOptions(mode:.text));bad.overwrite=true;bad.factory={try SFTPClient(command:"/usr/libexec/sftp-server",arguments:[])};bad.execute({});check(bad.failed);check(try Data(contentsOf:protected)==Data("keep".utf8))
  let large=local.appendingPathComponent("large.txt"),largeInput=Data(String(repeating:"abcdef\r\n",count:40000).utf8),largeExpected=Data(String(repeating:"abcdef\n",count:40000).utf8);try largeInput.write(to:large)
  let target=remote.appendingPathComponent("resumed.txt").path,state=TransferResume(source:large.path,destination:target,upload:true),interrupted=try SFTPClient(command:"/usr/libexec/sftp-server",arguments:[])
  var stop=false;interrupted.progress={_ in stop=true};interrupted.checkpoint={if stop{throw SFTPError.message("owned interruption")}}
  do{try TextTransfer.upload(large.path,to:target,state:state,client:interrupted,options:options,overwrite:false,verify:true,checkpoint:{if stop{throw SFTPError.message("owned interruption")}});fatalError("did not interrupt")}catch{};interrupted.close()
  check(state.sourceDigest != nil && !fm.fileExists(atPath:target))
  let record=TransferRecord(id:UUID(),site:Session(name:"fixture",host:"fixture.invalid",user:"fixture",port:22,key:""),up:true,source:large.path,destination:target,directory:false,size:UInt64(largeInput.count),overwrite:false,resumes:[state.record()],completed:[],created:[],policy:policy)
  let reopened=try TransferRecord.restoreFixture(record),restored=try TransferJob.restore(reopened);var reused:UInt64=0
  let retry=try SFTPClient(command:"/usr/libexec/sftp-server",arguments:[]);retry.resumedProgress={reused+=$0};try TextTransfer.upload(large.path,to:target,state:TransferResume(record:reopened.resumes[0]),client:retry,options:options,overwrite:false,verify:true,checkpoint:{});retry.close();check(reused>0)
  check(restored.policy==policy);check(try Data(contentsOf:URL(fileURLWithPath:target))==largeExpected)
  let mutate=local.appendingPathComponent("mutate.txt"),mutateDestination=remote.appendingPathComponent("mutate.txt");try Data("before\r\n".utf8).write(to:mutate);try Data("protected".utf8).write(to:mutateDestination)
  let mutationClient=try SFTPClient(command:"/usr/libexec/sftp-server",arguments:[]);var mutated=false;mutationClient.progress={_ in if !mutated{mutated=true;try! Data("changed\r\n".utf8).write(to:mutate)}}
  do{try TextTransfer.upload(mutate.path,to:mutateDestination.path,state:TransferResume(source:mutate.path,destination:mutateDestination.path,upload:true),client:mutationClient,options:options,overwrite:true,verify:true,checkpoint:{});fatalError("source mutation ignored")}catch{};mutationClient.close();check(try Data(contentsOf:mutateDestination)==Data("protected".utf8))
  let relay=try RelayTransfer(file:DragFile(path:remote.appendingPathComponent("tree/test.txt").path,directory:false,size:UInt64(expected.count),connection:"owned-source"),destination:remote.appendingPathComponent("relay-text.txt").path,policy:policy,temporaryRoot:root)
  relay.download.factory={try SFTPClient(command:"/usr/libexec/sftp-server",arguments:[])};relay.upload.factory={try SFTPClient(command:"/usr/libexec/sftp-server",arguments:[])};let scheduler=TransferScheduler();try relay.start(on:scheduler);let deadline=Date().addingTimeInterval(10);while relay.phase != .completed && Date()<deadline{Thread.sleep(forTimeInterval:0.01)};check(relay.phase == .completed);check(try Data(contentsOf:remote.appendingPathComponent("relay-text.txt"))==expected)
  // Comparison uses expected converted bytes, while candidates retain raw nodes for preflight guards.
  let l=try SyncPlanner.local(local.path),r=try SyncPlanner.remote(remote.appendingPathComponent("tree").path,client:client),settings=SyncSettings(direction:.upload,comparison:SyncComparisonOptions(modificationTime:false,size:true,checksum:true))
  let differences=try SyncTextComparison.differences(local:l,remote:r,localRoot:local.path,remoteRoot:remote.appendingPathComponent("tree").path,policy:policy,settings:settings,client:client)
  check(differences["test.txt"]==false && differences["utf16.txt"]==false)
  let preparedL=try SyncChecksums.local(l,root:local.path),preparedR=try SyncChecksums.remote(r,root:remote.appendingPathComponent("tree").path,client:client)
  let rows=try SyncComparison.plannedCandidates(local:preparedL,remote:preparedR,settings:settings,textDifferences:differences);check(!rows.contains{$0.relative=="test.txt"})
  // Continuous updates compare converted size and publish converted hashes into their baseline.
  let ml=root.appendingPathComponent("monitor"),mr=root.appendingPathComponent("monitor-remote"),resources=root.appendingPathComponent("resources")
  try Data("one\r\n".utf8).write(to:ml.appendingPathComponent("a.txt"));try fm.setAttributes([.modificationDate:Date(timeIntervalSince1970:1700000000)],ofItemAtPath:ml.appendingPathComponent("a.txt").path)
  let roots=try ContinuousRootGuard(local:ml.path,remote:mr.path,client:client),scope=try ContinuousScope(options:ContinuousOptions(strictRemote:true),policy:policy,selected:[])
  let ls=try ContinuousScanner.local(roots,scope:scope),rs=try ContinuousScanner.remote(roots,scope:scope,client:client)
  let plan=try ContinuousPlan.prepare(roots:roots,scope:scope,local:ls,previous:ls,remote:rs,accepted:rs,forced:[],initial:true,eventVersion:0,copyPermissions:true,client:client)
  let outcome=ContinuousOutcome();try plan.execute(client:client,resources:resources,outcome:outcome,checkpoint:{})
  check(try Data(contentsOf:mr.appendingPathComponent("a.txt"))==Data("one\n".utf8));check(outcome.remoteChanges["a.txt"]?.digest != nil)
  let updated=try ContinuousScanner.remote(roots,scope:scope,client:client),again=try ContinuousPlan.prepare(roots:roots,scope:scope,local:ls,previous:ls,remote:updated,accepted:updated,forced:[],initial:true,eventVersion:0,copyPermissions:true,client:client);check(again.actions.isEmpty)
  print("PASS: actual SFTP recursive text/binary/automatic upload/download, original bytes and old target preservation, upload converted-prefix resume after serialized recovery, text-aware sync comparisons and continuous baselines; owned stdio server only")
 }
}
extension TransferRecord{static func restoreFixture(_ record:TransferRecord)throws->TransferRecord{try JSONDecoder().decode(Self.self,from:JSONEncoder().encode(record)).validated()}}
