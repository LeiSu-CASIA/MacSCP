import Cocoa
@main struct NativeLayoutTests {
 static func main()throws{
  NSApplication.shared.setActivationPolicy(.prohibited)
  let fm=FileManager.default,root=fm.temporaryDirectory.appendingPathComponent("native-layout-"+UUID().uuidString)
  try fm.createDirectory(at:root,withIntermediateDirectories:true)
  let suite="macscp-layout-"+UUID().uuidString
  let defaults=UserDefaults(suiteName:suite)!
  defer{try? fm.removeItem(at:root);defaults.removePersistentDomain(forName:suite)}
  let app=App(defaults:defaults,dataDirectory:root.appendingPathComponent("profile"),initialLocalDirectory:root.path,automaticLogin:false,showsMainWindow:false,frameAutosaveName:nil)
  app.applicationDidFinishLaunching(Notification(name:NSApplication.didFinishLaunchingNotification))
  precondition(!app.window.isVisible && app.connections.isEmpty)
  precondition(app.store.deletingLastPathComponent()==root.appendingPathComponent("profile"))
  app.local.hiddenToggle.state = .off;app.local.applyFilter()
  precondition(defaults.object(forKey:"showHidden.本地文件") as? Bool == false)
  let longPath="/"+Array(repeating:"特别长的中文目录名称 空格 %20 #",count:14).joined(separator:"/")
  for width:CGFloat in [1180,900] {
   app.window.setContentSize(NSSize(width:width,height:700))
   for pane in [app.local,app.remote] {pane.setConnectionState(.connected);pane.acceptPath(longPath);pane.reload()}
   app.window.contentView!.layoutSubtreeIfNeeded()
   print("layout width",width,"actual",app.window.contentView!.frame.width,"panes",app.local.frame.width,app.remote.frame.width)
   precondition(app.window.contentView!.frame.width<=width+1,"Long path expands main window beyond requested width")
   for pane in [app.local,app.remote] {
    precondition(pane.frame.width>300 && pane.frame.width<width*0.65)
    precondition(pane.breadcrumbs.frame.width<=pane.frame.width && pane.breadcrumbs.frame.width>100)
    pane.togglePathEdit();pane.path.stringValue=longPath+"/draft";app.window.contentView!.layoutSubtreeIfNeeded()
    precondition(app.window.contentView!.frame.width<=width+1,"Path editor expands window")
    pane.togglePathEdit()
   }
  }
  app.window.close()
  print("PASS: isolated full App startup stays hidden, uses injected profile/preferences, and long breadcrumbs/path editors fit 1180/900 point windows with both panes accessible")
 }
}
