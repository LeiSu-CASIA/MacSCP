import Cocoa
final class HistoryReadGate {
 private let lock=NSLock();private var armed=false,inside=false;let release=DispatchSemaphore(value:0)
 func arm(){lock.lock();armed=true;inside=false;lock.unlock()}
 var entered:Bool{lock.lock();defer{lock.unlock()};return inside}
 func beforeClient(){lock.lock();let block=armed;armed=false;if block{inside=true};lock.unlock();if block{release.wait()}}
}
@main struct NativeDirectoryHistoryTests {
 static func wait(_ predicate:()->Bool){let end=Date().addingTimeInterval(10);while !predicate() && Date()<end{RunLoop.current.run(until:Date().addingTimeInterval(0.01))};precondition(predicate(),"history timeout")}
 static func main()throws{
  NSApplication.shared.setActivationPolicy(.prohibited)
  let fm=FileManager.default,root=fm.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("native-history-"+UUID().uuidString),suite="macscp-history-"+UUID().uuidString
  let local=(0..<4).map{root.appendingPathComponent("local-\($0)").path};var remote=(0..<4).map{root.appendingPathComponent("remote-\($0)").path}
  for path in local+remote{try fm.createDirectory(atPath:path,withIntermediateDirectories:true)}
  let setup=try SFTPClient(command:"/usr/libexec/sftp-server",arguments:[]);remote=try remote.map{try setup.canonical($0)};setup.close()
  let defaults=UserDefaults(suiteName:suite)!;defer{try? fm.removeItem(at:root);defaults.removePersistentDomain(forName:suite)}
  let gate=HistoryReadGate()
  let app=App(defaults:defaults,dataDirectory:root.appendingPathComponent("profile"),initialLocalDirectory:local[0],automaticLogin:false,showsMainWindow:false,frameAutosaveName:nil,clientProvider:{_,_ in gate.beforeClient();return try SFTPClient(command:"/usr/libexec/sftp-server",arguments:[])})
  app.applicationDidFinishLaunching(Notification(name:NSApplication.didFinishLaunchingNotification));defer{app.window.close()}
  for path in local[1...2]{app.local.path.stringValue=path;app.loadLocal()}
  precondition(app.localHistory==Array(local[0...1]) && app.local.historyControl!.isEnabled)
  app.paneCommand(true,"back");precondition(app.local.currentPath==local[1] && app.localNavigation.forward==[local[2]])
  app.paneCommand(true,"forward");precondition(app.local.currentPath==local[2] && app.localNavigation.forward.isEmpty)
  let menu=app.makeDirectoryHistoryMenu(true),oldLocal=menu.items.first{$0.representedObject != nil}!
  let two=menu.items.filter{$0.representedObject != nil}[1];app.jumpDirectoryHistory(two);precondition(app.local.currentPath==local[0] && app.localNavigation.forward==[local[2],local[1]])
  try fm.removeItem(atPath:local[1]);let before=app.localNavigation;app.paneCommand(true,"forward");precondition(app.localNavigation==before && app.local.currentPath==local[0] && app.local.path.stringValue==local[0] && app.status.stringValue.contains("历史目录"))
  try fm.createDirectory(atPath:local[1],withIntermediateDirectories:true);app.paneCommand(true,"forward");precondition(app.local.currentPath==local[1]);app.local.path.stringValue=local[3];app.loadLocal();precondition(app.localNavigation.forward.isEmpty)
  let ssh=SSHConnection(arguments:["60"],helper:"/unused",executable:"/unused",command:"/bin/sleep");defer{ssh.stop()}
  let auth=NSWindow(contentRect:NSRect(x:0,y:0,width:100,height:100),styleMask:[.titled],backing:.buffered,defer:false);auth.isReleasedWhenClosed=false;defer{auth.close()}
  let site=Session(name:"fixture A",host:"a.invalid",user:"fixture",port:22,key:""),otherSite=Session(name:"fixture B",host:"b.invalid",user:"fixture",port:22,key:"")
  let a=ConnectionTab(site,root.appendingPathComponent("absent-a").path,ssh,auth,local[3],defaults:defaults),b=ConnectionTab(otherSite,root.appendingPathComponent("absent-b").path,ssh,auth,local[0],defaults:defaults);a.connected=true;b.connected=true;a.remotePath=remote[0];a.history.lastRemote=remote[0];b.remotePath=remote[3]
  app.connections=[a,b];app.activateTab(0)
  for path in remote[1...2]{app.remote.path.stringValue=path;app.loadRemote();wait{!app.browsing}}
  precondition(app.remoteNavigation.current==remote[2] && app.remoteHistory==Array(remote[0...1]))
  gate.arm();let history=app.remoteNavigation;app.paneCommand(false,"back");wait{gate.entered};precondition(app.remoteNavigation==history && !app.remote.historyControl!.isEnabled)
  app.paneCommand(false,"back");precondition(app.pendingRemoteNavigation==nil);gate.release.signal();wait{!app.browsing};precondition(app.remote.currentPath==remote[1] && app.remoteNavigation.forward==[remote[2]])
  app.paneCommand(false,"forward");wait{!app.browsing};try fm.removeItem(atPath:remote[1]);let remoteBefore=app.remoteNavigation;app.paneCommand(false,"back");wait{!app.browsing};precondition(app.remoteNavigation==remoteBefore && app.remote.path.stringValue==remote[2]);try fm.createDirectory(atPath:remote[1],withIntermediateDirectories:true)
  app.paneCommand(false,"back");wait{!app.browsing};let oldRemote=app.makeDirectoryHistoryMenu(false).items.first{$0.representedObject != nil}!
  app.stashTab();app.activateTab(1);let otherHistory=app.remoteNavigation;precondition(otherHistory.current.isEmpty && otherHistory.back.isEmpty);app.jumpDirectoryHistory(oldRemote);app.jumpDirectoryHistory(oldLocal);precondition(app.remoteNavigation==otherHistory && app.remote.currentPath==remote[3] && app.local.currentPath==local[0])
  app.stashTab();app.activateTab(0);precondition(app.remote.currentPath==remote[1] && app.remoteNavigation.forward==[remote[2]])
  // Queueing a new user directory during a history read creates a new branch after success.
  app.paneCommand(false,"forward");wait{!app.browsing};gate.arm();app.paneCommand(false,"back");wait{gate.entered};app.remote.path.stringValue=remote[3];app.loadRemote();precondition(app.pendingRemoteNavigation?.target==remote[3]);gate.release.signal();wait{!app.browsing && app.remote.currentPath==remote[3]};precondition(app.remoteNavigation.forward.isEmpty && app.remoteHistory.last==remote[1])
  precondition(FileKeyAction.resolve(code:33,command:true,shift:false,option:false)=="back" && FileKeyAction.resolve(code:30,command:true,shift:false,option:false)=="forward" && !app.window.isVisible && !auth.isVisible)
  print("PASS: real local/SFTP back/forward and history-menu jumps, failed reads preserve stacks/current path, busy remote ignores repeated history actions, per-tab forward restoration, stale menu refusal, queued user branch after history read, hidden controls and shortcuts; fixture only")
 }
}
