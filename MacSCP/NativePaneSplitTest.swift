import Cocoa
@main struct NativePaneSplitTests {
 static func check(_ value:Bool,file:StaticString = #file,line:UInt = #line){precondition(value,file:file,line:line)}
 static func views(_ root:NSView)->[NSView]{[root]+root.subviews.flatMap{views($0)}}
 static func main()throws{
  NSApplication.shared.setActivationPolicy(.prohibited)
  let root=FileManager.default.temporaryDirectory.appendingPathComponent("macscp-pane-split-"+UUID().uuidString),suite="macscp-pane-split-"+UUID().uuidString,defaults=UserDefaults(suiteName:suite)!
  try FileManager.default.createDirectory(at:root,withIntermediateDirectories:false);defer{try? FileManager.default.removeItem(at:root);defaults.removePersistentDomain(forName:suite)}
  let app=App(defaults:defaults,dataDirectory:root.appendingPathComponent("profile"),initialLocalDirectory:root.path,automaticLogin:false,showsMainWindow:false,transferOptionsEnabled:false,frameAutosaveName:nil,clientProvider:{_,_ in fatalError("unexpected network")})
  app.applicationDidFinishLaunching(Notification(name:NSApplication.didFinishLaunchingNotification));defer{app.window.close()}
  let content=app.window.contentView!,split=views(content).compactMap{$0 as? CommanderFileSplitView}.first!
  app.window.setContentSize(NSSize(width:1180,height:780));content.layoutSubtreeIfNeeded()
  check(abs(app.local.frame.width-app.remote.frame.width)<2 && split.dividerThickness==5)
  for position:CGFloat in [350,790]{
   split.setPosition(position,ofDividerAt:0);content.layoutSubtreeIfNeeded();check(abs(app.local.frame.width-position)<2 && abs(app.local.frame.width-app.remote.frame.width)>300)
   let ratio=split.ratio
   for width:CGFloat in [900,1440,1180]{app.window.setContentSize(NSSize(width:width,height:780));content.layoutSubtreeIfNeeded();let available=split.bounds.width-split.dividerThickness,expected=min(max(280,available*ratio),available-280)
    check(abs(app.local.frame.width-expected)<2 && app.local.frame.width>=279 && app.remote.frame.width>=279)
    check(content.frame.width<=width+1)
    for pane in [app.local,app.remote]{let bars=views(pane).compactMap{$0 as? QueueToolbar};check(bars.count>=2 && bars.allSatisfy{$0.frame.width<=pane.frame.width+1});check(pane.table.enclosingScrollView!.frame.width>150)}
   }
  }
  let drawn=NSRect(x:app.local.frame.maxX,y:0,width:5,height:split.bounds.height),hit=split.splitView(split,effectiveRect:drawn,forDrawnRect:drawn,ofDividerAt:0)
  check(hit.width>=13 && split.splitView(split,constrainMinCoordinate:0,ofSubviewAt:0)>=280 && split.splitView(split,constrainMaxCoordinate:2000,ofSubviewAt:0)<=split.bounds.width-285)
  check(!views(content).flatMap{$0.constraints}.contains{($0.firstItem as? NSView) === app.local && ($0.secondItem as? NSView) === app.remote && $0.firstAttribute == .width && $0.relation == .equal})
  check(!app.window.isVisible && app.connections.isEmpty)
  print("PASS: actual App independent 350/790 pane positions, 900/1440/1180 window resizes preserve ratio and minimums, no equal-width lock, 13-point native divider hit area and constraints, narrow pane toolbars scroll without expanding window; hidden isolated app, no user UI or network")
 }
}
