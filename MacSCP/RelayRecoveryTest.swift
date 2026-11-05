import Foundation
@main struct RelayRecoveryTests {
 static let sourceSite=Session(name:"source fixture",host:"source.invalid",user:"fixture",port:22,key:"")
 static let targetSite=Session(name:"target fixture",host:"target.invalid",user:"fixture",port:2222,key:"")
 static func wait(_ condition:()->Bool){let deadline=Date().addingTimeInterval(20);while !condition() && Date()<deadline{Thread.sleep(forTimeInterval:0.005)};precondition(condition(),"relay recovery timeout")}
 static func attach(_ relay:RelayTransfer,_ journal:RelayJournal){relay.enableRecovery();relay.recoveryChanged={[weak relay] force in guard let relay=relay else{return};do{if let record=relay.recoveryRecord(){try journal.save(record,force:force)}else{try journal.remove(relay.id)}}catch{if let r=relay.recoveryRecord(){for (name,item) in [("down",r.download),("up",r.upload)]{try? FileHandle.standardError.write(contentsOf:Data("\(name) root=\(item.source) -> \(item.destination) dir=\(item.directory) resumes=\(item.resumes)\n".utf8))}};fatalError("relay journal: \(error)")}}}
 static func child(_ root:URL,upload:Bool,crash:Bool=false,directory:Bool=false)throws{
  let source=root.appendingPathComponent(directory ? "source-dir" : "source.bin"),target=root.appendingPathComponent(directory ? "target-dir" : "target.bin"),journal=try RelayJournal(url:root.appendingPathComponent("relays.json"))
  let relay=try RelayTransfer(file:DragFile(path:source.path,directory:directory,size:directory ? 0 : 262144,connection:"fixture"),destination:target.path,policy:directory ? TransferPolicy(include:"*.txt") : TransferPolicy(),sourceSite:sourceSite,targetSite:targetSite)
  attach(relay,journal);relay.upload.overwrite=true
  relay.download.factory={try SFTPClient(command:"/usr/libexec/sftp-server",arguments:[])};relay.upload.factory={try SFTPClient(command:"/usr/libexec/sftp-server",arguments:[])}
  let queue=TransferScheduler();queue.isSuspended=true
  relay.changed={[weak relay] in guard let relay=relay else{return};if (upload ? relay.upload : relay.download).transferredBytes>=65536{if crash{_exit(73)};relay.suspendForExit()}}
  try relay.start(on:queue);(upload ? relay.upload : relay.download).speedLimit=65536;queue.isSuspended=false
  wait{relay.canDiscard};try journal.flush()
  precondition(relay.phase == .failed && journal.list().count==1 && FileManager.default.fileExists(atPath:relay.staging.path))
  print("child preserved \(upload ? "upload" : "download")")
 }
 static func produce(_ root:URL,upload:Bool,crash:Bool=false,directory:Bool=false)throws{
  let p=Process();p.executableURL=URL(fileURLWithPath:CommandLine.arguments[0]);p.arguments=[(crash ? "crash-" : "child-")+(directory ? "directory-" : "")+(upload ? "upload" : "download"),root.path];p.standardOutput=FileHandle.nullDevice;try p.run();p.waitUntilExit();precondition(p.terminationStatus==(crash ? 73 : 0))
 }
 static func main()throws{
  if CommandLine.arguments.count==3{try child(URL(fileURLWithPath:CommandLine.arguments[2]),upload:CommandLine.arguments[1].hasSuffix("upload"),crash:CommandLine.arguments[1].hasPrefix("crash-"),directory:CommandLine.arguments[1].contains("directory-"));return}
  let fm=FileManager.default,root=fm.temporaryDirectory.appendingPathComponent("relay-recovery-test-"+UUID().uuidString),data=Data((0..<262144).map{UInt8($0%251)}),original=Data("original target".utf8)
  try fm.createDirectory(at:root,withIntermediateDirectories:false)
  let storage=try RelayStorage.prepare(at:root.appendingPathComponent("durable-storage"))
  let storageMode=try fm.attributesOfItem(atPath:storage.path)[.posixPermissions] as! NSNumber;precondition(storageMode.intValue==0o700)
  try fm.setAttributes([.posixPermissions:0o755],ofItemAtPath:storage.path);do{_ = try RelayStorage.prepare(at:storage);fatalError("insecure storage accepted")}catch{};try fm.setAttributes([.posixPermissions:0o700],ofItemAtPath:storage.path)
  var retained=[RelayRecord]()
  defer{for record in retained{try? record.discardLocal()};try? fm.removeItem(at:root)}
  func fixture(_ name:String)throws->URL{let path=root.appendingPathComponent(name);try fm.createDirectory(at:path,withIntermediateDirectories:false);try data.write(to:path.appendingPathComponent("source.bin"));try original.write(to:path.appendingPathComponent("target.bin"));return path}
  for (upload,crash) in [(false,false),(true,false),(false,true),(true,true)]{
   let fixture=try fixture((crash ? "crash-" : "normal-")+(upload ? "upload" : "download"));try produce(fixture,upload:upload,crash:crash)
   let journalPath=fixture.appendingPathComponent("relays.json"),journal=try RelayJournal(url:journalPath),record=journal.list().first!;retained.append(record)
   try record.checkStaging();do{_ = try RelayJournal(url:journalPath);fatalError("duplicate relay journal owner")}catch{}
   let fileAttrs=try fm.attributesOfItem(atPath:journalPath.path);precondition((fileAttrs[.posixPermissions] as! NSNumber).intValue==0o600)
   let json=try String(contentsOf:journalPath,encoding:.utf8);precondition(!json.contains("password"))
   let before=try Data(contentsOf:fixture.appendingPathComponent("target.bin"));precondition(before==original)
   let resumed=try RelayTransfer(record:record),queue=TransferScheduler();attach(resumed,journal)
   precondition(resumed.id==record.id && resumed.download.id==record.download.id && resumed.upload.id==record.upload.id)
   resumed.download.factory={try SFTPClient(command:"/usr/libexec/sftp-server",arguments:[])};resumed.upload.factory={try SFTPClient(command:"/usr/libexec/sftp-server",arguments:[])}
   try resumed.start(on:queue);wait{resumed.canDiscard}
   let result=try Data(contentsOf:fixture.appendingPathComponent("target.bin"));precondition(resumed.phase == .completed && result==data && journal.list().isEmpty && !fm.fileExists(atPath:record.staging))
   if upload{precondition(resumed.download.reusedBytes==UInt64(data.count) && resumed.upload.reusedBytes>=65536)}else{precondition(resumed.download.reusedBytes>=65536)}
  }
  func directoryFixture(_ name:String)throws->URL{let path=root.appendingPathComponent(name);for folder in ["source-dir/child","source-dir/empty-dir","target-dir"]{try fm.createDirectory(at:path.appendingPathComponent(folder),withIntermediateDirectories:true)};try data.write(to:path.appendingPathComponent("source-dir/child/file.txt"));try Data().write(to:path.appendingPathComponent("source-dir/empty.txt"));try data.write(to:path.appendingPathComponent("source-dir/excluded.bin"));try original.write(to:path.appendingPathComponent("target-dir/spare.txt"));return path}
  let treeRoot=try directoryFixture("directory" );try produce(treeRoot,upload:true,crash:true,directory:true)
  let treeJournal=try RelayJournal(url:treeRoot.appendingPathComponent("relays.json")),treeRecord=treeJournal.list().first!;retained.append(treeRecord)
  let oldDownload=treeRecord.download
  let interruptedMarker=TransferRecord(id:oldDownload.id,site:oldDownload.site,up:false,source:oldDownload.source,destination:oldDownload.destination,directory:true,size:oldDownload.size,overwrite:oldDownload.overwrite,resumes:oldDownload.resumes,completed:[],created:[],policy:oldDownload.policy,plannedDirectories:oldDownload.plannedDirectories)
  let publicationGap=RelayRecord(id:treeRecord.id,staging:treeRecord.staging,download:interruptedMarker,upload:treeRecord.upload)
  let tree=try RelayTransfer(record:publicationGap),treeQueue=TransferScheduler();attach(tree,treeJournal)
  tree.download.factory={try SFTPClient(command:"/usr/libexec/sftp-server",arguments:[])};tree.upload.factory={try SFTPClient(command:"/usr/libexec/sftp-server",arguments:[])}
  try tree.start(on:treeQueue);wait{tree.canDiscard}
  let treeData=try Data(contentsOf:treeRoot.appendingPathComponent("target-dir/child/file.txt")),spare=try Data(contentsOf:treeRoot.appendingPathComponent("target-dir/spare.txt"))
  precondition(tree.phase == .completed && treeData==data && spare==original && fm.fileExists(atPath:treeRoot.appendingPathComponent("target-dir/empty-dir").path) && !fm.fileExists(atPath:treeRoot.appendingPathComponent("target-dir/excluded.bin").path) && treeJournal.list().isEmpty)
  let removedRoot=try directoryFixture("removed" );try produce(removedRoot,upload:true,directory:true)
  let removedJournal=try RelayJournal(url:removedRoot.appendingPathComponent("relays.json")),removedRecord=removedJournal.list().first!;retained.append(removedRecord)
  try fm.removeItem(at:removedRoot.appendingPathComponent("source-dir/child/file.txt"))
  let removed=try RelayTransfer(record:removedRecord),removedQueue=TransferScheduler();attach(removed,removedJournal)
  removed.download.factory={try SFTPClient(command:"/usr/libexec/sftp-server",arguments:[])};removed.upload.factory={fatalError("removed completed file must block upload")}
  try removed.start(on:removedQueue);wait{removed.canDiscard};precondition(removed.phase == .failed && removed.download.column("progress").contains("已移除"));removed.cancel()
  let partialRoot=try directoryFixture("partial-removed");try produce(partialRoot,upload:false,directory:true)
  let partialJournal=try RelayJournal(url:partialRoot.appendingPathComponent("relays.json")),partialRecord=partialJournal.list().first!;retained.append(partialRecord)
  try fm.removeItem(at:partialRoot.appendingPathComponent("source-dir/child/file.txt"))
  let partial=try RelayTransfer(record:partialRecord),partialQueue=TransferScheduler();attach(partial,partialJournal)
  partial.download.factory={try SFTPClient(command:"/usr/libexec/sftp-server",arguments:[])};partial.upload.factory={fatalError("removed partially downloaded source must not upload staging files")}
  try partial.start(on:partialQueue);wait{partial.canDiscard};precondition(partial.phase == .failed && partial.download.column("progress").contains("已移除"));partial.cancel()
  let changedRoot=try fixture("changed");try produce(changedRoot,upload:true)
  let changedJournal=try RelayJournal(url:changedRoot.appendingPathComponent("relays.json")),changedRecord=changedJournal.list().first!;retained.append(changedRecord)
  let extra=URL(fileURLWithPath:changedRecord.staging).appendingPathComponent("unexpected.bin");try Data("unrecorded".utf8).write(to:extra)
  do{_ = try RelayTransfer(record:changedRecord);fatalError("unrecorded stage file")}catch{};try fm.removeItem(at:extra)
  try fm.setAttributes([.posixPermissions:0o755],ofItemAtPath:changedRecord.staging)
  do{_ = try RelayTransfer(record:changedRecord);fatalError("public staging permissions")}catch{};try fm.setAttributes([.posixPermissions:0o700],ofItemAtPath:changedRecord.staging)
  let relocated=changedRecord.staging+"-held";try fm.moveItem(atPath:changedRecord.staging,toPath:relocated);try fm.createSymbolicLink(atPath:changedRecord.staging,withDestinationPath:relocated)
  do{_ = try RelayTransfer(record:changedRecord);fatalError("staging root link")}catch{};try fm.removeItem(atPath:changedRecord.staging);try fm.moveItem(atPath:relocated,toPath:changedRecord.staging)
  try Data(repeating:101,count:data.count).write(to:changedRoot.appendingPathComponent("source.bin"))
  let changed=try RelayTransfer(record:changedRecord),queue=TransferScheduler();attach(changed,changedJournal)
  changed.download.factory={try SFTPClient(command:"/usr/libexec/sftp-server",arguments:[])};changed.upload.factory={fatalError("changed source must block the upload")}
  try changed.start(on:queue);wait{changed.canDiscard}
  let unchanged=try Data(contentsOf:changedRoot.appendingPathComponent("target.bin"));precondition(changed.phase == .failed && unchanged==original && changedJournal.list().count==1)
  changed.cancel();precondition(changedJournal.list().isEmpty && !fm.fileExists(atPath:changedRecord.staging))
  let unsafe=RelayRecord(id:UUID(),staging:root.path,download:changedRecord.download,upload:changedRecord.upload)
  do{_ = try unsafe.validated();fatalError("unrelated temporary directory accepted")}catch{}
  print("PASS: separate process preserves or abruptly exits during download/upload stages without cleanup/flush, fresh journal/model resumes stable IDs and verified prefixes, upload recovery revalidates completed local snapshot, original target retained until success, completed/cancelled record removal, exclusive 0600 journal/no passwords, directory tree/masks/empty folders retained, published-file/mkdir-before-journal crash windows verified and adopted, removed completed source blocks upload, tampered source/extra files/permissions/symlink/unrelated staging refused")
 }
}
