import Cocoa
final class ConnectionStateClientGate {
 private let lock=NSLock();private let semaphore=DispatchSemaphore(value:0)
 private var armed=false,entered=false;private var clients=[Process]()
 var count:Int{lock.lock();defer{lock.unlock()};return clients.count}
 var blocked:Bool{lock.lock();defer{lock.unlock()};return entered}
 var lastStopped:Bool{lock.lock();let process=clients.last;lock.unlock();return process.map{!$0.isRunning} ?? false}
 func arm(){lock.lock();armed=true;entered=false;lock.unlock()}
 func release(){semaphore.signal()}
 func make()throws->SFTPClient {
  lock.lock();let block=armed;armed=false;if block{entered=true};lock.unlock()
  if block{precondition(semaphore.wait(timeout:.now()+5) == .success)}
  let client=try SFTPClient(command:"/usr/libexec/sftp-server",arguments:[])
  lock.lock();clients.append(client.process);lock.unlock();return client
 }
}
@main struct NativeConnectionStateTests {
 static func wait(_ condition:()->Bool){let end=Date().addingTimeInterval(6);while !condition() && Date()<end{RunLoop.current.run(until:Date().addingTimeInterval(0.01))};precondition(condition(),"connection presentation timeout")}
 static func main()throws {
  NSApplication.shared.setActivationPolicy(.prohibited)
  let fm=FileManager.default,root=fm.temporaryDirectory.appendingPathComponent("native-connection-state-"+UUID().uuidString)
  try fm.createDirectory(at:root.appendingPathComponent("remote/next"),withIntermediateDirectories:true)
  try fm.createDirectory(at:root.appendingPathComponent("local"),withIntermediateDirectories:true)
  try Data("fixture".utf8).write(to:root.appendingPathComponent("remote/visible.txt"))
  try Data("stale".utf8).write(to:root.appendingPathComponent("remote/next/stale.txt"))
  let suite="macscp-connection-state-"+UUID().uuidString
  let isolated=UserDefaults(suiteName:suite)!
  defer{try? fm.removeItem(at:root);isolated.removePersistentDomain(forName:suite)}
  let gate=ConnectionStateClientGate()
  let app=App(defaults:isolated,dataDirectory:root.appendingPathComponent("profile"),initialLocalDirectory:root.appendingPathComponent("local").path,automaticLogin:false,showsMainWindow:false,transferOptionsEnabled:false,frameAutosaveName:nil,clientProvider:{_,_ in try gate.make()})
  app.applicationDidFinishLaunching(Notification(name:NSApplication.didFinishLaunchingNotification))
  let progress=SSHConnection(arguments:["60"],helper:"/unused",executable:"/unused",command:"/bin/sleep")
  defer{progress.stop()}
  let auth=NSWindow(contentRect:NSRect(x:0,y:0,width:200,height:100),styleMask:[.titled],backing:.buffered,defer:false);auth.isReleasedWhenClosed=false
  let site=Session(name:"connection state fixture",host:"state-fixture.invalid",user:"fixture",port:22,key:"")
  let tab=ConnectionTab(site,"fixture-state-socket",progress,auth,root.appendingPathComponent("local").path,defaults:isolated)
  app.connections=[tab];app.selectedTab=0;app.session=site;app.socket=tab.socket;app.auth=auth;app.terminal=progress
  tab.remotePath=root.appendingPathComponent("remote").path;app.remote.path.stringValue=tab.remotePath
  app.rebuildTabs()
  precondition(app.remote.path.stringValue==tab.remotePath)
  app.stashTab();precondition(tab.remotePath==root.appendingPathComponent("remote").path && app.siteStore?.sites.first?.remotePath==tab.remotePath)
  precondition(app.remoteToolbarControls.allSatisfy{!$0.isEnabled})
  precondition(app.remote.connectionState == .connecting && app.remote.loginPrompt?.isHidden == false)
  precondition(!app.remote.path.isEnabled && !app.remote.table.isEnabled && app.local.transferControl?.isEnabled == false)
  precondition(app.remote.connectionButton.identifier?.rawValue=="connectionProgress")
  app.remote.entries=[Entry(name:"cached.txt",size:1,dir:false)];app.remote.reload()
  app.remote.table.selectRowIndexes(IndexSet(integer:0),byExtendingSelection:false)
  app.remote.menuNeedsUpdate(app.remote.table.menu!)
  precondition(app.remote.table.menu!.items.allSatisfy{!$0.isEnabled})
  precondition(app.remote.tableView(app.remote.table,pasteboardWriterForRow:0)==nil)
  app.paneCommand(false,"rename");app.enqueue(true);app.loadRemote();app.findFiles();app.synchronize();app.openRemoteTerminal()
  precondition(!app.handleDrop([DragFile(path:root.appendingPathComponent("local/no-file").path,directory:false,size:0,connection:nil)],toRemote:true))
  precondition(gate.count==0 && app.jobs.isEmpty && app.editors.isEmpty && app.searchers.isEmpty && app.syncPreviews.isEmpty && app.terminalWindows.isEmpty && !auth.isVisible && !app.window.isVisible)
  tab.connected=true;app.rebuildTabs()
  precondition(app.remote.connectionState == .connected && app.remote.loginPrompt?.isHidden == true)
  precondition(app.remote.path.isEnabled && app.remote.table.isEnabled && app.local.transferControl?.isEnabled == true)
  app.remote.togglePathEdit();app.remote.path.stringValue="/draft/not-committed";app.rebuildTabs();precondition(app.remote.isEditingPath && app.remote.path.stringValue=="/draft/not-committed");app.remote.togglePathEdit()
  app.remote.path.stringValue=root.appendingPathComponent("remote").path;app.loadRemote()
  wait{!app.browsing && app.remote.entries.contains{$0.name=="visible.txt"}}
  precondition(app.remoteToolbarControls.allSatisfy{$0.isEnabled})
  let before=app.remote.currentPath
  gate.arm();app.remote.path.stringValue=root.appendingPathComponent("remote/next").path;app.loadRemote();wait{gate.blocked}
  let generation=app.generation;progress.exitCode=255;app.connectionEnded(tab)
  precondition(app.generation==generation+1 && !app.browsing && app.pendingRemoteNavigation==nil && !tab.connected)
  precondition(app.remoteToolbarControls.allSatisfy{!$0.isEnabled} && !app.remoteConnectionReady && app.remote.connectionButton.identifier?.rawValue=="reconnect")
  gate.release();wait{gate.count==2 && gate.lastStopped}
  var mainQueueDrained=false;DispatchQueue.main.async{mainQueueDrained=true};wait{mainQueueDrained}
  precondition(app.remote.currentPath==before && !app.remote.entries.contains{$0.name=="stale.txt"})
  precondition(!app.status.stringValue.hasPrefix("已连接") && !app.remote.table.isEnabled)
  let button=app.tabBar.arrangedSubviews.first as! NSButton
  precondition(button.title.hasPrefix("⚠ ") && button.toolTip!.contains("已断开"))
  if let signal=progress.authenticationCancellation{_ = fm.createFile(atPath:signal.path,contents:Data())}
  app.refreshConnectionPresentation()
  precondition(app.remote.connectionState == .cancelled && app.remote.connectionHeading.stringValue=="连接已取消")
  for state:RemotePaneConnectionState in [.disconnected,.connecting,.cancelled,.failed(String(repeating:"连接错误 ",count:50))] {
   app.remote.setConnectionState(state)
   var requested="";app.remote.command={requested=$0};app.remote.tool(app.remote.connectionButton)
   precondition(requested==state.command)
   app.window.setContentSize(NSSize(width:900,height:700));app.window.contentView!.layoutSubtreeIfNeeded()
   precondition(app.window.contentView!.frame.width<=901 && app.remote.frame.width>=400)
  }
  app.remote.command=nil
  let otherProgress=SSHConnection(arguments:["60"],helper:"/unused",executable:"/unused",command:"/bin/sleep");defer{otherProgress.stop()}
  let other=ConnectionTab(site,"other-fixture-socket",otherProgress,auth,root.appendingPathComponent("local").path,defaults:isolated);other.connected=true;other.remotePath=before
  app.connections.append(other);app.activateTab(1)
  precondition(app.remoteConnectionReady && app.remote.connectionState == .connected)
  let count=app.jobs.count
  precondition(!app.handleDrop([DragFile(path:root.appendingPathComponent("remote/visible.txt").path,directory:false,size:7,connection:tab.socket)],toRemote:true))
  precondition(app.jobs.count==count)
  app.activateTab(0)
  precondition(!app.remoteConnectionReady && app.remote.connectionState == .cancelled && !auth.isVisible && !app.window.isVisible)
  app.window.close();auth.close()
  print("PASS: hidden full App distinguishes connecting/connected/cancelled/failed states; blocks offline menus, drag, upload and directory reads; late SFTP result cannot overwrite disconnection; selected tab state and upload availability follow session; failed-tab activation opens no authentication window; narrow overlay layout fits; no network or visible prompt")
 }
}
