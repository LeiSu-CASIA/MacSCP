import Cocoa
@main struct NativeSyncContentsTests {
 static func check(_ value:Bool,file:StaticString = #file,line:UInt = #line){precondition(value,file:file,line:line)}
 static func wait(_ condition:()->Bool){let end=Date().addingTimeInterval(8);while !condition(),Date()<end{RunLoop.current.run(until:Date().addingTimeInterval(0.01))};check(condition())}
 static func main()throws {
  NSApplication.shared.setActivationPolicy(.prohibited)
  let fm=FileManager.default,root=fm.temporaryDirectory.appendingPathComponent("native-sync-contents-"+UUID().uuidString),local=root.appendingPathComponent("local"),remote=root.appendingPathComponent("remote"),suite="sync-contents-ui-"+UUID().uuidString,defaults=UserDefaults(suiteName:suite)!
  for path in [local.appendingPathComponent("tree/sub"),local.appendingPathComponent("tree/empty"),remote]{try fm.createDirectory(at:path,withIntermediateDirectories:true)}
  defer{try? fm.removeItem(at:root);defaults.removePersistentDomain(forName:suite)}
  try Data("chosen".utf8).write(to:local.appendingPathComponent("tree/sub/keep.txt"));try Data("unchecked".utf8).write(to:local.appendingPathComponent("tree/sub/skip.txt"))
  let app=App(defaults:defaults,dataDirectory:root.appendingPathComponent("profile"),initialLocalDirectory:local.path,automaticLogin:false,showsMainWindow:false,frameAutosaveName:nil,clientProvider:{_,_ in try SFTPClient(command:"/usr/libexec/sftp-server",arguments:[])})
  app.applicationDidFinishLaunching(Notification(name:NSApplication.didFinishLaunchingNotification))
  let terminal=SSHConnection(arguments:["60"],helper:"/unused",executable:"/unused",command:"/bin/sleep");defer{terminal.stop()}
  let auth=NSWindow(contentRect:NSRect(x:0,y:0,width:100,height:100),styleMask:[.titled],backing:.buffered,defer:false);auth.isReleasedWhenClosed=false;defer{auth.close()}
  let site=Session(name:"本机选择测试",host:"fixture.invalid",user:"fixture",port:22,key:""),token=root.appendingPathComponent("token").path;try Data().write(to:URL(fileURLWithPath:token))
  let tab=ConnectionTab(site,token,terminal,auth,local.path,defaults:defaults);tab.connected=true;app.connections=[tab];app.selectedTab=0;app.session=site;app.socket=token
  let client=try SFTPClient(command:"/usr/libexec/sftp-server",arguments:[]);defer{client.close()}
  let l=try SyncPlanner.local(local.path),r=try SyncPlanner.remote(remote.path,client:client),rows=try SyncComparison.plannedCandidates(local:l,remote:r,settings:SyncSettings())
  check(rows.count==1 && rows[0].directory)
  let preview=app.makeSyncPreview(rows,localRoot:local.path,remoteRoot:remote.path,localSnapshot:l,remoteSnapshot:r,deletions:[:],site:site,socket:token,policy:TransferPolicy())
  preview.window!.contentView!.layoutSubtreeIfNeeded();preview.table.selectRowIndexes(IndexSet(integer:0),byExtendingSelection:false);check(preview.contentsButton.isEnabled)
  let detail=preview.showContents(row:0)!;detail.window!.contentView!.layoutSubtreeIfNeeded();check(!detail.window!.isVisible && detail.outline.enclosingScrollView!.frame.height>=220)
  detail.expandAll();check(detail.outline.numberOfRows==5)
  let rootCheck=detail.outlineView(detail.outline,viewFor:detail.outline.tableColumns[0],item:detail.outline.item(atRow:0)!) as! NSButton
  rootCheck.performClick(nil);check(detail.contents.selected.isEmpty);rootCheck.performClick(nil);check(detail.contents.selected==detail.contents.leaves && detail.outline.numberOfRows==5)
  detail.selectNone();detail.set("tree/sub/keep.txt",on:true);detail.set("tree/empty",on:true)
  check(detail.contents.state("tree") == .mixed && detail.contents.selected.count==2)
  if CommandLine.arguments.count>1 {
   detail.window!.contentView!.layoutSubtreeIfNeeded();let view=detail.window!.contentView!,bounds=view.bounds
   guard let bitmap=view.bitmapImageRepForCachingDisplay(in:bounds) else{fatalError("bitmap unavailable")};view.cacheDisplay(in:bounds,to:bitmap)
   guard let canvas=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:bitmap.pixelsWide,pixelsHigh:bitmap.pixelsHigh,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0),let context=NSGraphicsContext(bitmapImageRep:canvas) else{fatalError("canvas unavailable")}
   NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=context;detail.window!.effectiveAppearance.performAsCurrentDrawingAppearance{detail.window!.backgroundColor.setFill();NSBezierPath(rect:NSRect(origin:.zero,size:canvas.size)).fill();let image=NSImage(size:bounds.size);image.addRepresentation(bitmap);image.draw(in:NSRect(origin:.zero,size:canvas.size),from:.zero,operation:.sourceOver,fraction:1)};NSGraphicsContext.restoreGraphicsState();try canvas.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:CommandLine.arguments[1]))
  }
  detail.apply();check(preview.candidates[0].contents?.selected.count==2 && preview.candidates[0].selected && preview.contentsWindows.isEmpty)
  preview.apply();wait{app.jobs.count==1 && app.jobs[0].finished};check(!app.jobs[0].failed && !app.jobs[0].retryAllowed && app.jobs[0].restrictedPaths==["tree","tree/sub","tree/sub/keep.txt","tree/empty"])
  check(try Data(contentsOf:remote.appendingPathComponent("tree/sub/keep.txt"))==Data("chosen".utf8));check(!fm.fileExists(atPath:remote.appendingPathComponent("tree/sub/skip.txt").path));check(fm.fileExists(atPath:remote.appendingPathComponent("tree/empty").path))
  let again=app.makeSyncPreview(rows,localRoot:local.path,remoteRoot:remote.path,localSnapshot:l,remoteSnapshot:r,deletions:[:],site:site,socket:token,policy:TransferPolicy())
  let empty=again.showContents(row:0)!;empty.selectNone();empty.apply();check(!again.candidates[0].selected);again.selectExecutable();check(again.candidates[0].contents?.selected.count==3)
  var changed=l;changed["tree/sub/keep.txt"]=SyncNode(directory:false,size:999,modified:100)
  do{try app.enqueueSync(again.candidates,localRoot:local.path,remoteRoot:remote.path,localSnapshot:changed,remoteSnapshot:r,deletions:[:],site:site,socket:token,policy:TransferPolicy());fatalError("changed binding accepted")}catch{}
  check(app.jobs.count==1);again.close()
  try fm.createDirectory(at:local.appendingPathComponent("stale"),withIntermediateDirectories:true);try Data("before".utf8).write(to:local.appendingPathComponent("stale/file"))
  let sl=try SyncPlanner.local(local.path),sr=try SyncPlanner.remote(remote.path,client:client),staleRows=try SyncComparison.plannedCandidates(local:sl,remote:sr,settings:SyncSettings()).filter{$0.relative=="stale"}
  let stalePreview=app.makeSyncPreview(staleRows,localRoot:local.path,remoteRoot:remote.path,localSnapshot:sl,remoteSnapshot:sr,deletions:[:],site:site,socket:token,policy:TransferPolicy())
  let staleDetail=stalePreview.showContents(row:0)!;staleDetail.apply();try Data("changed after preview".utf8).write(to:local.appendingPathComponent("stale/file"));stalePreview.apply();wait{app.jobs.count==2 && app.jobs.last!.finished}
  check(app.jobs.last!.failed && !fm.fileExists(atPath:remote.appendingPathComponent("stale").path))
  app.jobs=[];app.window.close()
  print("PASS: hidden directory tree and mixed checkboxes, selected file/empty-dir scope reaches production App queue, unchecked file absent, no blind retry/recovery, empty choice disables action, stale manifest rejected before queueing; owned local SFTP only")
 }
}
