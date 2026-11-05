import Foundation
final class RelayProbe {
 private let lock=NSLock();private var down=0,up=0,fired=false;private var client:SFTPClient?
 func factory(upload:Bool,fault:Bool=false)throws->SFTPClient{let c=try SFTPClient(command:"/usr/libexec/sftp-server",arguments:[]);lock.lock();if upload{up+=1}else{down+=1};if fault{client=c};lock.unlock();return c}
 func killAfterPrefix(_ job:TransferJob){guard job.transferredBytes>=65536 else{return};lock.lock();guard !fired,let client=client else{lock.unlock();return};fired=true;lock.unlock();if client.process.isRunning{client.process.terminate()}}
 var counts:(Int,Int){lock.lock();defer{lock.unlock()};return(down,up)}
}
@main struct RelayTests {
 static func wait(_ condition:()->Bool){let end=Date().addingTimeInterval(20);while !condition() && Date()<end{Thread.sleep(forTimeInterval:0.005)};precondition(condition(),"relay timeout")}
 static func settled(_ relay:RelayTransfer,_ scheduler:TransferScheduler){wait{relay.canDiscard && !scheduler.contains(relay.download.id) && !scheduler.contains(relay.upload.id)}}
 static func main()throws{
  let fm=FileManager.default,root=fm.temporaryDirectory.appendingPathComponent("relay-test-"+UUID().uuidString)
  try fm.createDirectory(at:root,withIntermediateDirectories:false);defer{try? fm.removeItem(at:root)}
  let source=root.appendingPathComponent("源 ' $.bin"),bytes=Data((0..<262144).map{UInt8($0%251)});try bytes.write(to:source)
  func make(_ destination:String,policy:TransferPolicy=TransferPolicy())throws->RelayTransfer{try RelayTransfer(file:DragFile(path:source.path,directory:false,size:UInt64(bytes.count),connection:"source-session"),destination:root.appendingPathComponent(destination).path,policy:policy,temporaryRoot:root)}

  let scheduler=TransferScheduler();scheduler.maxConcurrentOperationCount=3;scheduler.isSuspended=true
  let relay=try make("first.bin"),probe=RelayProbe();relay.download.factory={try probe.factory(upload:false)};relay.upload.factory={try probe.factory(upload:true)}
  let attrs=try fm.attributesOfItem(atPath:relay.staging.path);precondition((attrs[.posixPermissions] as! NSNumber).intValue==0o700)
  try relay.start(on:scheduler)
  precondition(scheduler.reorder([relay.upload.id,relay.download.id])==[relay.download.id,relay.upload.id]);precondition(probe.counts==(0,0))
  scheduler.isSuspended=false;settled(relay,scheduler)
  let first=try Data(contentsOf:root.appendingPathComponent("first.bin"));precondition(relay.phase == .completed && first==bytes && probe.counts==(1,1) && !fm.fileExists(atPath:relay.staging.path))

  let downScheduler=TransferScheduler();downScheduler.isSuspended=true
  let downFault=try make("download-retry.bin"),downProbe=RelayProbe();downFault.download.factory={try downProbe.factory(upload:false,fault:true)};downFault.upload.factory={try downProbe.factory(upload:true)}
  downFault.changed={[weak downFault] in if let relay=downFault{downProbe.killAfterPrefix(relay.download)}}
  try downFault.start(on:downScheduler);downFault.download.speedLimit=65536;downScheduler.isSuspended=false;settled(downFault,downScheduler)
  precondition(downFault.phase == .failed && downFault.download.failed && downFault.upload.failed && downProbe.counts==(1,0) && fm.fileExists(atPath:downFault.staging.path))
  precondition(downFault.upload.column("progress").contains("等待下载重试"))
  try downFault.start(on:downScheduler);settled(downFault,downScheduler)
  let downRetried=try Data(contentsOf:root.appendingPathComponent("download-retry.bin"));precondition(downFault.phase == .completed && downFault.download.reusedBytes>=32768 && downRetried==bytes && downProbe.counts==(2,1) && !fm.fileExists(atPath:downFault.staging.path))

  let upScheduler=TransferScheduler();upScheduler.isSuspended=true
  let upFault=try make("upload-retry.bin"),upProbe=RelayProbe();let original=Data("original destination".utf8);try original.write(to:URL(fileURLWithPath:upFault.upload.destination));upFault.upload.overwrite=true
  upFault.download.factory={try upProbe.factory(upload:false)};upFault.upload.factory={try upProbe.factory(upload:true,fault:true)}
  upFault.changed={[weak upFault] in if let relay=upFault{upProbe.killAfterPrefix(relay.upload)}}
  try upFault.start(on:upScheduler);upFault.upload.speedLimit=65536;upScheduler.isSuspended=false;settled(upFault,upScheduler)
  let preserved=try Data(contentsOf:URL(fileURLWithPath:upFault.upload.destination));precondition(upFault.phase == .failed && !upFault.download.failed && upFault.upload.failed && preserved==original && upProbe.counts==(1,1) && fm.fileExists(atPath:upFault.staging.path))
  // Retrying the upload uses the completed original local snapshot, even if the
  // source server's file changes after that download.
  try Data(repeating:88,count:bytes.count).write(to:source)
  try upFault.start(on:upScheduler);settled(upFault,upScheduler)
  let upRetried=try Data(contentsOf:URL(fileURLWithPath:upFault.upload.destination));precondition(upFault.phase == .completed && upFault.upload.reusedBytes>=32768 && upRetried==bytes && upProbe.counts==(1,2) && !fm.fileExists(atPath:upFault.staging.path))
  try bytes.write(to:source)

  let queuedScheduler=TransferScheduler();queuedScheduler.isSuspended=true;let queued=try make("queued-cancel.bin"),queuedProbe=RelayProbe();queued.download.factory={try queuedProbe.factory(upload:false)};queued.upload.factory={try queuedProbe.factory(upload:true)}
  try queued.start(on:queuedScheduler);queued.cancel();settled(queued,queuedScheduler)
  precondition(queued.phase == .cancelled && queuedProbe.counts==(0,0) && !fm.fileExists(atPath:queued.staging.path))
  do{try queued.start(on:queuedScheduler);fatalError("cancelled relay may not retry stale staging")}catch{}

  let directScheduler=TransferScheduler();directScheduler.isSuspended=true;let direct=try make("direct-step-cancel.bin")
  direct.download.factory={fatalError("cancelled relay source must not open")};direct.upload.factory={fatalError("cancelled relay target must not open")}
  try direct.start(on:directScheduler);direct.upload.cancel();settled(direct,directScheduler)
  precondition(direct.phase == .cancelled && direct.download.wasCancelled && direct.upload.wasCancelled && !fm.fileExists(atPath:direct.staging.path))

  let cancelScheduler=TransferScheduler();cancelScheduler.isSuspended=true;let running=try make("running-cancel.bin"),cancelProbe=RelayProbe();running.download.factory={try cancelProbe.factory(upload:false)};running.upload.factory={try cancelProbe.factory(upload:true)}
  running.changed={[weak running] in if let relay=running,relay.download.transferredBytes>=32768{relay.cancel()}}
  try running.start(on:cancelScheduler);running.download.speedLimit=65536;cancelScheduler.isSuspended=false;settled(running,cancelScheduler)
  precondition(running.phase == .cancelled && cancelProbe.counts==(1,0) && !fm.fileExists(atPath:running.staging.path))

  let upCancelScheduler=TransferScheduler();upCancelScheduler.isSuspended=true;let upCancel=try make("upload-cancel.bin"),upCancelProbe=RelayProbe();try original.write(to:URL(fileURLWithPath:upCancel.upload.destination));upCancel.upload.overwrite=true
  upCancel.download.factory={try upCancelProbe.factory(upload:false)};upCancel.upload.factory={try upCancelProbe.factory(upload:true)}
  upCancel.changed={[weak upCancel] in if let relay=upCancel,relay.upload.transferredBytes>=32768{relay.cancel()}}
  try upCancel.start(on:upCancelScheduler);upCancel.upload.speedLimit=65536;upCancelScheduler.isSuspended=false;settled(upCancel,upCancelScheduler)
  let cancelPreserved=try Data(contentsOf:URL(fileURLWithPath:upCancel.upload.destination))
  precondition(upCancel.phase == .cancelled && cancelPreserved==original && !fm.fileExists(atPath:upCancel.staging.path))
  precondition(upCancel.upload.retainedTemporaryPaths.allSatisfy{!fm.fileExists(atPath:$0)})

  let discardScheduler=TransferScheduler(),discarded=try make("discarded.bin")
  discarded.download.factory={throw SFTPError.message("fixture offline")};discarded.upload.factory={fatalError("upload must not start while source is offline")}
  try discarded.start(on:discardScheduler);settled(discarded,discardScheduler)
  precondition(discarded.phase == .failed && fm.fileExists(atPath:discarded.staging.path));discarded.discard()
  precondition(discarded.phase == .discarded && !fm.fileExists(atPath:discarded.staging.path))

  let skipScheduler=TransferScheduler(),skipped=try make("mask-skip.bin",policy:TransferPolicy(include:"*.txt")),skipProbe=RelayProbe();skipped.download.factory={try skipProbe.factory(upload:false)};skipped.upload.factory={try skipProbe.factory(upload:true)}
  try skipped.start(on:skipScheduler);settled(skipped,skipScheduler)
  precondition(skipped.phase == .completed && skipped.download.wasRootExcluded && skipped.upload.column("progress").contains("已跳过") && skipProbe.counts==(1,0) && !fm.fileExists(atPath:skipped.upload.destination))

  let tree=root.appendingPathComponent("中文目录"),treeTarget=root.appendingPathComponent("tree-result")
  try fm.createDirectory(at:tree.appendingPathComponent("child"),withIntermediateDirectories:true);try bytes.write(to:tree.appendingPathComponent("child/keep.txt"));try bytes.write(to:tree.appendingPathComponent("child/skip.bin"));try Data().write(to:tree.appendingPathComponent("empty.txt"))
  let directory=try RelayTransfer(file:DragFile(path:tree.path,directory:true,size:0,connection:"source-session"),destination:treeTarget.path,policy:TransferPolicy(include:"*.txt",verifyChecksum:true),temporaryRoot:root),treeScheduler=TransferScheduler()
  directory.download.factory={try SFTPClient(command:"/usr/libexec/sftp-server",arguments:[])};directory.upload.factory={try SFTPClient(command:"/usr/libexec/sftp-server",arguments:[])}
  try directory.start(on:treeScheduler);settled(directory,treeScheduler)
  let treeBytes=try Data(contentsOf:treeTarget.appendingPathComponent("child/keep.txt"));precondition(directory.phase == .completed && treeBytes==bytes && fm.fileExists(atPath:treeTarget.appendingPathComponent("empty.txt").path) && !fm.fileExists(atPath:treeTarget.appendingPathComponent("child/skip.bin").path))
  precondition(!fm.fileExists(atPath:directory.staging.path))
  print("PASS: real SFTP relay file/tree with exact bytes and masks/SHA, dependency-safe prioritization, process-killed download retry resumes before upload, process-killed upload retry reuses complete snapshot and prefix, original target survives failure, queued/download/upload paired cancellation and target/temp preservation, failed-group discard, excluded root skips upload, private staging cleaned on success/cancel")
 }
}
