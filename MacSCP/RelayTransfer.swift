import Foundation

// Both queue rows belong to one lifecycle. The upload is never retried as an
// independent local upload while its prerequisite is incomplete.
final class RelayTransfer {
 enum Phase {case waiting,running,failed,completed,cancelled,discarded}
 let id:UUID
 let download:TransferJob,upload:TransferJob
 let staging:URL
 private let sourceSite:Session?,targetSite:Session?
 private var recoveryEnabled=false
 private let lock=NSLock()
 private var state=Phase.waiting,cancellationRequested=false,preservingForExit=false
 private weak var scheduler:TransferScheduler?
 var recoveryChanged:((Bool)->Void)?;var persistRecovery:(()throws->Void)?
 var changed:(()->Void)?;var onTerminal:(()->Void)?
 var phase:Phase{lock.lock();defer{lock.unlock()};return state}
 var endpoints:(Session,Session)?{guard let source=sourceSite,let target=targetSite else{return nil};return(source,target)}
 var needsSourceConnection:Bool{!download.finished || download.failed}
 var jobIDs:Set<UUID>{[download.id,upload.id]}
 var canDiscard:Bool{download.finished && upload.finished && !download.isExecuting && !upload.isExecuting && !(scheduler?.contains(download.id) ?? false) && !(scheduler?.contains(upload.id) ?? false)}
 init(file:DragFile,destination:String,policy:TransferPolicy=TransferPolicy(),sourceName:String?=nil,targetName:String?=nil,temporaryRoot:URL=FileManager.default.temporaryDirectory,sourceSite:Session?=nil,targetSite:Session?=nil)throws{
  id=UUID();self.sourceSite=sourceSite;self.targetSite=targetSite;_ = try sourceSite?.validated();_ = try targetSite?.validated()
  guard file.connection != nil,file.path.hasPrefix("/"),destination.hasPrefix("/") else{throw SFTPError.message("中转路径或源会话无效")}
  let name=(file.path as NSString).lastPathComponent
  guard !name.isEmpty,name != "/",name != ".",name != ".." else{throw SFTPError.message("不能中转根目录")}
  _ = try policy.validated()
  staging=temporaryRoot.appendingPathComponent("MacSCP-Relay-"+UUID().uuidString,isDirectory:true)
  try FileManager.default.createDirectory(at:staging,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
  let local=staging.appendingPathComponent(name)
  download=TransferJob(up:false,source:file.path,destination:local.path,directory:file.directory,size:file.size)
  upload=TransferJob(up:true,source:local.path,destination:destination,directory:file.directory,size:file.size)
  download.endpointDescription=sourceSite.map{$0.fileProtocol.title+" · "+$0.identity};upload.endpointDescription=targetSite.map{$0.fileProtocol.title+" · "+$0.identity}
  download.policy=policy;download.policyConfigured=true
  upload.policy=TransferPolicy(verifyChecksum:policy.verifyChecksum,text:policy.text);upload.policyConfigured=true
  download.displayDestination="本机中转："+name;upload.displaySource="本机中转："+name
  if let name=sourceName{download.displaySource=name+":"+file.path}
  if let name=targetName{upload.displayDestination=name+":"+destination}
  wireCallbacks()
 }
 private func wireCallbacks(){
  download.onRecoveryChange={[weak self] force in self?.recoveryChanged?(force)};upload.onRecoveryChange={[weak self] force in self?.recoveryChanged?(force)}
  upload.persistRecovery={[weak self] in try self?.persistRecovery?()}
  download.onCompletion={[weak self] in self?.downloadFinished()}
  upload.onCompletion={[weak self] in guard let self=self else{return};if self.upload.wasCancelled{self.cancel()};self.settle()}
 }
 init(record:RelayRecord)throws{
  let record=try record.validated();try record.checkStaging()
  id=record.id;staging=URL(fileURLWithPath:record.staging);sourceSite=record.download.site;targetSite=record.upload.site;recoveryEnabled=true
  download=try TransferJob.restore(record.download);upload=try TransferJob.restore(record.upload)
  download.recoverySite=nil;upload.recoverySite=nil;download.strictCompletedManifest=true
  let name=(download.source as NSString).lastPathComponent
  download.displaySource=record.download.site.identity+":"+download.source;download.displayDestination="本机中转："+name
  upload.displaySource="本机中转："+name;upload.displayDestination=record.upload.site.identity+":"+upload.destination
  wireCallbacks()
 }
 func enableRecovery(){lock.lock();recoveryEnabled=true;lock.unlock()}
 var canPreserve:Bool{lock.lock();defer{lock.unlock()};return recoveryEnabled && sourceSite != nil && targetSite != nil}
 func recoveryRecord()->RelayRecord?{
  lock.lock();let retain=recoveryEnabled && !cancellationRequested && state != .completed && state != .discarded && state != .cancelled;lock.unlock()
  guard retain,!download.wasCancelled,!upload.wasCancelled,let source=sourceSite,let target=targetSite else{return nil}
  return RelayRecord(id:id,staging:staging.path,download:download.snapshot(site:source),upload:upload.snapshot(site:target))
 }
 func suspendForExit(){lock.lock();guard !preservingForExit else{lock.unlock();return};preservingForExit=true;lock.unlock();download.suspendForExit();upload.suspendForExit();scheduler?.refresh();recoveryChanged?(true);settle()}
 func start(on scheduler:TransferScheduler,paused:Bool=false,speedLimit:UInt64=0)throws{
  guard phase == .waiting || phase == .failed else{throw SFTPError.message("中转任务已结束或正在执行；取消后请重新拖拽")}
  guard !scheduler.contains(download.id),!scheduler.contains(upload.id) else{throw SFTPError.message("中转任务正在结束，请稍后重试")}
  self.scheduler=scheduler
  let needsDownload = !download.finished || download.failed
  if download.failed{download.reset()}
  if upload.finished{upload.reset()}
  lock.lock();state = .running;preservingForExit=false;lock.unlock()
  for job in [download,upload]{job.speedLimit=job.overrideSpeedLimit ?? speedLimit;job.setPaused(paused)}
  recoveryChanged?(true)
  let second=BlockOperation{[weak self] in guard let self=self else{return};self.upload.execute{self.changed?()}}
  upload.operation=second
  if needsDownload{
   let first=BlockOperation{[weak self] in guard let self=self else{return};self.download.execute{self.changed?()}}
   download.operation=first;second.addDependency(first)
   scheduler.addOperation(first,job:download)
  }
  scheduler.addOperation(second,job:upload)
  changed?()
 }
 func cancel(){
  if download.finished && upload.finished && !download.failed && !upload.failed && !download.wasCancelled && !upload.wasCancelled{return}
  lock.lock();guard !cancellationRequested,state != .completed,state != .discarded else{lock.unlock();return};cancellationRequested=true;lock.unlock()
  download.cancel();upload.cancel();scheduler?.refresh();settle()
 }
 func discard(){guard canDiscard else{return};lock.lock();state = .discarded;lock.unlock();try? FileManager.default.removeItem(at:staging);recoveryChanged?(true)}
 private func downloadFinished(){
  if download.wasCancelled{cancel();settle();scheduler?.refresh();return}
  lock.lock();let cancelled=cancellationRequested;lock.unlock()
  if cancelled{upload.cancel()}
  else if download.failed{upload.finishWithoutStarting("等待下载重试："+download.column("progress"),failed:true)}
  else if download.wasRootExcluded{upload.finishWithoutStarting("已跳过（传输掩码）")}
  settle();scheduler?.refresh()
 }
 private func settle(){
  guard download.finished,upload.finished,!download.isExecuting,!upload.isExecuting else{changed?();return}
  lock.lock()
  if state == .discarded{lock.unlock();return}
  let previous=state
  if cancellationRequested{state = .cancelled}
  else{state = download.failed || upload.failed ? .failed : .completed}
  let clean=state == .completed || state == .cancelled,transitioned=previous != state
  lock.unlock()
  if clean{try? FileManager.default.removeItem(at:staging)}
  recoveryChanged?(true);changed?();if transitioned{onTerminal?()}
 }
 deinit{if !recoveryEnabled || state == .completed || state == .cancelled || state == .discarded{try? FileManager.default.removeItem(at:staging)}}
}
