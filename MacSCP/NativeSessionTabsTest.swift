import Cocoa
@main struct NativeSessionTabsTests {
 static func main()throws{
  NSApplication.shared.setActivationPolicy(.prohibited)
  let fm=FileManager.default,root=fm.temporaryDirectory.appendingPathComponent("macscp-tab-test-"+UUID().uuidString),suite="macscp-tabs-"+UUID().uuidString
  try fm.createDirectory(at:root,withIntermediateDirectories:true);let defaults=UserDefaults(suiteName:suite)!
  defer{try? fm.removeItem(at:root);defaults.removePersistentDomain(forName:suite)}
  var clients=0
  let app=App(defaults:defaults,dataDirectory:root.appendingPathComponent("profile"),initialLocalDirectory:root.path,automaticLogin:false,showsMainWindow:false,frameAutosaveName:nil,clientProvider:{_,_ in clients+=1;throw SFTPError.message("unexpected network")})
  app.applicationDidFinishLaunching(Notification(name:NSApplication.didFinishLaunchingNotification))
  var tabs=[ConnectionTab]()
  for i in 0..<3 {
   let ssh=SSHConnection(arguments:["60"],helper:"/unused",executable:"/unused",command:"/bin/sleep")
   let auth=NSWindow(contentRect:NSRect(x:0,y:0,width:100,height:100),styleMask:[.titled],backing:.buffered,defer:false);auth.isReleasedWhenClosed=false
   let site=Session(name:"特别长的测试站点名称-\(i)",host:"host\(i).invalid",user:"fixture",port:22,key:"")
   let tab=ConnectionTab(site,root.appendingPathComponent("absent-socket-\(i)").path,ssh,auth,root.path,defaults:defaults);tab.remotePath="/fixture-\(i)";tabs.append(tab)
  }
  defer{for tab in tabs{tab.terminal?.stop();tab.auth?.close()};app.window.close()}
  app.connections=tabs;app.activateTab(1)
  let generation=app.generation
  precondition(app.currentConnection === tabs[1])
  let buttons=app.tabBar.arrangedSubviews.compactMap{$0 as? SessionTabButton};precondition(buttons.count==3)
  app.window.contentView!.layoutSubtreeIfNeeded()
  precondition(buttons.allSatisfy{$0.closeButton.superview === $0 && $0.closeButton.frame.width==20 && $0.close != nil && $0.contextMenu != nil})
  let pending=TransferJob(up:true,source:"/fixture",destination:"/fixture",directory:false,size:1);app.jobs=[pending]
  precondition(!app.closeConnection(tabs[0]) && app.connections.count==3 && app.generation==generation)
  precondition(!app.sessionTabMenu(tabs[0]).items.last!.isEnabled)
  app.jobs=[]
  precondition(app.closeConnection(tabs[0]) && app.currentConnection === tabs[1] && app.selectedTab==0 && app.generation==generation)
  precondition(!app.closeConnection(tabs[0]))
  let oldMenu=app.sessionTabMenu(tabs[1]);precondition(oldMenu.items.last!.isEnabled)
  precondition(app.closeConnection(tabs[1]) && app.currentConnection === tabs[2] && app.selectedTab==0 && app.generation>generation)
  app.sessionTabAction(oldMenu.items.first!) // Stale menu must not switch to a different session after indexes shift.
  precondition(app.currentConnection === tabs[2])
  let last=app.tabBar.arrangedSubviews.first as! SessionTabButton;last.closeButton.performClick(nil)
  precondition(app.connections.isEmpty && app.currentConnection==nil && app.selectedTab==nil && app.session==nil && app.socket.isEmpty && !app.remoteConnectionReady)
  precondition(app.remote.currentPath.isEmpty && app.remote.entries.isEmpty && !app.remote.table.isEnabled && clients==0 && !app.window.isVisible && tabs.allSatisfy{$0.auth?.isVisible != true})
  print("PASS: session close buttons/context menus, unfinished queue protection, inactive close preserves active generation and shifted selection, active close selects neighbor, stale menu identity, final session cleanup; no network/password/window")
 }
}
