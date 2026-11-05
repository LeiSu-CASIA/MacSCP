import Foundation

enum QueueMove {case up,down,first}
enum QueueOrdering {
 static func moved(_ ids:[UUID],selected:Set<UUID>,direction:QueueMove)->[UUID]{
  var result=ids
  switch direction{
  case .first:return ids.filter{selected.contains($0)}+ids.filter{!selected.contains($0)}
  case .up:
   guard result.count>1 else{return result}
   for i in 1..<result.count where selected.contains(result[i]) && !selected.contains(result[i-1]){result.swapAt(i,i-1)}
  case .down:
   guard result.count>1 else{return result}
   for i in stride(from:result.count-2,through:0,by:-1) where selected.contains(result[i]) && !selected.contains(result[i+1]){result.swapAt(i,i+1)}
  }
  return result
 }
}

// Only ready operations are admitted to the worker queue. Keeping pending work
// here makes arbitrary row order affect actual starts, beyond the five system
// queuePriority values, without interrupting running transfers.
final class TransferScheduler {
 private struct Entry {let id:UUID;let operation:Operation;let canStart:()->Bool}
 private let lock=NSLock()
 private let workers=OperationQueue()
 private var pending=[Entry](),active=[UUID:Operation]()
 private var limit=3,suspended=false
 var maxConcurrentOperationCount:Int{get{lock.lock();defer{lock.unlock()};return limit}set{lock.lock();limit=max(1,min(8,newValue));pump();lock.unlock()}}
 var isSuspended:Bool{get{lock.lock();defer{lock.unlock()};return suspended}set{lock.lock();suspended=newValue;pump();lock.unlock()}}
 var waitingIDs:[UUID]{lock.lock();defer{lock.unlock()};return pending.filter{!$0.operation.isCancelled}.map{$0.id}}
 func contains(_ id:UUID)->Bool{lock.lock();defer{lock.unlock()};return active[id] != nil || pending.contains{$0.id==id}}
 @discardableResult func addOperation(_ operation:Operation,job:TransferJob)->Bool{addOperation(operation,id:job.id,canStart:{[weak job] in guard let job=job else{return false};return !job.isPaused && !job.finished})}
 @discardableResult func addOperation(_ operation:Operation,id:UUID,canStart:@escaping()->Bool={true})->Bool{
  lock.lock();defer{lock.unlock()}
  guard !operation.isExecuting,!operation.isFinished,active[id]==nil,!active.values.contains(where:{$0 === operation}),!pending.contains(where:{$0.id==id || $0.operation === operation}) else{return false}
  let previous=operation.completionBlock
  let identity=ObjectIdentifier(operation)
  operation.completionBlock={[weak self] in previous?();self?.completed(id,identity:identity)}
  pending.append(Entry(id:id,operation:operation,canStart:canStart));pump();return true
 }
 func refresh(){lock.lock();pump();lock.unlock()}
 @discardableResult func reorder(_ preferred:[UUID])->[UUID]{
  lock.lock();defer{lock.unlock()}
  let byID=Dictionary(uniqueKeysWithValues:pending.map{($0.id,$0)})
  let byOperation=Dictionary(uniqueKeysWithValues:pending.map{(ObjectIdentifier($0.operation),$0.id)})
  var visited=Set<UUID>(),visiting=Set<UUID>(),ordered=[Entry]()
  func visit(_ id:UUID){
   guard !visited.contains(id),!visiting.contains(id),let entry=byID[id] else{return}
   visiting.insert(id)
   // Preserve prerequisites even when a dependent upload is moved to the top.
   for dependency in entry.operation.dependencies{if let ancestor=byOperation[ObjectIdentifier(dependency)]{visit(ancestor)}}
   visiting.remove(id);visited.insert(id);ordered.append(entry)
  }
  for id in preferred+pending.map({$0.id}){visit(id)}
  pending=ordered;let order=pending.filter{!$0.operation.isCancelled}.map{$0.id};pump();return order
 }
 func cancelAllOperations(){lock.lock();for entry in pending{entry.operation.cancel()};workers.cancelAllOperations();pump();lock.unlock()}
 private func completed(_ id:UUID,identity:ObjectIdentifier){lock.lock();if let operation=active[id],ObjectIdentifier(operation)==identity{active.removeValue(forKey:id)};pump();lock.unlock()}
 private func pump(){
  // Cancelled entries must finish even while the scheduler is globally paused.
  let cancelled=pending.filter{$0.operation.isCancelled};pending.removeAll{$0.operation.isCancelled}
  for entry in cancelled{workers.addOperation(entry.operation)}
  while !suspended && active.count<limit{
   guard let index=pending.firstIndex(where:{$0.operation.isReady && $0.canStart()}) else{return}
   let entry=pending.remove(at:index);active[entry.id]=entry.operation;workers.addOperation(entry.operation)
  }
 }
}
