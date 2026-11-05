import Foundation
final class QueueTrace {
 let condition=NSCondition();var starts=[Int](),ends=[Int]();var live=0,maximum=0
 func start(_ value:Int){condition.lock();starts.append(value);live+=1;maximum=max(maximum,live);condition.broadcast();condition.unlock()}
 func end(_ value:Int){condition.lock();ends.append(value);live-=1;condition.broadcast();condition.unlock()}
 func snapshot()->([Int],[Int],Int){condition.lock();defer{condition.unlock()};return(starts,ends,maximum)}
}
@main struct QueueOrderTests {
 static func wait(_ condition:()->Bool){let end=Date().addingTimeInterval(8);while !condition() && Date()<end{Thread.sleep(forTimeInterval:0.005)};precondition(condition(),"queue scheduling timeout")}
 static func main()throws{
  let ids=(0..<8).map{_ in UUID()}
  precondition(QueueOrdering.moved(ids,selected:Set([ids[1],ids[2],ids[5]]),direction:.up)==[ids[1],ids[2],ids[0],ids[3],ids[5],ids[4],ids[6],ids[7]])
  precondition(QueueOrdering.moved(ids,selected:Set([ids[1],ids[2],ids[5]]),direction:.down)==[ids[0],ids[3],ids[1],ids[2],ids[4],ids[6],ids[5],ids[7]])
  precondition(QueueOrdering.moved(ids,selected:Set([ids[2],ids[5]]),direction:.first)==[ids[2],ids[5],ids[0],ids[1],ids[3],ids[4],ids[6],ids[7]])
  let scheduler=TransferScheduler(),trace=QueueTrace();scheduler.maxConcurrentOperationCount=1;scheduler.isSuspended=true
  for i in ids.indices{let operation=BlockOperation{trace.start(i);trace.end(i)};precondition(scheduler.addOperation(operation,id:ids[i]));precondition(!scheduler.addOperation(operation,id:UUID()))}
  let desired=[7,2,5,0,6,1,4,3];precondition(scheduler.reorder(desired.map{ids[$0]})==desired.map{ids[$0]});precondition(trace.snapshot().0.isEmpty)
  scheduler.isSuspended=false;wait{ids.allSatisfy{!scheduler.contains($0)}}
  precondition(trace.snapshot().0==desired && trace.snapshot().2==1)

  let parallel=TransferScheduler(),concurrent=QueueTrace(),gate=DispatchSemaphore(value:0),parallelIDs=(0..<5).map{_ in UUID()}
  parallel.maxConcurrentOperationCount=2;parallel.isSuspended=true
  for i in 0..<5{parallel.addOperation(BlockOperation{concurrent.start(i);gate.wait();concurrent.end(i)},id:parallelIDs[i])}
  parallel.isSuspended=false;wait{concurrent.snapshot().0.count==2}
  precondition(Set(concurrent.snapshot().0)==Set([0,1]))
  parallel.reorder([parallelIDs[4],parallelIDs[3],parallelIDs[2]])
  parallel.maxConcurrentOperationCount=1
  gate.signal();wait{concurrent.snapshot().1.count==1}
  precondition(concurrent.snapshot().0.count==2) // Lowering the cap cannot start another job until the active count falls below it.
  gate.signal();wait{concurrent.snapshot().0.count==3};precondition(concurrent.snapshot().0.last==4)
  gate.signal();wait{concurrent.snapshot().0.count==4};precondition(concurrent.snapshot().0.last==3)
  gate.signal();wait{concurrent.snapshot().0.count==5};precondition(concurrent.snapshot().0.last==2)
  gate.signal();wait{parallelIDs.allSatisfy{!parallel.contains($0)}};precondition(concurrent.snapshot().2==2)

  let dependent=TransferScheduler(),dependencies=QueueTrace();dependent.maxConcurrentOperationCount=1;dependent.isSuspended=true
  let downID=UUID(),upID=UUID(),otherID=UUID()
  let down=BlockOperation{dependencies.start(0);dependencies.end(0)},up=BlockOperation{dependencies.start(1);dependencies.end(1)},other=BlockOperation{dependencies.start(2);dependencies.end(2)}
  up.addDependency(down)
  dependent.addOperation(down,id:downID);dependent.addOperation(other,id:otherID);dependent.addOperation(up,id:upID)
  precondition(dependent.reorder([upID,otherID,downID])==[downID,upID,otherID])
  dependent.isSuspended=false;wait{[downID,upID,otherID].allSatisfy{!dependent.contains($0)}};precondition(dependencies.snapshot().0==[0,1,2])
  dependent.isSuspended=true;let cancelledID=UUID();let cancelled=BlockOperation{fatalError("cancelled task must never run")};dependent.addOperation(cancelled,id:cancelledID);cancelled.cancel();dependent.refresh();wait{cancelled.isFinished};precondition(!dependent.contains(cancelledID) && dependent.isSuspended)

  let fm=FileManager.default,root=fm.temporaryDirectory.appendingPathComponent("queue-order-"+UUID().uuidString);try fm.createDirectory(at:root,withIntermediateDirectories:false);defer{try? fm.removeItem(at:root)}
  let real=TransferScheduler(),realTrace=QueueTrace();real.maxConcurrentOperationCount=1;real.isSuspended=true
  let bytes=Data(repeating:73,count:180000);var jobs=[TransferJob]()
  for i in 0..<3{let source=root.appendingPathComponent("source-\(i)"),target=root.appendingPathComponent("target-\(i)");try bytes.write(to:source);let job=TransferJob(up:false,source:source.path,destination:target.path,directory:false,size:UInt64(bytes.count));job.factory={try SFTPClient(command:"/usr/libexec/sftp-server",arguments:[])};if i==0{job.setPaused(true)};let operation=BlockOperation{realTrace.start(i);job.execute({});realTrace.end(i)};job.operation=operation;jobs.append(job);real.addOperation(operation,job:job)}
  real.reorder(jobs.reversed().map{$0.id});real.isSuspended=false
  wait{jobs[1].finished && jobs[2].finished};precondition(realTrace.snapshot().0==[2,1] && !jobs[0].finished)
  jobs[0].setPaused(false);real.refresh();wait{jobs.allSatisfy{$0.finished} && jobs.allSatisfy{!real.contains($0.id)}}
  precondition(realTrace.snapshot().0==[2,1,0]);for job in jobs{let actual=try Data(contentsOf:URL(fileURLWithPath:job.destination));precondition(!job.failed && actual==bytes)}
  // Recovery order is owned by the journal, so late progress snapshots cannot
  // overwrite a user's newer reordering with a stale position.
  let journalURL=root.appendingPathComponent("journal.json")
  let site=Session(name:"fixture",host:"localhost",user:"test",port:22,key:"")
  var journalIDs=[UUID]();var staleRecords=[TransferRecord]()
  do{
   let journal=try QueueJournal(url:journalURL)
   for i in 0..<4{let record=TransferRecord(id:UUID(),site:site,up:false,source:"/source/\(i)",destination:root.appendingPathComponent("recover-\(i)").path,directory:false,size:1,overwrite:false,resumes:[],completed:[],created:[]);journalIDs.append(record.id);staleRecords.append(record);try journal.save(record,force:true)}
   try journal.reorder([journalIDs[2],journalIDs[0]])
   precondition(journal.list().map{$0.id}==[journalIDs[2],journalIDs[1],journalIDs[0],journalIDs[3]])
   for record in staleRecords{try journal.save(record,force:true)}
   precondition(journal.list().map{$0.id}==[journalIDs[2],journalIDs[1],journalIDs[0],journalIDs[3]])
  }
  do{let restored=try QueueJournal(url:journalURL);precondition(restored.list().map{$0.id}==[journalIDs[2],journalIDs[1],journalIDs[0],journalIDs[3]]);try restored.remove(journalIDs[1]);precondition(restored.list().compactMap{$0.queuePosition}==[0,1,2])}
  print("PASS: stable multi-selection up/down/first, exact eight-task start order, duplicate rejection, live concurrency changes without interruption, dependency-aware prioritization, cancelled work finishes while globally paused, individually paused waiting work skips slots, real SFTP downloads follow reordered starts with exact bytes, recovery order persists and rejects stale progress positions")
 }
}
