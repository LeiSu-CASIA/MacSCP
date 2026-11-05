import Cocoa

enum TransferInitiation {case command,drag,paste;var isDrag:Bool{self == .drag}}
private struct TransferRequestScope {
 let files:[DragFile],toRemote:Bool,local:String,remote:String,socket:String,generation:Int
 let target:ConnectionTab?,targetPath:String
 var requiresRemote:Bool{toRemote || files.contains{$0.connection != nil}}
}
extension App {
 func writableTransferTarget(_ tab:ConnectionTab?)->Bool{guard let tab=tab,connections.contains(where:{$0 === tab}),tab.presentation.available else{return false};return tab.session.fileProtocol == .sftp || tab.session.ftpSettings.allowNonAtomicWrites}
 func directoryForTransferTarget(_ tab:ConnectionTab)->String{currentConnection === tab ? remote.currentPath : tab.remotePath}
 private func preferencesForTransferTarget(_ tab:ConnectionTab?,directory:String)->TransferPreferences{
  guard let tab=tab,currentConnection !== tab else{return effectiveTransferPreferences}
  if transferPresetReadError==nil,let preset=try? transferPresets.automaticPreset(TransferPresetContext(connection:tab.socket,host:tab.session.host,user:tab.session.user,local:local.currentPath,remote:directory)){return preset.preferences}
  return preferences
 }
 @discardableResult func requestTransfer(_ files:[DragFile],toRemote:Bool,origin:TransferInitiation,directory:String?=nil,targetTab:ConnectionTab?=nil)->Bool{
  guard !files.isEmpty else{return false}
  guard transferConfirmation==nil else{status.stringValue="请先确认或取消当前传输窗口";return false}
  let target=toRemote ? (targetTab ?? currentConnection) : nil
  guard !toRemote || writableTransferTarget(target) else{status.stringValue="请先连接可写的目标服务器";return false}
  let enabled=origin.isDrag ? dragTransferOptionsEnabled : transferOptionsEnabled
  if !enabled,directory==nil,targetTab==nil{return performDrop(files,toRemote:toRemote)}
  do{let files=try FileReferenceValidation.validated(files),targetPath=target.map{directoryForTransferTarget($0)} ?? "",root=try TransferBatchOptions.directory(directory ?? (toRemote ? targetPath : local.currentPath))
   let scope=TransferRequestScope(files:files,toRemote:toRemote,local:local.currentPath,remote:remote.currentPath,socket:socket,generation:generation,target:target,targetPath:targetPath),base=preferencesForTransferTarget(target,directory:root)
   let independentSpeed=toRemote && target !== currentConnection ? base.bytesPerSecond : nil
   if !enabled{return submitDirectedDrop(scope,directory:root,preferences:base,speedLimit:independentSpeed)}
   let controller=TransferOptionsController(files:files,directory:root,toRemote:toRemote,endpoint:toRemote ? (target?.session.identity ?? "服务器未连接") : "本机",preferences:base,presets:transferPresets.presets,sourceLabels:connections.reduce(into:[String:String]()){$0[$1.socket]=$1.session.identity})
   if independentSpeed != nil{controller.independent.state = .on;controller.changeIndependent()}
   if origin.isDrag{controller.suppress.title="以后拖放直接使用当前目录与设置，不再显示确认窗口"}
   controller.onClosed={[weak self,weak controller] in if self?.transferConfirmation === controller{self?.transferConfirmation=nil}}
   controller.onConfirm={[weak self,weak controller] options in guard let self=self,let controller=controller,!controller.closed else{return}
    guard self.transferScopeValid(scope) else{controller.showError("会话、目录或来源已变化，请取消后重新发起传输");return}
    let finish:(String,Set<String>?)->Void={[weak self,weak controller] directory,names in guard let self=self,let controller=controller,!controller.closed else{return};guard self.transferScopeValid(scope) else{controller.showError("目标核对期间会话或目录发生变化，请重新发起");return}
     do{try self.checkTransferTargets(scope.files,directory:directory,toRemote:toRemote,target:scope.target);controller.close();if options.suppress{self.setTransferConfirmation(false,drag:origin.isDrag)};_ = self.performDrop(scope.files,toRemote:toRemote,directory:directory,preferences:options.preferences,speedLimit:options.speedLimit,remoteNames:names,targetTab:scope.target)}catch{controller.showError(error.localizedDescription)}
    }
    if !toRemote{do{finish(try self.localTransferDirectory(options.directory),nil)}catch{controller.showError(error.localizedDescription)};return}
    if scope.target === self.currentConnection,options.directory==scope.remote{finish(options.directory,Set(self.remote.allEntries.map{$0.name}));return}
    guard let target=scope.target else{controller.showError("目标会话已关闭");return};let probe=TransferDestinationProbe();controller.cancelValidation={probe.cancel()};controller.setBusy(true)
    DispatchQueue.global().async{do{let result=try probe.read(options.directory,factory:{try self.client(target.session,target.socket)});DispatchQueue.main.async{finish(result.0,result.1)}}catch{DispatchQueue.main.async{if !controller.closed{controller.showError(error.localizedDescription)}}}}
   }
   let before=jobs.count;transferConfirmation=controller
   if let presenter=transferOptionsPresenter{presenter(controller)}else if showsMainWindow,let panel=controller.window{window.beginSheet(panel)}
   return !controller.closed || jobs.count>before
  }catch{status.stringValue=error.localizedDescription;return false}
 }
 private func localTransferDirectory(_ path:String)throws->String{let client=LocalReadClient();defer{client.close()};let directory=try client.canonical(path);guard let attrs=try client.attributes(directory),attrs.mode&0o170000==0o040000 else{throw SFTPError.message("目标不是已存在的本地目录")};return directory}
 private func submitDirectedDrop(_ scope:TransferRequestScope,directory:String,preferences:TransferPreferences,speedLimit:UInt64?)->Bool{
  guard transferScopeValid(scope) else{status.stringValue="拖放来源或目标已变化";return false}
  if !scope.toRemote{do{let root=try localTransferDirectory(directory);try checkTransferTargets(scope.files,directory:root,toRemote:false,target:nil);return performDrop(scope.files,toRemote:false,directory:root,preferences:preferences,speedLimit:speedLimit)}catch{status.stringValue=error.localizedDescription;return false}}
  guard let target=scope.target else{return false}
  guard pendingDropProbes.count<8 else{status.stringValue="等待核对的拖放过多，请稍后重试或按Esc取消";return false}
  let id=UUID(),probe=TransferDestinationProbe();pendingDropProbes[id]=probe;status.stringValue="正在核对拖放目标 · Esc 或队列菜单可取消"
  DispatchQueue.global().async{let result=Result{try probe.read(directory,factory:{try self.client(target.session,target.socket)})};DispatchQueue.main.async{
   guard self.pendingDropProbes.removeValue(forKey:id) != nil else{return}
   guard self.transferScopeValid(scope) else{self.status.stringValue="拖放核对期间会话或目录变化，未加入任务";return}
   do{let result=try result.get();try self.checkTransferTargets(scope.files,directory:result.0,toRemote:true,target:target);_ = self.performDrop(scope.files,toRemote:true,directory:result.0,preferences:preferences,speedLimit:speedLimit,remoteNames:result.1,targetTab:target)}catch{self.status.stringValue=error.localizedDescription}
  }};return true
 }
 func cancelPendingDrops(){let probes=Array(pendingDropProbes.values);pendingDropProbes.removeAll();for probe in probes{probe.cancel()};if !probes.isEmpty{status.stringValue="已取消尚未加入队列的拖放目标核对"}}
 private func transferScopeValid(_ scope:TransferRequestScope)->Bool{
  guard local.currentPath==scope.local else{return false}
  if scope.requiresRemote{guard generation==scope.generation,socket==scope.socket,remote.currentPath==scope.remote else{return false}}
  if scope.toRemote{guard writableTransferTarget(scope.target),let target=scope.target,directoryForTransferTarget(target)==scope.targetPath else{return false}}
  return scope.files.allSatisfy{file in file.connection.map{token in connections.contains{$0.socket==token && $0.presentation.available}} ?? true}
 }
 private func checkTransferTargets(_ files:[DragFile],directory:String,toRemote:Bool,target:ConnectionTab?)throws{
  for file in files{
   if toRemote{if file.connection==target?.socket,file.directory,directory==file.path || directory.hasPrefix(file.path+"/"){throw SFTPError.message("不能把目录复制到自身或子目录")};continue}
   if file.connection==nil{let client=LocalReadClient();defer{client.close()};let source=try client.canonical(file.path),target=(directory as NSString).appendingPathComponent((file.path as NSString).lastPathComponent);guard source != target,!(file.directory && (directory==source || directory.hasPrefix(source+"/"))) else{throw SFTPError.message("不能把本地项目复制到自身或子目录")}}
  }
 }
}
