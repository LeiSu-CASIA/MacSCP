import Foundation
import CryptoKit
import Darwin
import CoreServices

struct ContinuousOptions:Codable,Equatable {
 var recursive=true,cleanup=false,existingOnly=false,initialSync=true,continueOnError=false,selectedOnly=false,preserveTime=true,strictRemote=false
 var interval:Double=2,settle:Double=1.5
 func validated()throws->Self{guard interval.isFinite,settle.isFinite,(0.5...60).contains(interval),(0.5...30).contains(settle) else{throw SFTPError.message("检查间隔须为 0.5–60 秒，稳定等待为 0.5–30 秒")};return self}
 static func load(_ defaults:UserDefaults)->Self?{guard let data=defaults.data(forKey:"continuousOptions"),let saved=try? JSONDecoder().decode(Self.self,from:data) else{return nil};return try? saved.validated()}
 func save(_ defaults:UserDefaults)throws{_ = try validated();defaults.set(try JSONEncoder().encode(self),forKey:"continuousOptions")}
}
struct ContinuousScope {
 let options:ContinuousOptions,policy:TransferPolicy,selected:Set<String>,ignoredRoot:String
 private let predicate:(String,String,Bool)->Bool
 init(options:ContinuousOptions,policy:TransferPolicy,selected:Set<String>,ignoredRoot:String="")throws{self.options=try options.validated();self.policy=try policy.validated();self.selected=selected;self.ignoredRoot=ignoredRoot;predicate=try policy.predicate();if options.selectedOnly && selected.isEmpty{throw SFTPError.message("请先选择要监控的文件或目录")};for name in selected{try SyncDeletionPlan.checkedRelative(name)}}
 static func internalName(_ name:String)->Bool{TransferPrivateNames.contains(name)}
 func allows(_ path:String,_ directory:Bool)->Bool{
  if Self.internalName((path as NSString).lastPathComponent){return false}
  if !options.recursive && (directory || path.contains("/")){return false}
  if options.selectedOnly && !selected.contains(where:{path==$0 || path.hasPrefix($0+"/") || directory && $0.hasPrefix(path+"/")}){return false}
  return predicate(path,(path as NSString).lastPathComponent,directory)
 }
}
struct ContinuousLocalVersion:Equatable {
 let seconds:Int,nanoseconds:Int
 static func read(_ path:String)throws->Self{var value=stat();guard lstat(path,&value)==0 else{throw NSError(domain:NSPOSIXErrorDomain,code:Int(errno))};return Self(seconds:value.st_ctimespec.tv_sec,nanoseconds:value.st_ctimespec.tv_nsec)}
}
struct ContinuousLocalSnapshot:Equatable {
 let nodes:[String:SyncNode],signatures:[String:LocalTrashSignature],versions:[String:ContinuousLocalVersion]
 static func ==(a:Self,b:Self)->Bool{a.signatures==b.signatures && a.versions==b.versions}
}
struct ContinuousRemoteNode:Equatable {
 let directory:Bool,size:UInt64,modified:UInt32,mode:UInt32;var digest:String?=nil
 var node:SyncNode{SyncNode(directory:directory,size:size,modified:Double(modified),checksum:digest)}
 static func ==(a:Self,b:Self)->Bool{a.directory==b.directory && a.mode==b.mode && (a.directory || a.size==b.size && a.modified==b.modified && a.digest==b.digest)}
}
struct ContinuousRootGuard {
 let requestedLocal:String,requestedRemote:String,local:String,remote:String,ancestors:[LocalTrashItem],remoteMode:UInt32
 init(local:String,remote:String,client:RemoteFileClient)throws {
  requestedLocal=local;requestedRemote=remote;self.local=try LocalTrashPlan.canonicalDirectory(local);self.remote=try client.canonical(remote)
  guard self.remote.hasPrefix("/"),!self.remote.contains("\0"),!self.remote.split(separator:"/").contains(".."),let root=try client.attributes(self.remote),root.mode&0o170000==0o040000 else{throw SFTPError.message("远程监控目录不可用")};remoteMode=root.mode
  var entries=[LocalTrashItem](),cursor="";for part in [""]+self.local.split(separator:"/").map(String.init){cursor=part.isEmpty ? "/" : SyncDeletionPlan.join(cursor,part);let signature=try LocalTrashSignature.read(cursor);guard signature.type==FileAttributeType.typeDirectory.rawValue else{throw SFTPError.message("本地监控路径不是目录")};entries.append(.init(path:cursor,signature:signature))};ancestors=entries
 }
 func validateLocal()throws{guard try LocalTrashPlan.canonicalDirectory(requestedLocal)==local else{throw SFTPError.message("本地监控根路径已改变")};for item in ancestors{guard try item.signature.sameDirectory(LocalTrashSignature.read(item.path)) else{throw SFTPError.message("本地监控父目录已被替换")}}}
 func validate(client:RemoteFileClient)throws{try validateLocal();guard try client.canonical(requestedRemote)==remote,try client.attributes(remote)?.mode==remoteMode else{throw SFTPError.message("远程监控根路径已改变")}}
}
enum ContinuousScanner {
 static func local(_ root:ContinuousRootGuard,scope:ContinuousScope,checkpoint:()throws->Void={})throws->ContinuousLocalSnapshot {
  try root.validateLocal();var nodes=[String:SyncNode](),signatures=[String:LocalTrashSignature](),versions=[String:ContinuousLocalVersion]()
  func scan(_ base:String,_ prefix:String,_ depth:Int)throws {
   try checkpoint();guard depth<512,nodes.count<100000 else{throw SFTPError.message("监控目录层级或条目数超过限制")}
   for url in try FileManager.default.contentsOfDirectory(at:URL(fileURLWithPath:base),includingPropertiesForKeys:nil){try checkpoint();if url.path==scope.ignoredRoot || !scope.ignoredRoot.isEmpty && url.path.hasPrefix(scope.ignoredRoot+"/"){continue};guard nodes.count<100000 else{throw SFTPError.message("监控条目数超过 100000")};let path=prefix+url.lastPathComponent,signature=try LocalTrashSignature.read(url.path),directory=signature.type==FileAttributeType.typeDirectory.rawValue
    nodes[path]=SyncNode(directory:directory,size:signature.size,modified:signature.modified?.timeIntervalSince1970 ?? 0)
    guard scope.allows(path,directory) else{continue}
    guard directory || signature.type==FileAttributeType.typeRegular.rawValue else{throw SFTPError.message("监控不跟随链接或特殊文件："+path.debugDescription)}
    signatures[path]=signature;versions[path]=try ContinuousLocalVersion.read(url.path);if directory{try scan(url.path,path+"/",depth+1)}
   }
  };try scan(root.local,"",0);try root.validateLocal();return .init(nodes:nodes,signatures:signatures,versions:versions)
 }
 static func remote(_ root:ContinuousRootGuard,scope:ContinuousScope,client:RemoteFileClient)throws->[String:ContinuousRemoteNode] {
  try root.validate(client:client);var result=[String:ContinuousRemoteNode]()
  func scan(_ base:String,_ prefix:String,_ depth:Int)throws {
   try client.checkpoint?();guard depth<512,result.count<100000 else{throw SFTPError.message("远程监控目录层级或条目数超过限制")}
   for entry in try client.list(base,maximumEntries:100000-result.count){let path=prefix+entry.name;try SyncDeletionPlan.checkedRelative(path);guard result[path]==nil else{throw SFTPError.message("服务器返回重名监控条目")};var node=ContinuousRemoteNode(directory:entry.directory,size:entry.size,modified:entry.modified,mode:entry.mode)
    if scope.allows(path,entry.directory){guard entry.directory || entry.mode&0o170000==0o100000 else{throw SFTPError.message("监控不跟随远程链接或特殊文件："+path.debugDescription)};if entry.directory{try scan(SyncDeletionPlan.join(base,entry.name),path+"/",depth+1)}else if scope.options.strictRemote{node.digest=try client.checksum(SyncDeletionPlan.join(base,entry.name))}}
    result[path]=node
   }
  };try scan(root.remote,"",0);return result
 }
}
enum ContinuousIssue:Error,LocalizedError {
 case sourceChanged(String),conflict(String),stopped
 var errorDescription:String?{switch self{case .sourceChanged(let path):return "本地文件仍在变化，等待稳定："+path.debugDescription;case .conflict(let path):return "远程目标在监控期间被其他操作改动，请重新核对："+path.debugDescription;case .stopped:return "监控已停止"}}
}
final class ContinuousOutcome {
 var remoteChanges=[String:ContinuousRemoteNode](),removed=Set<String>(),messages=[String](),skipped=0,transient=false,fatal=false,completed=0
}
struct ContinuousPlan {
 enum Action {case directory(String),upload(String),delete(SyncDeletionPlan)}
 let roots:ContinuousRootGuard,scope:ContinuousScope,local:ContinuousLocalSnapshot,remote:[String:ContinuousRemoteNode],actions:[Action],copyPermissions:Bool
 let initial:Bool,eventVersion:UInt64
 var bytes:UInt64{actions.reduce(0){sum,action in if case .upload(let path)=action{return sum+(local.nodes[path]?.size ?? 0)};return sum}}
 var deletions:[String]{actions.compactMap{if case .delete(let plan)=$0{return plan.candidate.relative};return nil}}
 static func prepare(roots:ContinuousRootGuard,scope:ContinuousScope,local:ContinuousLocalSnapshot,previous:ContinuousLocalSnapshot,remote:[String:ContinuousRemoteNode],accepted:[String:ContinuousRemoteNode],forced:Set<String>,initial:Bool,eventVersion:UInt64,copyPermissions:Bool,client:RemoteFileClient)throws->Self {
  let allows:(String,Bool)->Bool={scope.allows($0,$1)};var actions=[Action](),changed=Set<String>()
  for (path,sig) in local.signatures where previous.signatures[path] != sig || previous.versions[path] != local.versions[path] || forced.contains(where:{path==$0 || path.hasPrefix($0+"/")}){changed.insert(path)}
  var uploads=Set<String>(),directories=Set<String>(),deletes=[SyncDeletionPlan]()
  for path in local.nodes.keys.sorted(){guard let node=local.nodes[path],scope.allows(path,node.directory) else{continue};let target=remote[path]
   if let target=target,target.directory != node.directory{throw ContinuousIssue.conflict(path)}
   if node.directory{if target==nil && !scope.options.existingOnly{directories.insert(path)};continue}
   if scope.options.existingOnly && target==nil{continue}
   let shouldUpload:Bool
   if initial{var compared=node;if let options=scope.policy.text,try options.applies(path){let size=try TextTransfer.withSnapshot(SyncDeletionPlan.join(roots.local,path),options:options,upload:true,checkpoint:{try client.checkpoint?()}){url,_ in (try FileManager.default.attributesOfItem(atPath:url.path)[.size] as! NSNumber).uint64Value};compared=SyncNode(directory:false,size:size,modified:node.modified)};shouldUpload = try target==nil || SyncComparisonOptions(size:true,timeTolerance:0).shouldTransfer(source:compared,target:target!.node)}else{shouldUpload=changed.contains(path)}
   if shouldUpload{uploads.insert(path)}
  }
  let removed=Set(previous.signatures.keys).subtracting(local.signatures.keys)
  if scope.options.cleanup {
   let candidates=SyncComparison.candidates(local:local.nodes,remote:remote.mapValues{$0.node},direction:.upload,deleteExtraneous:true,allows:allows)
   for candidate in candidates where candidate.deletion {
    guard initial || removed.contains(where:{candidate.relative==$0 || candidate.relative.hasPrefix($0+"/")}) else{continue}
    let affected=remote.filter{$0.key==candidate.relative || $0.key.hasPrefix(candidate.relative+"/")}
    for (path,value) in affected where scope.allows(path,value.directory){guard accepted[path]==value else{throw ContinuousIssue.conflict(path)}}
    deletes.append(try SyncDeletionPlan.prepare(candidate,localRoot:roots.local,remoteRoot:roots.remote,localSnapshot:local.nodes,remoteSnapshot:remote.mapValues{$0.node},client:client))
   }
  }
  // Each mutation is bound to the last remote state accepted by this monitor.
  for path in uploads.union(directories){guard remote[path]==accepted[path] else{throw ContinuousIssue.conflict(path)};let parts=path.split(separator:"/");var parent="";for part in parts.dropLast(){parent=parent.isEmpty ? String(part) : parent+"/"+part;if let a=remote[parent],a.directory==false{throw ContinuousIssue.conflict(parent)}}}
  for path in directories.filter({directory in initial || changed.contains(directory) || uploads.contains(where:{$0.hasPrefix(directory+"/")})}).sorted(by:{$0.split(separator:"/").count == $1.split(separator:"/").count ? $0<$1 : $0.split(separator:"/").count<$1.split(separator:"/").count}){actions.append(.directory(path))}
  for path in uploads.sorted(){actions.append(.upload(path))};for plan in deletes{actions.append(.delete(plan))}
  return Self(roots:roots,scope:scope,local:local,remote:remote,actions:actions,copyPermissions:copyPermissions,initial:initial,eventVersion:eventVersion)
 }
 func validateSource(_ path:String)throws {
  try roots.validateLocal();var parent="";for part in path.split(separator:"/").dropLast(){parent=parent.isEmpty ? String(part) : parent+"/"+part;guard let expected=local.signatures[parent],try expected.sameDirectory(LocalTrashSignature.read(SyncDeletionPlan.join(roots.local,parent))) else{throw ContinuousIssue.sourceChanged(parent)}}
  guard let expected=local.signatures[path],try SyncDeletionPlan.localSignature(SyncDeletionPlan.join(roots.local,path))==expected,try ContinuousLocalVersion.read(SyncDeletionPlan.join(roots.local,path))==local.versions[path] else{throw ContinuousIssue.sourceChanged(path)}
 }
 private func checkRemote(_ path:String,client:RemoteFileClient,expected:ContinuousRemoteNode?)throws {
  let current=try client.attributes(SyncDeletionPlan.join(roots.remote,path));guard let expected=expected else{guard current==nil else{throw ContinuousIssue.conflict(path)};return}
  guard let current=current,current.mode==expected.mode,(expected.directory || current.size==expected.size && current.modified==expected.modified) else{throw ContinuousIssue.conflict(path)}
  if let digest=expected.digest{guard try client.checksum(SyncDeletionPlan.join(roots.remote,path))==digest else{throw ContinuousIssue.conflict(path)}}
 }
 private func checkParents(_ path:String,client:RemoteFileClient,outcome:ContinuousOutcome)throws {
  var prefix="";for part in path.split(separator:"/").dropLast(){prefix=prefix.isEmpty ? String(part) : prefix+"/"+part;let full=SyncDeletionPlan.join(roots.remote,prefix);guard let expected=outcome.remoteChanges[prefix] ?? remote[prefix],expected.directory,let current=try client.attributes(full),current.mode==expected.mode,try client.canonical(full)==full else{throw ContinuousIssue.conflict(prefix)}}
 }
 func execute(client:RemoteFileClient,resources:URL,outcome:ContinuousOutcome,checkpoint:()throws->Void)throws {
  try roots.validate(client:client)
  for action in actions {
   try checkpoint();let path:String;switch action{case .directory(let p),.upload(let p):path=p;case .delete(let p):path=p.candidate.relative}
   do {
    try roots.validate(client:client);try checkParents(path,client:client,outcome:outcome)
    switch action {
    case .directory:
     try validateSource(path);try checkRemote(path,client:client,expected:nil);try checkpoint();try client.mkdir(SyncDeletionPlan.join(roots.remote,path))
     guard let a=try client.attributes(SyncDeletionPlan.join(roots.remote,path)),a.mode&0o170000==0o040000 else{throw ContinuousIssue.conflict(path)};outcome.remoteChanges[path] = .init(directory:true,size:a.size,modified:a.modified,mode:a.mode)
    case .upload:
     try validateSource(path);try checkRemote(path,client:client,expected:remote[path])
     let source:FTPUploadSource
     do{source=try FTPUploadSource(URL(fileURLWithPath:SyncDeletionPlan.join(roots.local,path)))}catch{try validateSource(path);throw error}
     let snapshot=resources.appendingPathComponent(UUID().uuidString)
     defer{try? FileManager.default.removeItem(at:snapshot)}
     let descriptor=open(snapshot.path,O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW|O_CLOEXEC,0o600);guard descriptor>=0 else{throw SFTPError.message("无法创建监控上传快照")}
     let target=FileHandle(fileDescriptor:descriptor,closeOnDealloc:true);defer{try? target.close()};try source.file.seek(toOffset:0);var hash=SHA256(),size:UInt64=0
     while let data=try source.file.read(upToCount:1024*1024),!data.isEmpty{try checkpoint();do{try source.check()}catch{throw ContinuousIssue.sourceChanged(path)};guard UInt64(data.count)<=source.size-size else{throw ContinuousIssue.sourceChanged(path)};try target.write(contentsOf:data);hash.update(data:data);size+=UInt64(data.count)}
     try target.close();do{try source.check()}catch{throw ContinuousIssue.sourceChanged(path)};try validateSource(path);guard size==source.size else{throw ContinuousIssue.sourceChanged(path)}
     try FileManager.default.setAttributes([.modificationDate:local.signatures[path]!.modified!],ofItemAtPath:snapshot.path)
     let digest=hash.finalize().map{String(format:"%02x",$0)}.joined(),destination=SyncDeletionPlan.join(roots.remote,path)
     var publishedSize=size,publishedDigest=digest
     try withoutActuallyEscaping(checkpoint){point in
      func send(_ url:URL)throws{try client.upload(url,to:destination,overwrite:remote[path] != nil,permissions:copyPermissions ? source.permissions : nil,beforeCommit:{try point();try self.roots.validate(client:client);try self.checkParents(path,client:client,outcome:outcome);try self.validateSource(path);try self.checkRemote(path,client:client,expected:self.remote[path])})}
      if let options=scope.policy.text,try options.applies(path){try TextTransfer.withSnapshot(snapshot.path,options:options,upload:true,checkpoint:point){converted,_ in publishedSize=(try FileManager.default.attributesOfItem(atPath:converted.path)[.size] as! NSNumber).uint64Value;publishedDigest=try StableChecksum.local(converted.path,checkpoint:point);try send(converted)}}else{try send(snapshot)}
     }
     guard let a=try client.attributes(destination),a.mode&0o170000==0o100000,a.size==publishedSize,!scope.options.preserveTime || a.modified==source.modified else{throw ContinuousIssue.conflict(path)}
     if scope.policy.verifyChecksum || scope.options.strictRemote{guard try client.checksum(destination)==publishedDigest else{throw ContinuousIssue.conflict(path)}}
     outcome.remoteChanges[path] = .init(directory:false,size:a.size,modified:a.modified,mode:a.mode,digest:scope.options.strictRemote ? publishedDigest : nil)
    case .delete(let plan):
     if try SyncDeletionPlan.localSignature(SyncDeletionPlan.join(roots.local,path)) != nil{throw ContinuousIssue.sourceChanged(path)}
     try plan.execute(client:client,checkpoint:checkpoint,trash:{_ in throw SFTPError.message("远程监控不操作本地废纸篓")})
     for key in remote.keys where key==path || key.hasPrefix(path+"/"){outcome.removed.insert(key)}
    };outcome.completed+=1
   }catch {
    outcome.messages.append(path.debugDescription+"："+error.localizedDescription)
    if case ContinuousIssue.sourceChanged=error{outcome.transient=true;throw error}
    if case ContinuousIssue.conflict=error{outcome.fatal=true;throw error}
    // Distinguish a stable file/permission error from a lost connection; never keep reconnecting on transport failure.
    do{try checkpoint();_ = try client.attributes(roots.remote)}catch{outcome.fatal=true;throw error}
    if !scope.options.continueOnError{outcome.fatal=true;throw error};outcome.skipped+=1
   }
  }
 }
}

final class ContinuousEvents {
 private final class Box {let event:(String,UInt32)->Void;init(_ event:@escaping(String,UInt32)->Void){self.event=event}}
 private var stream:FSEventStreamRef?;private let box:Box
 init(root:String,queue:DispatchQueue,event:@escaping(String,UInt32)->Void)throws {
  box=Box(event);let retained=Unmanaged.passRetained(box)
  var context=FSEventStreamContext(version:0,info:retained.toOpaque(),retain:nil,release:{pointer in if let pointer=pointer{Unmanaged<Box>.fromOpaque(pointer).release()}},copyDescription:nil)
  let flags=FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes|kFSEventStreamCreateFlagFileEvents|kFSEventStreamCreateFlagWatchRoot|kFSEventStreamCreateFlagNoDefer)
  guard let stream=FSEventStreamCreate(nil,{_,info,count,paths,flags,_ in
   guard let info=info else{return};let box=Unmanaged<Box>.fromOpaque(info).takeUnretainedValue();let values=Unmanaged<CFArray>.fromOpaque(paths).takeUnretainedValue() as! [String]
   for i in 0..<min(count,values.count){box.event(values[i],flags[i])}
  },&context,[root] as CFArray,FSEventStreamEventId(kFSEventStreamEventIdSinceNow),0.25,flags) else{retained.release();throw SFTPError.message("无法创建目录事件监控")}
  self.stream=stream;FSEventStreamSetDispatchQueue(stream,queue)
  guard FSEventStreamStart(stream) else{stop();throw SFTPError.message("无法启动目录事件监控")}
 }
 func stop(){if let stream=stream{self.stream=nil;FSEventStreamStop(stream);FSEventStreamInvalidate(stream);FSEventStreamRelease(stream)}}
 deinit{stop()}
}
struct ContinuousBootstrap {let local:String,remote:String,directories:Int,initialCleanup:[String]}
final class ContinuousSyncEngine {
 enum State:Equatable {case preparing,watching,paused,syncing,stopping,stopped,failed(String)
  var terminal:Bool{switch self{case .stopped,.failed:return true;default:return false}}
  var title:String{switch self{case .preparing:return "准备监控…";case .watching:return "正在监控";case .paused:return "监控已暂停（当前队列继续）";case .syncing:return "正在更新远程目录";case .stopping:return "正在停止网络操作…";case .stopped:return "已停止";case .failed(let text):return "已停止："+text}}
 }
 let options:ContinuousOptions,policy:TransferPolicy,selected:Set<String>,requestedLocal:String,requestedRemote:String,copyPermissions:Bool
 let queue=DispatchQueue(label:"local.macscp.continuous."+UUID().uuidString)
 let factory:()throws->RemoteFileClient;private let useEvents:Bool
 private let lock=NSLock();private var value:State = .preparing,stopWanted=false,pauseWanted=false,client:RemoteFileClient?,job:TransferJob?
 private var started=false,pendingFailure:String?
 private var timer:DispatchSourceTimer?,events:ContinuousEvents?,roots:ContinuousRootGuard?,scope:ContinuousScope?,resources:URL?,resourceIdentity:LocalTrashSignature?
 private var previous:ContinuousLocalSnapshot?,pending:ContinuousLocalSnapshot?,pendingSince=Date(),lastEvent=Date.distantPast,remoteAccepted=[String:ContinuousRemoteNode](),forced=Set<String>(),eventVersion:UInt64=0,initialPending=false,approved=false
 var onReady:((ContinuousBootstrap)->Void)?,onState:((State)->Void)?,onLog:((String)->Void)?,onJob:((TransferJob)->Void)?
 var state:State{lock.lock();defer{lock.unlock()};return value}
 var stopped:Bool{lock.lock();defer{lock.unlock()};return stopWanted}
 var activeJob:TransferJob?{lock.lock();defer{lock.unlock()};return job}
 init(local:String,remote:String,options:ContinuousOptions,policy:TransferPolicy,selected:Set<String>,copyPermissions:Bool,useEvents:Bool=true,factory:@escaping()throws->RemoteFileClient){requestedLocal=local;requestedRemote=remote;self.options=options;self.policy=policy;self.selected=selected;self.copyPermissions=copyPermissions;self.useEvents=useEvents;self.factory=factory}
 private func change(_ state:State){lock.lock();value=state;lock.unlock();DispatchQueue.main.async{[weak self] in self?.onState?(state)}}
 private func log(_ text:String){DispatchQueue.main.async{[weak self] in self?.onLog?(text)}}
 private func checkpoint()throws{if stopped{throw ContinuousIssue.stopped}}
 private func setClient(_ c:RemoteFileClient?){lock.lock();client=c;let stop=stopWanted;lock.unlock();if stop{c?.interrupt()}}
 func start(){queue.async{[weak self] in guard let self=self,!self.started else{return};self.started=true;self.prepare()}}
 private func prepare(){do{
  _ = try options.validated();_ = try policy.validated();try checkpoint()
  let resource=FileManager.default.temporaryDirectory.appendingPathComponent("macscp-monitor-"+UUID().uuidString);try FileManager.default.createDirectory(at:resource,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700]);resources=URL(fileURLWithPath:try LocalTrashPlan.canonicalDirectory(resource.path));resourceIdentity=try LocalTrashSignature.read(resources!.path)
  let c=try factory();setClient(c);defer{setClient(nil);c.close()};c.checkpoint={try self.checkpoint()}
  let root=try ContinuousRootGuard(local:requestedLocal,remote:requestedRemote,client:c),scope=try ContinuousScope(options:options,policy:policy,selected:selected,ignoredRoot:resources!.path);roots=root;self.scope=scope
  if useEvents{events=try ContinuousEvents(root:root.local,queue:queue){[weak self] path,flags in self?.event(path,flags:flags)}}
  let local=try ContinuousScanner.local(root,scope:scope,checkpoint:{try self.checkpoint()}),remote=try ContinuousScanner.remote(root,scope:scope,client:c)
  previous=local;pending=local;pendingSince=Date();remoteAccepted=remote;initialPending=options.initialSync
  let initial=options.initialSync && options.cleanup ? SyncComparison.candidates(local:local.nodes,remote:remote.mapValues{$0.node},direction:.upload,deleteExtraneous:true,allows:{scope.allows($0,$1)}).filter{$0.deletion}.map{$0.relative} : []
  try checkpoint();let info=ContinuousBootstrap(local:root.local,remote:root.remote,directories:local.signatures.values.filter{$0.type==FileAttributeType.typeDirectory.rawValue}.count+1,initialCleanup:initial)
  if onReady != nil{DispatchQueue.main.async{[weak self] in guard let self=self,!self.stopped else{return};self.onReady?(info)}}else{approve()}
 }catch{finish(error)}}
 func approve(){queue.async{[weak self] in guard let self=self,!self.stopped,!self.approved else{return};self.approved=true;self.change(self.isPaused ? .paused : .watching);self.log("开始："+(self.roots?.local ?? "")+" → "+(self.roots?.remote ?? ""));let timer=DispatchSource.makeTimerSource(queue:self.queue);timer.schedule(deadline:.now()+self.options.interval,repeating:self.options.interval);timer.setEventHandler{[weak self] in self?.tick()};self.timer=timer;timer.resume()}}
 private var isPaused:Bool{lock.lock();defer{lock.unlock()};return pauseWanted}
 func pause(_ paused:Bool){lock.lock();pauseWanted=paused;lock.unlock();queue.async{[weak self] in guard let self=self,!self.stopped else{return};self.pendingSince=Date();if self.activeJob==nil{self.change(paused ? .paused : .watching)}}}
 func invalidate(_ reason:String){queue.async{[weak self] in self?.finish(SFTPError.message(reason))}}
 var monitoringPaused:Bool{isPaused}
 func stop(){lock.lock();guard !stopWanted else{lock.unlock();return};stopWanted=true;let c=client,j=job;lock.unlock();change(.stopping);c?.interrupt();j?.cancel();queue.async{[weak self] in guard let self=self else{return};self.timer?.cancel();self.timer=nil;self.events?.stop();self.events=nil;if self.activeJob==nil{self.finish(nil)}}}
 private func event(_ path:String,flags:UInt32){guard !stopped,let root=roots,let scope=scope else{return}
  if flags & UInt32(kFSEventStreamEventFlagRootChanged|kFSEventStreamEventFlagMustScanSubDirs|kFSEventStreamEventFlagUserDropped|kFSEventStreamEventFlagKernelDropped) != 0{finish(SFTPError.message("目录身份变化或事件丢失，请重新比较后开始"));return}
  guard flags & UInt32(kFSEventStreamEventFlagItemModified|kFSEventStreamEventFlagItemCreated|kFSEventStreamEventFlagItemRemoved|kFSEventStreamEventFlagItemRenamed) != 0 else{return}
  let prefix=root.local=="/" ? "/" : root.local+"/";guard path.hasPrefix(prefix),path != scope.ignoredRoot,!path.hasPrefix(scope.ignoredRoot+"/") else{return};let relative=String(path.dropFirst(prefix.count));guard !relative.isEmpty,scope.allows(relative,flags & UInt32(kFSEventStreamEventFlagItemIsDir) != 0) else{return}
  forced.insert(relative);eventVersion &+= 1;lastEvent=Date();if forced.count>10000{finish(SFTPError.message("待处理变化过多，请缩小范围后重新开始"))}
 }
 // Exposed for deterministic tests; normal operation also has a periodic local metadata reconciliation.
 func signalChange(_ path:String){queue.async{[weak self] in guard let self=self,let root=self.roots else{return};self.event(SyncDeletionPlan.join(root.local,path),flags:UInt32(kFSEventStreamEventFlagItemModified|kFSEventStreamEventFlagItemIsFile))}}
 private func tick(){guard approved,!stopped,!isPaused,activeJob==nil,let roots=roots,let scope=scope,let previous=previous else{return}
  do{let current=try ContinuousScanner.local(roots,scope:scope,checkpoint:{try self.checkpoint()});let now=Date()
   if pending != current{pending=current;pendingSince=now;return};pending=current
   guard now.timeIntervalSince(pendingSince)>=options.settle,now.timeIntervalSince(lastEvent)>=options.settle else{return}
   guard initialPending || current != previous || !forced.isEmpty else{return}
   let c=try factory();setClient(c);defer{setClient(nil);c.close()};c.checkpoint={try self.checkpoint()}
   let remote=try ContinuousScanner.remote(roots,scope:scope,client:c)
   let plan=try ContinuousPlan.prepare(roots:roots,scope:scope,local:current,previous:previous,remote:remote,accepted:remoteAccepted,forced:forced,initial:initialPending,eventVersion:eventVersion,copyPermissions:copyPermissions,client:c)
   if plan.actions.isEmpty{self.previous=current;initialPending=false;forced=[];change(.watching);return}
   try checkpoint();let outcome=ContinuousOutcome(),job=TransferJob(up:true,source:roots.local,destination:roots.remote,directory:true,size:plan.bytes)
   job.policy=policy;job.policyConfigured=true;job.customAction="持续更新";job.displaySource=roots.local+"（\(plan.actions.count) 项）";job.retryAllowed=false;job.retryNotice="持续更新任务由监控窗口管理，请核对日志后重新开始"
   job.beforeTransfer={client in try self.checkpoint();try roots.validate(client:client)}
   job.factory={try self.checkpoint();return try self.factory()}
   job.customOperation={[weak self,weak job] client,point in guard let self=self else{throw ContinuousIssue.stopped};self.setClient(client);defer{self.setClient(nil)};try self.checkResource();try plan.execute(client:client,resources:self.resources!,outcome:outcome,checkpoint:point);if outcome.skipped>0{job?.completionMessage="已完成（跳过 \(outcome.skipped) 项）"}}
   lock.lock();self.job=job;lock.unlock();change(.syncing)
   job.observeCompletion{[weak self,weak job] in guard let self=self,let job=job else{return};self.queue.async{self.completed(job,plan:plan,outcome:outcome)}}
   DispatchQueue.main.async{[weak self] in guard let self=self else{return};if self.stopped{job.cancel();return};if let submit=self.onJob{submit(job)}else{job.finishWithoutStarting("未连接传输队列",failed:true)}}
  }catch{finish(error)}
 }
 private func completed(_ job:TransferJob,plan:ContinuousPlan,outcome:ContinuousOutcome){
  for (path,node) in outcome.remoteChanges{remoteAccepted[path]=node};for path in outcome.removed{remoteAccepted.removeValue(forKey:path)}
  job.releaseCompletedCustomOperation()
  lock.lock();self.job=nil;lock.unlock();for message in outcome.messages{log(message)}
  if stopped || job.wasCancelled{finish(nil);return}
  if outcome.transient{log("文件继续变化，等待稳定后重新比较");pending=nil;pendingSince=Date();change(isPaused ? .paused : .watching);return}
  if job.failed || outcome.fatal{finish(SFTPError.message(job.column("progress")));return}
  previous=plan.local;initialPending=false;if plan.eventVersion==eventVersion{forced=[]};pendingSince=Date();log("本轮完成 \(outcome.completed) 项，跳过 \(outcome.skipped) 项");change(isPaused ? .paused : .watching)
 }
 private func checkResource()throws{guard let root=resources,let expected=resourceIdentity,try expected.sameDirectory(LocalTrashSignature.read(root.path)) else{throw SFTPError.message("监控暂存目录身份改变")}}
 private func finish(_ error:Error?){
  lock.lock();let hadStopped=stopWanted;stopWanted=true;let c=client,j=job;lock.unlock();c?.interrupt();j?.cancel();timer?.cancel();timer=nil;events?.stop();events=nil
  if let error=error,!hadStopped,pendingFailure==nil{pendingFailure=error.localizedDescription;log(error.localizedDescription)}
  if j != nil{change(.stopping);return}
  if let resources=resources{if (try? checkResource()) != nil{try? FileManager.default.removeItem(at:resources)};self.resources=nil}
  if let failure=pendingFailure{change(.failed(failure))}else{change(.stopped)}
 }
}
