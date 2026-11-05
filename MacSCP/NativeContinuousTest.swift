import Cocoa
@main struct NativeContinuousTests {
 static func check(_ value:Bool,file:StaticString = #file,line:UInt = #line){precondition(value,file:file,line:line)}
 static func wait(_ condition:()->Bool,seconds:Double=8){let end=Date().addingTimeInterval(seconds);while !condition(),Date()<end{RunLoop.current.run(until:Date().addingTimeInterval(0.02))};check(condition())}
 static func main()throws {
  NSApplication.shared.setActivationPolicy(.prohibited)
  let fm=FileManager.default,root=fm.temporaryDirectory.appendingPathComponent("native-continuous-"+UUID().uuidString),suite="continuous-ui-"+UUID().uuidString,defaults=UserDefaults(suiteName:suite)!
  let local=root.appendingPathComponent("local"),remote=root.appendingPathComponent("remote")
  for path in [local,remote]{try fm.createDirectory(at:path,withIntermediateDirectories:true)}
  defer{try? fm.removeItem(at:root);defaults.removePersistentDomain(forName:suite)}
  var calls=0
  let app=App(defaults:defaults,dataDirectory:root.appendingPathComponent("profile"),initialLocalDirectory:local.path,automaticLogin:false,showsMainWindow:false,frameAutosaveName:nil,clientProvider:{_,_ in calls+=1;return try SFTPClient(command:"/usr/libexec/sftp-server",arguments:[])})
  app.applicationDidFinishLaunching(Notification(name:NSApplication.didFinishLaunchingNotification));app.keepRemoteUpdated();check(app.continuousWindows.isEmpty && calls==0)
  let terminal=SSHConnection(arguments:["60"],helper:"/unused",executable:"/unused",command:"/bin/sleep");defer{terminal.stop()}
  let auth=NSWindow(contentRect:NSRect(x:0,y:0,width:100,height:100),styleMask:[.titled],backing:.buffered,defer:false);auth.isReleasedWhenClosed=false;defer{auth.close()}
  let site=Session(name:"本机测试站点",host:"fixture.invalid",user:"fixture",port:22,key:"")
  let socket=root.appendingPathComponent("owned-token").path;try Data().write(to:URL(fileURLWithPath:socket))
  let tab=ConnectionTab(site,socket,terminal,auth,local.path,defaults:defaults);tab.connected=true
  app.connections=[tab];app.selectedTab=0;app.session=site;app.socket=socket;app.remote.acceptPath(remote.path);app.rebuildTabs();app.keepRemoteUpdated()
  check(app.continuousWindows.count==1 && calls==0)
  let controller=app.continuousWindows[0];controller.usesNativeEvents=false
  check(controller.window?.isVisible==false && controller.cleanup.state == .off && !controller.preserve.isEnabled && controller.preserve.state == .on && !controller.selected.isEnabled)
  app.keepRemoteUpdated();check(app.continuousWindows.count==1)
  controller.interval.stringValue="invalid";controller.start();check(controller.engine==nil && calls==0)
  controller.interval.stringValue="0.5";controller.settle.stringValue="0.5";controller.initial.state = .off
  controller.transferPolicy=TransferPolicy(exclude:"*.tmp");check(controller.policyLabel.stringValue.contains("*.tmp"))
  controller.window!.contentView!.layoutSubtreeIfNeeded()
  for field in [controller.localField,controller.remoteField,controller.interval,controller.settle]{check(field.frame.width>40 && field.frame.height>15)}
  check(controller.logView.enclosingScrollView!.frame.height>=100 && controller.logView.frame.width>500 && controller.logView.frame.height>100)
  for width:CGFloat in [620,660]{controller.window!.setContentSize(NSSize(width:width,height:700));controller.window!.contentView!.layoutSubtreeIfNeeded();check(abs(controller.logView.frame.width-controller.logView.enclosingScrollView!.contentSize.width)<2)}
  controller.start();wait{controller.engine?.state == .watching};check(!controller.startButton.isEnabled && controller.stopButton.isEnabled && !controller.localField.isEnabled)
  controller.togglePause();wait{controller.engine?.state == .paused};check(controller.pauseButton.title=="继续监控")
  controller.togglePause();wait{controller.engine?.state == .watching}
  try Data("queued from UI".utf8).write(to:local.appendingPathComponent("file.txt"))
  wait{app.jobs.count==1 && app.jobs[0].finished && controller.engine?.state == .watching}
  check(!app.jobs[0].failed && app.jobs[0].customAction=="持续更新" && !app.jobs[0].retryAllowed && app.jobs[0].customOperation==nil && app.jobs[0].factory==nil && app.jobs[0].beforeTransfer==nil)
  check(try Data(contentsOf:remote.appendingPathComponent("file.txt"))==Data("queued from UI".utf8))
  // Closing a live session first stops monitoring, then closes exactly that tab asynchronously.
  check(!app.closeConnection(tab));wait{app.connections.isEmpty && app.continuousWindows.isEmpty && app.monitorWaiters.isEmpty}
  check(controller.engine!.state.terminal && !controller.window!.isVisible);check(!controller.logView.string.isEmpty);controller.logView.layoutManager!.ensureLayout(for:controller.logView.textContainer!);check(controller.logView.layoutManager!.usedRect(for:controller.logView.textContainer!).height>0)
  // A hidden standalone controller exercises explicit deletion approval without a modal dialog.
  let deleting=ContinuousSyncController(site:site,connection:"test-only",local:local.path,remote:remote.path,selected:[],defaults:defaults,factory:{_ in try SFTPClient(command:"/usr/libexec/sftp-server",arguments:[])})
  deleting.usesNativeEvents=false;deleting.interval.stringValue="0.5";deleting.settle.stringValue="0.5";deleting.cleanup.state = .on
  try Data("extra".utf8).write(to:remote.appendingPathComponent("extra"));var asked=false
  deleting.confirm={info,options in asked=true;check(options.cleanup && info.initialCleanup.contains("extra"));return false}
  deleting.start();wait{asked && deleting.engine!.state.terminal};check(fm.fileExists(atPath:remote.appendingPathComponent("extra").path))
  deleting.load(ContinuousOptions());deleting.interval.stringValue="0.5";deleting.settle.stringValue="0.5";deleting.cleanup.state = .on;deleting.confirm={_,_ in true}
  deleting.start();wait{deleting.engine?.state == .watching};var stopped=false
  app.afterMonitorsStop([deleting]){stopped=true};wait{stopped && app.monitorWaiters.isEmpty};check(deleting.engine!.state.terminal)
  if CommandLine.arguments.count>1 {
   deleting.localField.stringValue="/Users/demo/Documents/project";deleting.remoteField.stringValue="/home/demo/project";deleting.cleanup.state = .off;deleting.logView.string="示例预览：开始监控后，这里显示目录变化和执行结果。";deleting.stateLabel.stringValue="已停止 · 示例预览";deleting.window!.contentView!.layoutSubtreeIfNeeded()
   deleting.logView.layoutManager!.ensureLayout(for:deleting.logView.textContainer!);check(deleting.logView.visibleRect.minX==0 && deleting.logView.layoutManager!.usedRect(for:deleting.logView.textContainer!).height>0);let view=deleting.window!.contentView!;guard let bitmap=view.bitmapImageRepForCachingDisplay(in:view.bounds) else{fatalError("bitmap unavailable")};view.cacheDisplay(in:view.bounds,to:bitmap)
   guard let canvas=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:bitmap.pixelsWide,pixelsHigh:bitmap.pixelsHigh,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0),let context=NSGraphicsContext(bitmapImageRep:canvas) else{fatalError("canvas unavailable")}
   NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=context
   deleting.window!.effectiveAppearance.performAsCurrentDrawingAppearance{deleting.window!.backgroundColor.setFill();NSBezierPath(rect:NSRect(origin:.zero,size:canvas.size)).fill();let image=NSImage(size:view.bounds.size);image.addRepresentation(bitmap);image.draw(in:NSRect(origin:.zero,size:canvas.size),from:.zero,operation:.sourceOver,fraction:1)}
   NSGraphicsContext.restoreGraphicsState();guard let png=canvas.representation(using:.png,properties:[:]) else{fatalError("PNG unavailable")};try png.write(to:URL(fileURLWithPath:CommandLine.arguments[1]))
  }
  deleting.close();app.window.close();check(!auth.isVisible)
  print("PASS: hidden monitoring controls/options/validation, no automatic connection, actual App queue upload, pause/resume, duplicate-window prevention, session close waits for monitor, deletion approval/refusal and shared quit wait helper; no user endpoint/password/visible window")
 }
}
