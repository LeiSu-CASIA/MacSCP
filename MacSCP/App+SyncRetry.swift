import Cocoa
extension App {
 func syncQueueValue(_ job:TransferJob,_ key:String)->String{let value=job.column(key);return key=="progress" ? value+(syncRetryNotes[job.id].map{" · "+$0} ?? "") : value}
 @objc func recompareSelectedSync(){let rows=queueTable.selectedRowIndexes;let selected=jobs.enumerated().filter{(rows.isEmpty || rows.contains($0.offset)) && $0.element.finished && ($0.element.failed || $0.element.wasCancelled) && syncRetryIntents[$0.element.id] != nil && !syncRetrySuperseded.contains($0.element.id)}.map{$0.element};guard !selected.isEmpty else{status.stringValue="请选择失败或已取消、尚未重新处理的同步任务";return};beginSyncRecompare(selected)}
 func retryConnection(_ context:SyncRetryContext)throws->ConnectionTab{
  let matches=connections.filter{$0.session.identity==context.site.identity && $0.usable}
  if let original=matches.first(where:{$0.socket==context.socket}){return original}
  if let current=currentConnection,matches.contains(where:{$0 === current}){return current}
  guard matches.count==1 else{throw SFTPError.message(matches.isEmpty ? "请手动登录原服务器后重新比较："+context.site.identity : "原服务器有多个连接，请先切换到要用于重新比较的会话")};return matches[0]
 }
 func beginSyncRecompare(_ selected:[TransferJob]){
  var seen=Set<UUID>()
  for job in selected{
   guard let intent=syncRetryIntents[job.id],seen.insert(intent.context.id).inserted else{continue}
   let context=intent.context,id=context.id,origin=Set(selected.filter{syncRetryIntents[$0.id]?.context.id==id}.map{$0.id})
   if syncRecompareOperations[id] != nil{status.stringValue="此批同步正在重新比较；可取消选中任务来停止比较";continue}
   if let preview=syncRecomparePreviews[id]{if showsMainWindow{preview.showWindow(nil);preview.window?.makeKeyAndOrderFront(nil)};status.stringValue="此批同步已有待确认的新预览";continue}
   if jobs.contains(where:{(!$0.finished || $0.isExecuting || transfers.contains($0.id)) && syncRetryIntents[$0.id]?.context.id==id}){status.stringValue="此批同步仍有任务运行，请等待或取消并等待结束后重新比较";continue}
   do{
    let tab=try retryConnection(context),socket=tab.socket,site=tab.session,intents=selected.compactMap{syncRetryIntents[$0.id]}.filter{$0.context.id==id}
    if intents.flatMap({$0.scopes}).contains(where:{$0.upload}),site.fileProtocol != .sftp && !site.ftpSettings.allowNonAtomicWrites{throw SFTPError.message("原范围包含远程写入，请先连接明确允许写入的同一服务器")}
    let operation=SyncRecompareOperation(context:context,intents:intents,socket:socket);syncRecompareOperations[id]=operation;syncRecompareConnections[id]=socket
    for jobID in origin{syncRetryNotes[jobID]="正在重新比较；取消选中可停止"};status.stringValue="正在重新比较原同步范围（只读取，不自动执行）…";reloadQueue()
    DispatchQueue.global(qos:.userInitiated).async{[weak self,weak tab] in guard let self=self else{return}
     do{let result=try operation.run{try self.client(site,socket)}
      DispatchQueue.main.async{[weak self,weak tab] in guard let self=self else{return};self.syncRecompareOperations.removeValue(forKey:id)
       guard !operation.stopped,let tab=tab,self.connections.contains(where:{$0 === tab}),tab.usable else{self.finishSyncRecompare(id,origin:origin,message:"重新比较已取消或连接结束");return}
       if result.candidates.isEmpty && result.notices.isEmpty{self.markSyncRecompared(origin,message:"已重新比较，原范围无待处理项");self.syncRecompareConnections.removeValue(forKey:id);self.status.stringValue="重新比较完成，原范围没有待处理项目";return}
       let explanation="失败/取消任务重新比较 · 只处理原范围，需再次确认\n"+context.settings.comparison.summary+(result.notices.isEmpty ? "" : "\n"+result.notices.joined(separator:"\n"))
       let preview=self.makeSyncPreview(result.candidates,localRoot:context.localRoot,remoteRoot:context.remoteRoot,localSnapshot:result.local,remoteSnapshot:result.remote,deletions:result.deletions,site:site,socket:socket,policy:context.policy,comparisonSummary:explanation,requireUploadTimestamp:context.settings.comparison.modificationTime,timestampPlans:result.timestamps,retryContext:context,onEnqueued:{[weak self] _ in self?.markSyncRecompared(origin,message:"已创建重新比较后的新任务")})
       let closed=preview.onClosed;preview.onClosed={[weak self] in closed?();guard let self=self else{return};self.syncRecomparePreviews.removeValue(forKey:id);self.syncRecompareConnections.removeValue(forKey:id);for jobID in origin where !self.syncRetrySuperseded.contains(jobID){self.syncRetryNotes.removeValue(forKey:jobID)};self.reloadQueue()}
       self.syncRecomparePreviews[id]=preview;self.syncPreviews.append(preview);for jobID in origin{self.syncRetryNotes[jobID]="重新比较完成，等待新预览确认"};self.status.stringValue="已生成新的同步预览，尚未传输或清理";self.reloadQueue();if self.showsMainWindow{preview.showWindow(nil);preview.window?.makeKeyAndOrderFront(nil)}
      }
     }catch{DispatchQueue.main.async{[weak self] in guard let self=self else{return};self.syncRecompareOperations.removeValue(forKey:id);self.finishSyncRecompare(id,origin:origin,message:operation.stopped ? "重新比较已取消" : "重新比较失败："+error.localizedDescription)}}
    }
   }catch{status.stringValue=error.localizedDescription;status.toolTip=error.localizedDescription}
  }
 }
 private func markSyncRecompared(_ origin:Set<UUID>,message:String){syncRetrySuperseded.formUnion(origin);for job in jobs where origin.contains(job.id){job.releaseCompletedPreviewClosures()};for id in origin{syncRetryNotes[id]=message};reloadQueue()}
 private func finishSyncRecompare(_ id:UUID,origin:Set<UUID>,message:String){syncRecompareConnections.removeValue(forKey:id);for jobID in origin{syncRetryNotes.removeValue(forKey:jobID)};status.stringValue=message;status.toolTip=message;reloadQueue()}
 @discardableResult func cancelSyncRecompare(jobs:Set<UUID>)->Bool{let contexts=Set(jobs.compactMap{syncRetryIntents[$0]?.context.id});var cancelled=false;for id in contexts{if let operation=syncRecompareOperations[id]{operation.cancel();cancelled=true};if let preview=syncRecomparePreviews[id]{preview.close();cancelled=true}};return cancelled}
 func cancelSyncRecompare(socket:String){for (id,token) in Array(syncRecompareConnections) where token==socket{syncRecompareOperations[id]?.cancel();syncRecomparePreviews[id]?.close()}}
 func cancelAllSyncRecompare(){for operation in syncRecompareOperations.values{operation.cancel()};for preview in Array(syncRecomparePreviews.values){preview.close()}}
 func pruneSyncRetryRecords(){let ids=Set(jobs.map{$0.id});syncRetryIntents=syncRetryIntents.filter{ids.contains($0.key)};syncRetryNotes=syncRetryNotes.filter{ids.contains($0.key)};syncRetrySuperseded.formIntersection(ids);let contexts=Set(syncRetryIntents.values.map{$0.context.id});for id in Set(syncRecompareConnections.keys).subtracting(contexts){syncRecompareOperations[id]?.cancel();syncRecomparePreviews[id]?.close()}}
}
