import Cocoa
@main struct NativePartialDeletionTests {
 static func check(_ value:Bool,file:StaticString = #file,line:UInt = #line){precondition(value,file:file,line:line)}
 static func wait(_ condition:()->Bool){let end=Date().addingTimeInterval(8);while !condition(),Date()<end{RunLoop.current.run(until:Date().addingTimeInterval(0.01))};check(condition())}
 static func render(_ window:NSWindow,_ path:String)throws{window.contentView!.layoutSubtreeIfNeeded();let view=window.contentView!,bounds=view.bounds;guard let bitmap=view.bitmapImageRepForCachingDisplay(in:bounds) else{fatalError("bitmap unavailable")};view.cacheDisplay(in:bounds,to:bitmap)
  guard let canvas=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:bitmap.pixelsWide,pixelsHigh:bitmap.pixelsHigh,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0),let context=NSGraphicsContext(bitmapImageRep:canvas) else{fatalError("canvas unavailable")}
  NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=context;window.effectiveAppearance.performAsCurrentDrawingAppearance{NSColor(calibratedWhite:0.95,alpha:1).setFill();NSBezierPath(rect:NSRect(origin:.zero,size:canvas.size)).fill();let image=NSImage(size:bounds.size);image.addRepresentation(bitmap);image.draw(in:NSRect(origin:.zero,size:canvas.size),from:.zero,operation:.sourceOver,fraction:1)};NSGraphicsContext.restoreGraphicsState();try canvas.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:path))
 }
 static func main()throws {
  NSApplication.shared.setActivationPolicy(.prohibited)
  let fm=FileManager.default,root=fm.temporaryDirectory.appendingPathComponent("native-partial-cleanup-"+UUID().uuidString),local=root.appendingPathComponent("local"),remote=root.appendingPathComponent("remote"),bin=root.appendingPathComponent("bin"),suite="partial-cleanup-ui-"+UUID().uuidString,defaults=UserDefaults(suiteName:suite)!
  for path in [local.appendingPathComponent("localtree"),remote.appendingPathComponent("tree/sub"),bin]{try fm.createDirectory(at:path,withIntermediateDirectories:true)}
  defer{try? fm.removeItem(at:root);defaults.removePersistentDomain(forName:suite)}
  for (base,path) in [(local,"localtree/drop"),(local,"localtree/keep"),(remote,"tree/sub/drop"),(remote,"tree/sub/keep")]{try Data(path.utf8).write(to:base.appendingPathComponent(path))}
  let app=App(defaults:defaults,dataDirectory:root.appendingPathComponent("profile"),initialLocalDirectory:local.path,automaticLogin:false,showsMainWindow:false,frameAutosaveName:nil,clientProvider:{_,_ in try SFTPClient(command:"/usr/libexec/sftp-server",arguments:[])})
  app.applicationDidFinishLaunching(Notification(name:NSApplication.didFinishLaunchingNotification))
  let terminal=SSHConnection(arguments:["60"],helper:"/unused",executable:"/unused",command:"/bin/sleep");defer{terminal.stop()}
  let auth=NSWindow(contentRect:NSRect(x:0,y:0,width:100,height:100),styleMask:[.titled],backing:.buffered,defer:false);auth.isReleasedWhenClosed=false;defer{auth.close()}
  let site=Session(name:"本机清理预览",host:"fixture.invalid",user:"fixture",port:22,key:""),token=root.appendingPathComponent("token").path;try Data().write(to:URL(fileURLWithPath:token))
  let tab=ConnectionTab(site,token,terminal,auth,local.path,defaults:defaults);tab.connected=true;app.connections=[tab];app.selectedTab=0;app.session=site;app.socket=token
  let client=try SFTPClient(command:"/usr/libexec/sftp-server",arguments:[]);defer{client.close()}
  func preview(_ up:Bool)throws->SyncPreviewController{let l=try SyncPlanner.local(local.path),r=try SyncPlanner.remote(remote.path,client:client),rows=SyncComparison.candidates(local:l,remote:r,direction:up ? .upload : .download,deleteExtraneous:true).filter{$0.deletion && $0.relative==(up ? "tree" : "localtree")};check(rows.count==1);let plan=try SyncDeletionPlan.prepare(rows[0],localRoot:local.path,remoteRoot:remote.path,localSnapshot:l,remoteSnapshot:r,client:client);return app.makeSyncPreview(rows,localRoot:local.path,remoteRoot:remote.path,localSnapshot:l,remoteSnapshot:r,deletions:[rows[0].relative:plan],site:site,socket:token,policy:TransferPolicy())}
  let remotePreview=try preview(true);remotePreview.table.selectRowIndexes(IndexSet(integer:0),byExtendingSelection:false);check(remotePreview.contentsButton.isEnabled)
  let detail=remotePreview.showContents(row:0)!;detail.expandAll();detail.selectNone();detail.set("tree/sub/drop",on:true);var premature=0;remotePreview.confirmDeletion={_ in premature+=1;return false};remotePreview.apply();check(premature==0 && app.jobs.isEmpty && remotePreview.summary.stringValue.contains("内容选择"));check(detail.window!.title.contains("清理") && remotePreview.contentsButton.title.contains("清理"));if CommandLine.arguments.count>1{try render(detail.window!,CommandLine.arguments[1])};detail.apply()
  check(remotePreview.deletionLines(remotePreview.candidates)==["远程永久删除：\"tree/sub/drop\""])
  let alert=remotePreview.deletionAlert(remotePreview.candidates);alert.layout();check(!alert.window.isVisible && alert.informativeText.contains(site.identity) && alert.informativeText.contains(remote.path))
  if CommandLine.arguments.count>2{let demo=SyncPreviewController(candidates:remotePreview.candidates,context:"示例预览（未连接服务器）\n本地：/Users/demo/Documents\n远程：demo@example.invalid /home/demo/project");let demoAlert=demo.deletionAlert(demo.candidates);demoAlert.icon=NSImage(contentsOfFile:FileManager.default.currentDirectoryPath+"/Resources/AppIcon.icns");demoAlert.layout();try render(demoAlert.window,CommandLine.arguments[2]);demo.close()}
  let scroll=alert.accessoryView as! NSScrollView,text=scroll.documentView as! NSTextView;check(text.string.contains("tree/sub/drop") && !text.string.contains("keep") && text.frame.width<=scroll.contentSize.width+1)
  remotePreview.confirmDeletion={_ in false};remotePreview.apply();check(app.jobs.isEmpty && fm.fileExists(atPath:remote.appendingPathComponent("tree/sub/drop").path))
  remotePreview.confirmDeletion={selected in check(selected[0].contents!.selectedRoots==["tree/sub/drop"]);return true};remotePreview.apply();wait{app.jobs.count==1 && app.jobs[0].finished}
  check(!app.jobs[0].failed && !app.jobs[0].retryAllowed && app.jobs[0].transferredBytes==0);check(!fm.fileExists(atPath:remote.appendingPathComponent("tree/sub/drop").path));check(fm.fileExists(atPath:remote.appendingPathComponent("tree/sub/keep").path))
  var moved=[String]();app.localTrashHandler={url in moved.append(url.lastPathComponent);try fm.moveItem(at:url,to:bin.appendingPathComponent(UUID().uuidString))}
  let localPreview=try preview(false),localDetail=localPreview.showContents(row:0)!;localDetail.selectNone();localDetail.set("localtree/drop",on:true);localDetail.apply()
  check(localPreview.deletionLines(localPreview.candidates)==["本地移到废纸篓：\"localtree/drop\""])
  localPreview.confirmDeletion={_ in true};localPreview.apply();wait{app.jobs.count==2 && app.jobs[1].finished};check(!app.jobs[1].failed && moved==["drop"] && fm.fileExists(atPath:local.appendingPathComponent("localtree/keep").path))
  // Confirmation never truncates the actual path list, and its view can scroll through it.
  let node=SyncNode(directory:false,size:1,modified:100),many=(0..<250).map{SyncCandidate(relative:"many/file-\($0)",local:nil,remote:node,upload:true,selected:true,typeConflict:false,deletion:true)}
  let manyAlert=localPreview.deletionAlert(many);manyAlert.layout();let manyScroll=manyAlert.accessoryView as! NSScrollView,manyText=manyScroll.documentView as! NSTextView
  check(manyText.string.contains("file-249") && manyText.string.components(separatedBy:"\n").count==250);manyText.layoutManager!.ensureLayout(for:manyText.textContainer!);check(manyText.layoutManager!.usedRect(for:manyText.textContainer!).height>manyScroll.contentSize.height && !manyAlert.window.isVisible);check(manyText.frame.height>=manyText.layoutManager!.usedRect(for:manyText.textContainer!).maxY);manyText.scrollToEndOfDocument(nil);check(manyScroll.contentView.bounds.origin.y>0)
  app.jobs=[];app.window.close()
  print("PASS: hidden cleanup tree, precise final confirmation with all paths and scrollable long list, refusal leaves queue/files unchanged, actual App selected remote deletion/local injected trash, unchecked siblings retained, zero bytes/no blind retry; no user server or real Trash")
 }
}
