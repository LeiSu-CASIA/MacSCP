import Foundation
import CoreServices
@main struct ContinuousEngineTests {
 static func check(_ value:Bool,file:StaticString = #file,line:UInt = #line){precondition(value,file:file,line:line)}
 static func wait(_ condition:()->Bool,seconds:Double=8){let end=Date().addingTimeInterval(seconds);while !condition(),Date()<end{RunLoop.current.run(until:Date().addingTimeInterval(0.02))};check(condition())}
 static func pump(_ seconds:Double){RunLoop.current.run(until:Date().addingTimeInterval(seconds))}
 static func main()throws {
  let fm=FileManager.default,root=fm.temporaryDirectory.appendingPathComponent("continuous-engine-"+UUID().uuidString)
  try fm.createDirectory(at:root,withIntermediateDirectories:false);defer{try? fm.removeItem(at:root)}
  let local=root.appendingPathComponent("local"),remote=root.appendingPathComponent("remote")
  for dir in [local,remote]{try fm.createDirectory(at:dir,withIntermediateDirectories:false)}
  func put(_ path:String,_ text:String)throws{try Data(text.utf8).write(to:local.appendingPathComponent(path))}
  func text(_ path:String)->String?{try? String(contentsOf:remote.appendingPathComponent(path),encoding:.utf8)}
  var options=ContinuousOptions();options.interval=0.5;options.settle=0.5;options.initialSync=false
  let operations=OperationQueue();operations.maxConcurrentOperationCount=1
  func engine(_ settings:ContinuousOptions?=nil,events:Bool=false)->ContinuousSyncEngine{ContinuousSyncEngine(local:local.path,remote:remote.path,options:settings ?? options,policy:TransferPolicy(),selected:[],copyPermissions:true,useEvents:events,factory:{try SFTPClient(command:"/usr/libexec/sftp-server",arguments:[])})}
  try put("file","baseline")
  let monitor=engine();var jobs=[TransferJob](),logs=[String]()
  monitor.onLog={logs.append($0)};monitor.onJob={job in jobs.append(job);operations.addOperation{job.execute({})}}
  monitor.start();monitor.start();wait{monitor.state == .watching};pump(1.6);check(jobs.isEmpty && text("file")==nil)
  try put("file","changed");wait{jobs.count==1 && jobs[0].finished && monitor.state == .watching}
  check(text("file")=="changed");pump(1.1);check(jobs.count==1)
  monitor.pause(true);wait{monitor.state == .paused};try put("file","paused edit");pump(1.6);check(jobs.count==1 && text("file")=="changed")
  monitor.pause(false);wait{jobs.count==2 && jobs[1].finished && monitor.state == .watching};check(text("file")=="paused edit")
  monitor.stop();wait{monitor.state.terminal};try put("file","after stop");pump(1.2);check(jobs.count==2 && text("file")=="paused edit")
  // Preparation is read-only until the controller approves the canonical roots/deletion scope.
  var initial=options;initial.initialSync=true
  let guarded=engine(initial);var prepared=false,guardedJobs=[TransferJob]()
  guarded.onReady={_ in prepared=true};guarded.onJob={job in guardedJobs.append(job);operations.addOperation{job.execute({})}}
  guarded.start();wait{prepared};pump(1.3);check(guardedJobs.isEmpty && text("file")=="paused edit")
  guarded.approve();wait{guardedJobs.count==1 && guardedJobs[0].finished && guarded.state == .watching};check(text("file")=="after stop")
  guarded.stop();wait{guarded.state.terminal}
  // A batch waiting in a paused global queue can be stopped without starting any client writes.
  let queued=engine();var pending:TransferJob?
  queued.onJob={pending=$0};queued.start();wait{queued.state == .watching};try put("file","never published")
  wait{pending != nil};queued.stop();wait{queued.state.terminal};check(pending!.finished && pending!.wasCancelled && text("file")=="after stop")
  // External target changes fail once. No authentication/reconnect/retry loop follows a failure.
  let conflict=engine();var submissions=0
  conflict.onJob={job in submissions+=1;operations.addOperation{job.execute({})}}
  conflict.start();wait{conflict.state == .watching}
  try Data("external writer".utf8).write(to:remote.appendingPathComponent("file"));try put("file","my change")
  wait{conflict.state.terminal};if case .failed=conflict.state{}else{fatalError("conflict reason lost")};pump(1.2)
  check(submissions==0 && text("file")=="external writer")
  // Failure during an active queued batch must survive cancellation of that batch.
  let invalidated=engine();var stoppedJob:TransferJob?
  invalidated.onJob={stoppedJob=$0};invalidated.start();wait{invalidated.state == .watching};try put("file","invalidate pending")
  wait{stoppedJob != nil};invalidated.invalidate("fixture root invalidated");wait{invalidated.state.terminal}
  check(stoppedJob!.wasCancelled);if case .failed(let reason)=invalidated.state{check(reason=="fixture root invalidated")}else{fatalError("failure replaced by stopped state")}
  // Exercise real FSEvents on one newly owned directory, not a user folder.
  if ProcessInfo.processInfo.environment["MACSCP_NATIVE_EVENTS"]=="1"{
  let eventsRoot=root.appendingPathComponent("events");try fm.createDirectory(at:eventsRoot,withIntermediateDirectories:false)
  let lock=NSLock();var observed=false
  let events=try ContinuousEvents(root:eventsRoot.path,queue:DispatchQueue(label:"fixture.native.events")){path,flags in
   if path.hasSuffix("/event-file") && flags & UInt32(kFSEventStreamEventFlagItemCreated|kFSEventStreamEventFlagItemModified) != 0{lock.lock();observed=true;lock.unlock()}
  }
  try Data("event".utf8).write(to:eventsRoot.appendingPathComponent("event-file"))
  wait({lock.lock();defer{lock.unlock()};return observed},seconds:6);events.stop();print("PASS: actual FSEvents on newly owned directory")}
  operations.waitUntilAllOperationsAreFinished()
  print("PASS: continuous engine read-only preparation/approval, no initial sync, stable edit queue, no duplicate start/jobs, pause/resume/stop, paused queue cancellation, terminal conflict without retry; local SFTP and owned fixtures only")
 }
}
