import Cocoa
extension App {
 func copyFiles(_ isLocal:Bool){let pane=isLocal ? local : remote
  guard pane.fileOperationsAvailable,isLocal || remoteConnectionReady else{status.stringValue="请先连接来源服务器";return}
  do{let files=pane.selected.filter{$0.name != "." && $0.name != ".."}.map{DragFile(path:join(pane.currentPath,$0.name),directory:$0.dir,size:$0.size,connection:isLocal ? nil : socket)};guard !files.isEmpty else{return};try fileClipboard.write(FileClipboardEnvelope.encode(owner:clipboardOwner,files:files));status.stringValue="已复制 \(files.count) 项；在目标文件列表粘贴"}catch{status.stringValue=error.localizedDescription}
 }
 func copyFilePaths(_ isLocal:Bool){let pane=isLocal ? local : remote,paths=pane.selected.filter{$0.name != "." && $0.name != ".."}.map{join(pane.currentPath,$0.name)};guard pane.fileOperationsAvailable,!paths.isEmpty else{return};do{try fileClipboard.write(FileClipboardSnapshot(text:paths.joined(separator:"\n")));status.stringValue="已复制完整路径"}catch{status.stringValue=error.localizedDescription}}
 func pasteFiles(_ isLocal:Bool){let pane=isLocal ? local : remote
  guard pane.fileOperationsAvailable,isLocal || remoteConnectionReady else{status.stringValue="请先连接目标服务器";return}
  do{let snapshot=try fileClipboard.read()
   guard let files=try FileClipboardEnvelope.files(snapshot,owner:clipboardOwner) else{if let path=try FileClipboardEnvelope.directoryText(snapshot.text){pane.path.stringValue=path;if isLocal{loadLocal()}else{loadRemote()}}else{status.stringValue="剪贴板中没有可粘贴的文件或绝对目录路径"};return}
   if !isLocal{guard remoteWriteAvailable else{status.stringValue="目标服务器不可写；FTP 写入需明确开启";return}}
   // Validate the complete batch before displaying any conflict dialog or enqueuing a task.
   for file in files{if let origin=file.connection{guard connections.contains(where:{$0.socket==origin && $0.presentation.available}) else{throw SFTPError.message("来源服务器会话已关闭或断开，请重新登录后复制")};if !isLocal,!transferOptionsEnabled,origin==socket,file.directory,remote.currentPath==file.path || remote.currentPath.hasPrefix(file.path+"/"){throw SFTPError.message("不能把目录复制到自身或其子目录")}}else{let reader=LocalReadClient();defer{reader.close()};guard let info=try reader.attributes(file.path),info.mode&0o170000==0o100000 || info.mode&0o170000==0o040000 else{throw SFTPError.message("本地来源已移除、是链接或不是普通文件／目录")};if isLocal && !transferOptionsEnabled{let source=try reader.canonical(file.path),target=try reader.canonical(local.currentPath),destination=(target as NSString).appendingPathComponent((file.path as NSString).lastPathComponent);guard source != destination,!(info.mode&0o170000==0o040000 && (target==source || target.hasPrefix(source+"/"))) else{throw SFTPError.message("不能把项目复制到自身或目录的子目录")}}}}
   _ = requestTransfer(files,toRemote:!isLocal,origin:.paste)
  }catch{status.stringValue=error.localizedDescription}
 }
 func enqueueLocalCopies(_ files:[DragFile],directory:String?=nil,preferences:TransferPreferences?=nil,speedLimit:UInt64?=nil,batch:TransferApprovalBatch=TransferApprovalBatch()){let root=directory ?? local.currentPath,viewRoot=local.currentPath;var count=0
  for file in files{if batch.cancelled{break};guard local.currentPath==viewRoot else{status.stringValue="本地目标目录已变化，未加入剩余任务";break}
   let job=TransferJob(up:false,source:file.path,destination:join(root,(file.path as NSString).lastPathComponent),directory:file.directory,size:file.size)
   job.customAction="本地复制";job.endpointDescription="本机 → 本机";job.policy=TransferPolicy(verifyChecksum:(preferences ?? effectiveTransferPreferences).filePolicy.verifyChecksum);job.policyConfigured=true;job.overrideSpeedLimit=speedLimit;job.factory={LocalReadClient()}
   if approveTransfer(job,batch:batch,remoteNames:[]),local.currentPath==viewRoot{jobs.append(job);schedule(job);count+=1}
  };reloadQueue();status.stringValue=batch.cancelled ? "已取消剩余本地复制；此前加入的任务继续执行" : "已加入 \(count) 项本地复制任务"
 }
}
