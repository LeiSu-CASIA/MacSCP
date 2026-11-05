import Foundation
struct SyncRetryContext {
 let id:UUID,site:Session,socket:String,settings:SyncSettings,policy:TransferPolicy,anchor:ContinuousRootGuard
 var localRoot:String{anchor.requestedLocal};var remoteRoot:String{anchor.requestedRemote}
 init(id:UUID=UUID(),site:Session,socket:String,settings:SyncSettings,policy:TransferPolicy,local:String,remote:String,client:RemoteFileClient)throws{self.id=id;self.site=try site.validated();self.socket=socket;self.settings=try settings.validated();self.policy=try policy.validated();anchor=try ContinuousRootGuard(local:local,remote:remote,client:client)}
}
struct SyncRetryScope:Hashable {
 enum Kind:Hashable{case transfer,deletion,timestamp}
 let relative:String,directory:Bool,recursive:Bool,upload:Bool,kind:Kind
}
struct SyncRetryIntent {
 let context:SyncRetryContext,scopes:[SyncRetryScope]
 init(context:SyncRetryContext,action:SyncCandidate)throws{
  guard action.executable,!action.deletion || context.settings.cleanup,!action.timestampOnly || context.settings.comparison.fileMode == .timestamps else{throw SFTPError.message("无法记录未解决或与原选项不符的同步动作")};try SyncDeletionPlan.checkedRelative(action.relative)
  self.context=context;let kind:SyncRetryScope.Kind=action.deletion ? .deletion : action.timestampOnly ? .timestamp : .transfer
  if let contents=action.contents{
   guard action.directory,!action.timestampOnly else{throw SFTPError.message("无效的同步目录选择")}
   let paths=action.deletion ? contents.selectedRoots : contents.selected.sorted()
   scopes=try paths.map{path in try SyncDeletionPlan.checkedRelative(path);guard path==action.relative || path.hasPrefix(action.relative+"/"),let node=contents.manifest[path] else{throw SFTPError.message("同步重试范围超出原勾选目录")};return SyncRetryScope(relative:path,directory:node.directory,recursive:action.deletion && node.directory,upload:action.upload!,kind:kind)}
  }else{scopes=[SyncRetryScope(relative:action.relative,directory:action.directory,recursive:action.directory,upload:action.upload!,kind:kind)]}
 }
}
struct SyncRecompareResult {
 let local:[String:SyncNode],remote:[String:SyncNode],candidates:[SyncCandidate],deletions:[String:SyncDeletionPlan],timestamps:[String:SyncTimestampPlan],notices:[String]
}
enum SyncRecompare {
 private static func promote(_ rows:[SyncCandidate],local:[String:SyncNode],remote:[String:SyncNode],policy:TransferPolicy)throws->[SyncCandidate]{
  var result=[String:SyncCandidate](),groups=[String:[SyncCandidate]](),parents=[String:String]();let localIndex=SyncSnapshotIndex(local),remoteIndex=SyncSnapshotIndex(remote)
  for row in rows {
   guard let up=row.upload,!row.deletion,!row.timestampOnly,!row.typeConflict else{result[row.relative]=row;continue}
   let target=up ? remote : local,source=up ? local : remote;var prefix="",handled=false
   for part in row.relative.split(separator:"/").dropLast(){prefix=prefix.isEmpty ? String(part) : prefix+"/"+part
    if let existing=target[prefix],!existing.directory{result[prefix]=SyncCandidate(relative:prefix,local:local[prefix],remote:remote[prefix],upload:nil,selected:false,typeConflict:true);handled=true;break}
    if target[prefix]==nil{guard source[prefix]?.directory==true else{throw SFTPError.message("重新比较缺少源父目录")};let key=(up ? "up:" : "down:")+prefix;groups[key,default:[]].append(row);parents[key]=prefix;handled=true;break}
   }
   if !handled{result[row.relative]=row}
  }
  for (key,children) in groups{let parent=parents[key]!,up=children[0].upload!;let source=up ? local : remote,index=up ? localIndex : remoteIndex;var model=try SyncContents(root:parent,snapshot:index.subtree(parent,values:source),policy:policy,excludePrivateStages:true);model.setAll(false)
   for row in children{if let contents=row.contents{for path in contents.selected{model.set(path,on:true)}}else{model.set(row.relative,on:true)}}
   guard !model.selected.isEmpty else{continue};var row=SyncCandidate(relative:parent,local:local[parent],remote:remote[parent],upload:up,selected:true,typeConflict:false,mirror:children.contains{$0.mirror});row.contents=model;result[parent]=row
  }
  let conflicts=result.values.filter{$0.typeConflict}.map{$0.relative};return result.values.filter{row in !conflicts.contains(where:{row.relative.hasPrefix($0+"/")})}
 }
 static func prepare(context:SyncRetryContext,intents:[SyncRetryIntent],client:RemoteFileClient,checkpoint:@escaping()throws->Void)throws->SyncRecompareResult{
  guard !intents.isEmpty,intents.allSatisfy({$0.context.id==context.id && $0.context.site.identity==context.site.identity && $0.context.localRoot==context.localRoot && $0.context.remoteRoot==context.remoteRoot && $0.context.settings==context.settings && $0.context.policy==context.policy}) else{throw SFTPError.message("不能合并不同来源的同步重试")}
  try checkpoint();try context.anchor.validate(client:client)
  var local=try SyncPlanner.local(context.localRoot,checkpoint:checkpoint),remote=try SyncPlanner.remote(context.remoteRoot,client:client)
  let permits=try context.policy.predicate(),allows:(String,Bool)->Bool={!TransferPrivateNames.contains(($0 as NSString).lastPathComponent) && permits($0,($0 as NSString).lastPathComponent,$1)}
  let allScopes=Set(intents.flatMap{$0.scopes});let scopes=allScopes.filter{scope in var parent=(scope.relative as NSString).deletingLastPathComponent;while !parent.isEmpty,parent != "/"{if allScopes.contains(SyncRetryScope(relative:parent,directory:true,recursive:true,upload:scope.upload,kind:scope.kind)){return false};parent=(parent as NSString).deletingLastPathComponent};return true}
  let localIndex=SyncSnapshotIndex(local),remoteIndex=SyncSnapshotIndex(remote),exact=Set(scopes.map{$0.relative}),recursive=Set(scopes.filter{$0.recursive}.map{$0.relative})
  // Hash only paths inside the original intended scopes; unrelated payloads are never needed here.
  func inScope(_ path:String)->Bool{if exact.contains(path){return true};var parent=(path as NSString).deletingLastPathComponent;while !parent.isEmpty,parent != "/"{if recursive.contains(parent){return true};parent=(parent as NSString).deletingLastPathComponent};return false}
  if context.settings.comparison.checksum{
   local=try SyncChecksums.local(local,root:context.localRoot,paths:Set(SyncComparison.checksumPaths(local,allows:allows).filter(inScope)),checkpoint:checkpoint)
   remote=try SyncChecksums.remote(remote,root:context.remoteRoot,client:client,paths:Set(SyncComparison.checksumPaths(remote,allows:allows).filter(inScope)))
  }
  var candidates=[String:SyncCandidate](),notices=[String]()
  for scope in scopes.sorted(by:{$0.relative<$1.relative}){
   try checkpoint();try SyncDeletionPlan.checkedRelative(scope.relative)
   let source=scope.kind == .deletion ? (scope.upload ? remote[scope.relative] : local[scope.relative]) : (scope.upload ? local[scope.relative] : remote[scope.relative])
   if let source=source,source.directory != scope.directory{notices.append("原选中项目类型已变化，未自动纳入："+scope.relative.debugDescription);continue}
   if scope.directory && !scope.recursive{
    let index=scope.upload ? localIndex : remoteIndex
    if index.hasChildren(scope.relative){notices.append("原选空目录已新增子项，未自动扩大范围："+scope.relative.debugDescription);continue}
   }
   func subset(_ snapshot:[String:SyncNode],_ index:SyncSnapshotIndex)->[String:SyncNode]{scope.recursive ? index.subtree(scope.relative,values:snapshot) : snapshot[scope.relative].map{[scope.relative:$0]} ?? [:]}
   var settings=context.settings;settings.direction=scope.upload ? .upload : .download;settings.cleanup=scope.kind == .deletion
   if scope.kind == .timestamp{settings.comparison=SyncComparisonOptions(fileMode:.timestamps,timeTolerance:context.settings.comparison.timeTolerance,timestampSameSizeOnly:context.settings.comparison.timestampSameSizeOnly)}
   let ls=subset(local,localIndex),rs=subset(remote,remoteIndex),textDifferences=try SyncTextComparison.differences(local:ls,remote:rs,localRoot:context.localRoot,remoteRoot:context.remoteRoot,policy:context.policy,settings:settings,client:client,allows:allows,checkpoint:checkpoint)
   let rows=try SyncComparison.plannedCandidates(local:ls,remote:rs,settings:settings,allows:allows,textDifferences:textDifferences)
   for var row in rows{
    guard row.typeConflict || (scope.kind == .deletion ? row.deletion : scope.kind == .timestamp ? row.timestampOnly : !row.deletion && !row.timestampOnly) else{continue}
    if row.directory && !scope.recursive && !row.deletion{
     var chosen=try SyncContents(root:row.relative,snapshot:scope.upload ? local : remote,policy:context.policy,excludePrivateStages:true);chosen.setAll(false);if chosen.leaves.contains(scope.relative){chosen.set(scope.relative,on:true)};guard !chosen.selected.isEmpty else{continue};row.contents=chosen
    }
    if let previous=candidates[row.relative]{guard previous.upload==row.upload,previous.deletion==row.deletion,previous.timestampOnly==row.timestampOnly else{throw SFTPError.message("重试范围存在方向冲突，请分别重新比较")}}
    candidates[row.relative]=row
   }
  }
  let rows=try promote(Array(candidates.values),local:local,remote:remote,policy:context.policy).sorted{$0.relative<$1.relative}
  // Scopes from different attempts may overlap. Never enqueue a parent and its child independently.
  for (index,row) in rows.enumerated() where row.directory{if rows.dropFirst(index+1).contains(where:{$0.relative.hasPrefix(row.relative+"/")}){throw SFTPError.message("重试范围互相包含，请分别选择原任务重新比较")}}
  var deletions=[String:SyncDeletionPlan](),timestamps=[String:SyncTimestampPlan]()
  for row in rows where row.deletion{deletions[row.relative]=try SyncDeletionPlan.prepare(row,localRoot:context.localRoot,remoteRoot:context.remoteRoot,localSnapshot:local,remoteSnapshot:remote,client:client)}
  for row in rows where row.timestampOnly && row.executable{timestamps[row.relative]=try SyncTimestampPlan.prepare(row,localRoot:context.localRoot,remoteRoot:context.remoteRoot,client:client)}
  try checkpoint();try context.anchor.validate(client:client)
  return .init(local:local,remote:remote,candidates:rows,deletions:deletions,timestamps:timestamps,notices:notices)
 }
}
final class SyncRecompareOperation {
 let context:SyncRetryContext,intents:[SyncRetryIntent],socket:String
 private let lock=NSLock();private var cancelled=false,client:RemoteFileClient?
 init(context:SyncRetryContext,intents:[SyncRetryIntent],socket:String){self.context=context;self.intents=intents;self.socket=socket}
 var stopped:Bool{lock.lock();defer{lock.unlock()};return cancelled}
 func cancel(){lock.lock();cancelled=true;let client=client;lock.unlock();client?.interrupt()}
 func checkpoint()throws{if stopped{throw SFTPError.message("重新比较已取消")}}
 func run(factory:()throws->RemoteFileClient)throws->SyncRecompareResult{
  try checkpoint();let client=try factory();lock.lock();self.client=client;let stop=cancelled;lock.unlock();if stop{client.interrupt()};defer{lock.lock();self.client=nil;lock.unlock();client.close()};client.checkpoint={try self.checkpoint()}
  return try SyncRecompare.prepare(context:context,intents:intents,client:client,checkpoint:checkpoint)
 }
}
