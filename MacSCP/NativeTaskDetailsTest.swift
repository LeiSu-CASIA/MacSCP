import Cocoa
@main struct NativeTaskDetailsTests {
 static func check(_ value:Bool,file:StaticString = #file,line:UInt = #line){precondition(value,file:file,line:line)}
 static func main()throws{
  NSApplication.shared.setActivationPolicy(.prohibited)
  let root=FileManager.default.temporaryDirectory.appendingPathComponent("native-task-details-"+UUID().uuidString),suite="macscp-task-details-"+UUID().uuidString,defaults=UserDefaults(suiteName:suite)!
  try FileManager.default.createDirectory(at:root,withIntermediateDirectories:false);defer{try? FileManager.default.removeItem(at:root);defaults.removePersistentDomain(forName:suite)}
  var network=0
  let app=App(defaults:defaults,dataDirectory:root.appendingPathComponent("profile"),initialLocalDirectory:root.path,automaticLogin:false,showsMainWindow:false,frameAutosaveName:nil,clientProvider:{_,_ in network+=1;throw SFTPError.message("unexpected connection")})
  app.applicationDidFinishLaunching(Notification(name:NSApplication.didFinishLaunchingNotification))
  defer{for window in Array(app.taskDetailsWindows.values){window.close()};app.jobs=[];app.window.close()}
  let site=Session(name:"示例服务器",host:"example.invalid",user:"demo",port:22,key:"/private/not-displayed-key"),first=TransferJob(up:true,source:"/Users/demo/Documents/project/report.txt",destination:"/srv/project/report.txt",directory:false,size:32768),second=TransferJob(up:false,source:"/srv/data.csv",destination:"/Users/demo/data.csv",directory:false,size:2048)
  second.recoverySite=site;second.policy=TransferPolicy(verifyChecksum:true,text:TextTransferOptions(mode:.automatic));second.policyConfigured=true
  first.recoverySite=site;first.policy=TransferPolicy(include:"*.txt",exclude:"*.tmp",verifyChecksum:true,text:TextTransferOptions(mode:.automatic,remote:.crlf,removeBOM:true));first.policyConfigured=true;first.speedLimit=128*1024;app.jobs=[first,second];app.reloadQueue()
  let controller=app.makeTaskDetails(first);check(app.makeTaskDetails(first) === controller && app.taskDetailsWindows.count==1 && !controller.timerActive)
  app.queueTable.selectRowIndexes(IndexSet(integer:0),byExtendingSelection:false);app.showJobDetails();check(app.taskDetailsWindows.count==1 && !controller.window!.isVisible)
  check(controller.report.contains("自动 · 按文本文件掩码") && controller.report.contains("CRLF") && controller.report.contains("*.tmp") && controller.report.contains("demo@example.invalid") && !controller.report.contains("not-displayed-key"))
  app.preferences=TransferPreferences(policy:TransferPolicy());app.session=Session(name:"别的会话",host:"other.invalid",user:"other",port:22,key:"");controller.refresh();check(controller.report.contains("example.invalid") && !controller.report.contains("other.invalid"))
  var copied="";controller.copyText={copied=$0};controller.copyButton.performClick(nil);check(copied==controller.report && copied.contains(first.source))
  app.jobs=[second,first];app.reloadQueue();controller.locateButton.performClick(nil);check(app.queueTable.selectedRow==1)
  for size in [NSSize(width:780,height:590),NSSize(width:680,height:480)]{controller.window!.setContentSize(size);controller.window!.contentView!.layoutSubtreeIfNeeded();let bounds=controller.window!.contentView!.bounds
   for view in [controller.heading,controller.endpoint,controller.status,controller.progress,controller.copyButton,controller.locateButton] as [NSView]{let rect=view.convert(view.bounds,to:controller.window!.contentView!);check(rect.minX>=0 && rect.maxX<=bounds.width+1 && rect.minY>=0 && rect.maxY<=bounds.height+1)}
   check(controller.output.enclosingScrollView!.frame.height>=190 && controller.output.frame.height>0);check(controller.output.frame.width<=controller.output.enclosingScrollView!.contentSize.width+1)
  }
  app.window.contentView!.layoutSubtreeIfNeeded()
  func context(_ point:NSPoint){let event=NSEvent.mouseEvent(with:.rightMouseDown,location:app.queueTable.convert(point,to:nil),modifierFlags:[],timestamp:0,windowNumber:app.window.windowNumber,context:nil,eventNumber:0,clickCount:1,pressure:1)!;_ = app.queueTable.menu(for:event)}
  app.queueTable.selectRowIndexes(IndexSet(integer:0),byExtendingSelection:false);context(NSPoint(x:20,y:app.queueTable.rect(ofRow:1).midY));check(app.queueTable.selectedRow==1)
  app.queueTable.selectRowIndexes(IndexSet(integersIn:0..<2),byExtendingSelection:false);context(NSPoint(x:20,y:app.queueTable.rect(ofRow:1).midY));check(app.queueTable.selectedRowIndexes.count==2)
  context(NSPoint(x:20,y:app.queueTable.bounds.maxY-1));check(app.queueTable.selectedRowIndexes.isEmpty)
  check(app.queueTable.doubleAction == #selector(App.showJobDetails) && app.queueTable.target === app)
  app.queueTable.selectRowIndexes(IndexSet(integer:0),byExtendingSelection:false)
  let event=NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:app.window.windowNumber,context:nil,characters:"\r",charactersIgnoringModifiers:"\r",isARepeat:false,keyCode:36)!;app.queueTable.keyDown(with:event);check(app.taskDetailsWindows.count==2)
  first.finishWithoutStarting("失败：fixture failure\n"+String(repeating:"完整错误原因；",count:100),failed:true);controller.refresh();check(controller.status.textColor == .systemRed && controller.report.contains("完整错误原因"));app.clearFinished();controller.refresh();check(!controller.locateButton.isEnabled && controller.report.contains("任务已从队列移除"));controller.locateButton.performClick(nil);check(app.jobs.count==1)
  first.customAction="远程时间";controller.refresh();check(controller.total.stringValue=="不传输内容" && controller.report.contains("专用操作未提供逐文件统计") && !controller.report.contains("已完成文件：0 / 0"));first.customAction=nil;controller.refresh()
  controller.window!.setContentSize(NSSize(width:780,height:590));controller.window!.contentView!.layoutSubtreeIfNeeded()
  if CommandLine.arguments.count>1{let preview=app.makeTaskDetails(second);preview.window!.contentView!.layoutSubtreeIfNeeded();let window=preview.window!,view=window.contentView!;preview.output.layoutManager!.ensureLayout(for:preview.output.textContainer!);check(preview.output.frame.width<=preview.output.enclosingScrollView!.contentSize.width+1);preview.output.layoutManager!.enumerateLineFragments(forGlyphRange:NSRange(location:0,length:preview.output.layoutManager!.numberOfGlyphs)){_,used,container,_,_ in check(used.maxX<=container.containerSize.width+1)};let bounds=view.bounds,bitmap=view.bitmapImageRepForCachingDisplay(in:view.bounds)!;view.cacheDisplay(in:bounds,to:bitmap)
   let canvas=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:bitmap.pixelsWide,pixelsHigh:bitmap.pixelsHigh,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!,graphics=NSGraphicsContext(bitmapImageRep:canvas)!
   NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=graphics;window.effectiveAppearance.performAsCurrentDrawingAppearance{window.backgroundColor.setFill();NSBezierPath(rect:NSRect(origin:.zero,size:canvas.size)).fill();let image=NSImage(size:bounds.size);image.addRepresentation(bitmap);image.draw(in:NSRect(origin:.zero,size:canvas.size),from:.zero,operation:.sourceOver,fraction:1)};NSGraphicsContext.restoreGraphicsState();try canvas.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:CommandLine.arguments[1]))
  }
  weak var released:TaskDetailsController?
  autoreleasepool{var live:TaskDetailsController?=TaskDetailsController(job:second);released=live
   check(live!.timerActive);second.finishWithoutStarting("已完成");RunLoop.current.run(until:Date().addingTimeInterval(0.5));check(live!.status.stringValue=="已完成");live!.close();check(!live!.timerActive);live=nil
  }
  check(released==nil)
  let removed=controller.job.id;controller.close();check(app.taskDetailsWindows[removed]==nil)
  check(network==0 && !app.window.isVisible)
  print("PASS: hidden per-job singleton details, pinned policy/endpoint not current preferences, copy sink, stable-ID queue location/reorder/removal, long failure report, 680/780 layouts, Return/double-click hooks, live refresh and timer teardown; no network/window/clipboard/authentication")
 }
}
