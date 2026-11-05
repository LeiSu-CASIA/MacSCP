import Cocoa
@main struct NativeTransferConflictTests {
 static func main()throws{
  NSApplication.shared.setActivationPolicy(.prohibited)
  let fm=FileManager.default,root=fm.temporaryDirectory.appendingPathComponent("macscp-conflict-"+UUID().uuidString),suite="macscp-conflict-"+UUID().uuidString
  try fm.createDirectory(at:root,withIntermediateDirectories:true);let defaults=UserDefaults(suiteName:suite)!
  defer{try? fm.removeItem(at:root);defaults.removePersistentDomain(forName:suite)}
  let app=App(defaults:defaults,dataDirectory:root.appendingPathComponent("profile"),initialLocalDirectory:root.path,automaticLogin:false,showsMainWindow:false,transferOptionsEnabled:false,frameAutosaveName:nil,clientProvider:{_,_ in fatalError("unexpected connection")})
  app.applicationDidFinishLaunching(Notification(name:NSApplication.didFinishLaunchingNotification));app.transfers.isSuspended=true
  let ssh=SSHConnection(arguments:["60"],helper:"/unused",executable:"/unused",command:"/bin/sleep")
  let auth=NSWindow(contentRect:NSRect(x:0,y:0,width:100,height:100),styleMask:[.titled],backing:.buffered,defer:false);auth.isReleasedWhenClosed=false
  defer{for job in app.jobs{job.cancel()};app.transfers.cancelAllOperations();ssh.stop();auth.close();app.window.close()}
  let site=Session(name:"fixture",host:"fixture.invalid",user:"fixture",port:22,key:"")
  let tab=ConnectionTab(site,root.appendingPathComponent("absent-socket").path,ssh,auth,root.path,defaults:defaults);tab.connected=true
  app.connections=[tab];app.selectedTab=0;app.session=site;app.socket=tab.socket
  app.local.acceptPath(root.path);app.remote.acceptPath("/fixture-remote")
  let names=["a.txt","b.txt","c.txt"]
  func populate(){app.local.entries=names.map{Entry(name:$0,size:1,dir:false)};app.local.reload();app.local.table.selectAll(nil);app.remote.entries=app.local.entries;app.remote.reload();app.refreshConnectionPresentation()}
  func clear(){for job in app.jobs{job.cancel()};app.transfers.cancelAllOperations();app.jobs=[]}
  var prompts=0
  populate();app.transferConflictPrompt={_ in prompts+=1;return .init(action:.replace,applyToRemainingConflicts:true)};app.enqueue(true)
  precondition(prompts==1 && app.jobs.count==3 && app.jobs.allSatisfy{$0.overwrite && $0.recoveryRecord()?.overwrite==true})
  clear();populate();app.enqueue(true);precondition(prompts==2 && app.jobs.count==3) // Fresh gesture asks again.
  clear();populate();prompts=0;app.transferConflictPrompt={_ in prompts+=1;return .init(action:.skip,applyToRemainingConflicts:true)};app.enqueue(true)
  precondition(prompts==1 && app.jobs.isEmpty)
  // Apply-to-all skips only conflicts, not genuinely new destinations.
  app.remote.entries=[Entry(name:"a.txt",size:1,dir:false)];app.remote.reload();app.enqueue(true)
  precondition(prompts==2 && app.jobs.count==2 && app.jobs.allSatisfy{!$0.overwrite})
  clear();populate();prompts=0;app.transferConflictPrompt={_ in prompts+=1;return .init(action:prompts==1 ? .replace : .cancelRemaining)};app.enqueue(true)
  precondition(prompts==2 && app.jobs.count==1 && app.status.stringValue.contains("剩余任务"))
  clear();populate();prompts=0;app.transferConflictPrompt={_ in prompts+=1;return .init(action:.skip,applyToRemainingConflicts:true)}
  let files=names.map{DragFile(path:root.appendingPathComponent($0).path,directory:false,size:1,connection:nil)}
  precondition(!app.handleDrop(files,toRemote:true) && prompts==1 && app.jobs.isEmpty)
  app.transferConflictPrompt={_ in prompts+=1;return .init(action:.replace,applyToRemainingConflicts:true)}
  precondition(app.handleDrop(files,toRemote:true) && app.jobs.count==3 && prompts==2)
  clear()
  // Downloads and server-to-local drag share the same gesture scope.
  for name in names{try Data("old".utf8).write(to:root.appendingPathComponent(name))}
  populate();app.remote.table.selectAll(nil);prompts=0;app.enqueue(false)
  precondition(prompts==1 && app.jobs.count==3 && app.jobs.allSatisfy{!$0.up && $0.overwrite});clear()
  let remoteFiles=names.map{DragFile(path:"/fixture-remote/"+$0,directory:false,size:1,connection:tab.socket)}
  prompts=0;precondition(app.handleDrop(remoteFiles,toRemote:false) && prompts==1 && app.jobs.count==3);clear()
  // A connection that ends while confirmation is open must not receive newly queued work.
  populate();prompts=0;app.transferConflictPrompt={_ in prompts+=1;tab.connected=false;return .init(action:.replace)};app.enqueue(true)
  precondition(app.jobs.isEmpty && prompts==1);tab.connected=true;app.refreshConnectionPresentation()
  // Broken local symlinks still need confirmation, and directories do not inherit file overwrite approval.
  let dangling=root.appendingPathComponent("dangling");try fm.createSymbolicLink(atPath:dangling.path,withDestinationPath:root.appendingPathComponent("missing").path)
  let link=TransferJob(up:false,source:"/fixture",destination:dangling.path,directory:false,size:1);prompts=0
  app.transferConflictPrompt={_ in prompts+=1;return .init(action:.replace,applyToRemainingConflicts:true)}
  let batch=TransferApprovalBatch();precondition(app.approveTransfer(link,batch:batch,remoteNames:[]) && prompts==1)
  let folder=TransferJob(up:false,source:"/fixture",destination:root.path,directory:true,size:0)
  precondition(app.approveTransfer(folder,batch:batch,remoteNames:[]) && prompts==2)
  let dialog=TransferConflictDialog(folder);dialog.alert.window.contentView!.layoutSubtreeIfNeeded()
  precondition(dialog.alert.accessoryView!.frame.height>50 && !dialog.alert.window.isVisible && dialog.applyAll.title.contains("目录"))
  dialog.applyAll.state = .on;precondition(dialog.response(.alertSecondButtonReturn).action == .replace && dialog.response(.alertSecondButtonReturn).applyToRemainingConflicts)
  precondition(dialog.response(.alertThirdButtonReturn).action == .cancelRemaining && dialog.alert.buttons[2].keyEquivalent=="\u{1b}")
  let cancelled=TransferApprovalBatch();precondition(!cancelled.approve(link,exists:true){.init(action:.cancelRemaining)})
  precondition(!cancelled.approve(folder,exists:false){fatalError("must not prompt after cancellation")})
  precondition(!app.window.isVisible && !auth.isVisible)
  print("PASS: real upload/drop batch integration, replace/skip all conflicts per gesture and file/dir kind, new targets preserved, cancel remaining retains prior queued items, broken local link confirmation, recovery overwrite flags, hidden dialog paths/keyboard/layout; no connection/password/window")
 }
}
