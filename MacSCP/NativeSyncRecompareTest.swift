import Cocoa
@main struct NativeSyncRecompareTests {
 static func check(_ value:Bool,file:StaticString = #file,line:UInt = #line){precondition(value,file:file,line:line)}
 static func wait(_ condition:()->Bool){let end=Date().addingTimeInterval(10);while !condition(),Date()<end{RunLoop.current.run(until:Date().addingTimeInterval(0.01))};check(condition())}
 static func render(_ window:NSWindow,_ path:String)throws{window.appearance=NSAppearance(named:.aqua);window.contentView!.layoutSubtreeIfNeeded();let view=window.contentView!,bounds=view.bounds;guard let bitmap=view.bitmapImageRepForCachingDisplay(in:bounds) else{fatalError("bitmap unavailable")};view.cacheDisplay(in:bounds,to:bitmap)
  guard let canvas=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:bitmap.pixelsWide,pixelsHigh:bitmap.pixelsHigh,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0),let context=NSGraphicsContext(bitmapImageRep:canvas) else{fatalError("canvas unavailable")}
  NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=context;window.effectiveAppearance.performAsCurrentDrawingAppearance{NSColor(calibratedWhite:0.95,alpha:1).setFill();NSBezierPath(rect:NSRect(origin:.zero,size:canvas.size)).fill();let image=NSImage(size:bounds.size);image.addRepresentation(bitmap);image.draw(in:NSRect(origin:.zero,size:canvas.size),from:.zero,operation:.sourceOver,fraction:1)};NSGraphicsContext.restoreGraphicsState();try canvas.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:path))
 }
 static func main()throws{
  NSApplication.shared.setActivationPolicy(.prohibited)
  let fm=FileManager.default,root=fm.temporaryDirectory.appendingPathComponent("native-sync-recompare-"+UUID().uuidString),local=root.appendingPathComponent("local"),remote=root.appendingPathComponent("remote"),otherLocal=root.appendingPathComponent("other-local"),otherRemote=root.appendingPathComponent("other-remote"),suite="recompare-ui-"+UUID().uuidString,defaults=UserDefaults(suiteName:suite)!
  for path in [local.appendingPathComponent("tree/sub"),remote,otherLocal,otherRemote]{try fm.createDirectory(at:path,withIntermediateDirectories:true)};defer{try? fm.removeItem(at:root);defaults.removePersistentDomain(forName:suite)}
  func put(_ base:URL,_ path:String,_ text:String)throws{let url=base.appendingPathComponent(path);try fm.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true);try Data(text.utf8).write(to:url)}
  try put(local,"tree/sub/keep","original");try put(local,"tree/sub/skip","unchecked")
  var calls=0
  let app=App(defaults:defaults,dataDirectory:root.appendingPathComponent("profile"),initialLocalDirectory:local.path,automaticLogin:false,showsMainWindow:false,frameAutosaveName:nil,clientProvider:{_,_ in calls+=1;return try SFTPClient(command:"/usr/libexec/sftp-server",arguments:[])})
  app.applicationDidFinishLaunching(Notification(name:NSApplication.didFinishLaunchingNotification))
  let terminal=SSHConnection(arguments:["60"],helper:"/unused",executable:"/unused",command:"/bin/sleep");defer{terminal.stop()}
  let auth=NSWindow(contentRect:NSRect(x:0,y:0,width:100,height:100),styleMask:[.titled],backing:.buffered,defer:false);auth.isReleasedWhenClosed=false;defer{auth.close()}
  let site=Session(name:"重新比较测试",host:"fixture.invalid",user:"fixture",port:22,key:""),token=root.appendingPathComponent("token").path;try Data().write(to:URL(fileURLWithPath:token))
  let tab=ConnectionTab(site,token,terminal,auth,local.path,defaults:defaults);tab.connected=true;app.connections=[tab];app.selectedTab=0;app.session=site;app.socket=token
  let client=try SFTPClient(command:"/usr/libexec/sftp-server",arguments:[]);defer{client.close()}
  func context(_ settings:SyncSettings=SyncSettings())throws->SyncRetryContext{try SyncRetryContext(site:site,socket:token,settings:settings,policy:TransferPolicy(),local:local.path,remote:remote.path,client:client)}
  let ctx=try context(),l=try SyncPlanner.local(local.path),r=try SyncPlanner.remote(remote.path,client:client);var action=SyncComparison.candidates(local:l,remote:r,direction:.upload).first{$0.relative=="tree"}!
  var contents=try SyncContents(root:"tree",snapshot:l,policy:TransferPolicy());contents.setAll(false);contents.set("tree/sub/keep",on:true);action.contents=contents
  app.togglePause();let first=try app.enqueueSync([action],localRoot:local.path,remoteRoot:remote.path,localSnapshot:l,remoteSnapshot:r,deletions:[:],site:site,socket:token,policy:TransferPolicy(),retryContext:ctx)[0]
  try put(local,"tree/sub/keep","new content after original preview");app.togglePause();wait{first.finished && !first.isExecuting && !app.transfers.contains(first.id)};check(first.failed && !fm.fileExists(atPath:remote.appendingPathComponent("tree").path))
  // Changing the browsed directories cannot redirect an old task's recompare.
  app.local.acceptPath(otherLocal.path);app.remote.acceptPath(otherRemote.path)
  app.queueTable.selectRowIndexes(IndexSet(integer:0),byExtendingSelection:false);app.retrySelected();wait{app.syncRecomparePreviews[ctx.id] != nil && app.syncRecompareOperations.isEmpty}
  let preview=app.syncRecomparePreviews[ctx.id]!;check(app.jobs.count==1 && first.failed && !preview.window!.isVisible && preview.context.contains(remote.path))
  check(preview.candidates.count==1 && preview.candidates[0].contents!.selected==["tree/sub/keep"])
  if CommandLine.arguments.count>1{let demo=SyncPreviewController(candidates:preview.candidates,context:"失败任务重新比较 · 示例数据（未连接服务器）\n仍需确认后才会执行；仅保留原来勾选的 keep 文件，skip 不会传输。\n本地：/Users/demo/Documents/project\n远程：demo@example.invalid /home/demo/project");try render(demo.window!,CommandLine.arguments[1]);demo.close()}
  app.retrySelected();check(app.syncRecomparePreviews.count==1 && app.syncRecompareOperations.isEmpty)
  check(!fm.fileExists(atPath:remote.appendingPathComponent("tree").path));preview.apply();wait{app.jobs.count==2 && app.jobs[1].finished}
  check(!app.jobs[1].failed && app.syncRetrySuperseded.contains(first.id) && first.beforeTransfer==nil && first.factory==nil);check(try Data(contentsOf:remote.appendingPathComponent("tree/sub/keep"))==Data("new content after original preview".utf8));check(!fm.fileExists(atPath:remote.appendingPathComponent("tree/sub/skip").path))
  app.queueTable.selectRowIndexes(IndexSet(integer:0),byExtendingSelection:false);app.retrySelected();check(app.syncRecompareOperations.isEmpty && app.status.stringValue.contains("重新处理"))
  // Cleanup failures produce new deletion plans and still require a new destructive confirmation.
  try put(remote,"obsolete/drop","old");try put(remote,"obsolete/keep","keep")
  let dl=try SyncPlanner.local(local.path),dr=try SyncPlanner.remote(remote.path,client:client),dc=try context(SyncSettings(cleanup:true));var deletion=SyncComparison.candidates(local:dl,remote:dr,direction:.upload,deleteExtraneous:true).first{$0.relative=="obsolete" && $0.deletion}!
  var dcContents=try SyncContents(root:"obsolete",snapshot:dr,policy:TransferPolicy());dcContents.setAll(false);dcContents.set("obsolete/drop",on:true);deletion.contents=dcContents
  let oldPlan=try SyncDeletionPlan.prepare(deletion,localRoot:local.path,remoteRoot:remote.path,localSnapshot:dl,remoteSnapshot:dr,client:client)
  app.togglePause();let failedDelete=try app.enqueueSync([deletion],localRoot:local.path,remoteRoot:remote.path,localSnapshot:dl,remoteSnapshot:dr,deletions:["obsolete":oldPlan],site:site,socket:token,policy:TransferPolicy(),retryContext:dc)[0]
  try put(remote,"obsolete/drop","changed target");app.togglePause();wait{failedDelete.finished && !failedDelete.isExecuting && !app.transfers.contains(failedDelete.id)};check(failedDelete.failed)
  app.queueTable.selectRowIndexes(IndexSet(integer:2),byExtendingSelection:false);app.recompareSelectedSync();wait{app.syncRecomparePreviews[dc.id] != nil}
  let deletePreview=app.syncRecomparePreviews[dc.id]!;check(deletePreview.candidates.map{$0.relative}==["obsolete/drop"] && app.jobs.count==3)
  deletePreview.confirmDeletion={_ in false};deletePreview.apply();check(app.jobs.count==3 && fm.fileExists(atPath:remote.appendingPathComponent("obsolete/drop").path))
  deletePreview.confirmDeletion={_ in true};deletePreview.apply();wait{app.jobs.count==4 && app.jobs[3].finished};check(!app.jobs[3].failed && fm.fileExists(atPath:remote.appendingPathComponent("obsolete/keep").path) && !fm.fileExists(atPath:remote.appendingPathComponent("obsolete/drop").path))
  // Canceled syncs can be compared too; canceling comparison never retries the old job.
  try put(local,"cancelled","canceled scope");let cl=try SyncPlanner.local(local.path),cr=try SyncPlanner.remote(remote.path,client:client),cc=try context(),cancelAction=SyncCandidate(relative:"cancelled",local:cl["cancelled"],remote:nil,upload:true,selected:true,typeConflict:false)
  app.togglePause();let cancelled=try app.enqueueSync([cancelAction],localRoot:local.path,remoteRoot:remote.path,localSnapshot:cl,remoteSnapshot:cr,deletions:[:],site:site,socket:token,policy:TransferPolicy(),retryContext:cc)[0];cancelled.cancel();app.transfers.refresh();wait{cancelled.finished && !cancelled.isExecuting && !app.transfers.contains(cancelled.id)}
  app.queueTable.selectRowIndexes(IndexSet(integer:4),byExtendingSelection:false);app.recompareSelectedSync();check(app.queueTable.selectedRowIndexes==IndexSet(integer:4) && app.syncRecompareOperations[cc.id] != nil);app.cancelSelected();wait{app.syncRecompareOperations.isEmpty};check(app.syncRecomparePreviews[cc.id]==nil && app.jobs.count==5 && cancelled.wasCancelled)
  app.togglePause();wait{app.jobs.allSatisfy{$0.finished && !$0.isExecuting}}
  check(app.closeConnection(tab));let prior=calls;app.recompareSelectedSync();check(app.syncRecompareOperations.isEmpty && app.status.stringValue.contains("手动登录") && calls==prior && !auth.isVisible)
  // A manually supplied replacement session can be used; closing it cancels its pending preview.
  let newTerminal=SSHConnection(arguments:["60"],helper:"/unused",executable:"/unused",command:"/bin/sleep");defer{newTerminal.stop()};let newToken=root.appendingPathComponent("new-token").path;try Data().write(to:URL(fileURLWithPath:newToken))
  let newTab=ConnectionTab(site,newToken,newTerminal,auth,local.path,defaults:defaults);newTab.connected=true;app.connections=[newTab];app.selectedTab=0;app.session=site;app.socket=newToken
  app.recompareSelectedSync();wait{app.syncRecomparePreviews[cc.id] != nil};check(app.jobs.count==5 && app.syncRecompareConnections[cc.id]==newToken)
  check(app.closeConnection(newTab));check(app.syncRecomparePreviews.isEmpty && app.syncRecompareConnections.isEmpty)
  app.clearFinished();check(app.jobs.isEmpty && app.syncRetryIntents.isEmpty && app.syncRetryNotes.isEmpty && app.syncRetrySuperseded.isEmpty)
  app.window.close()
  print("PASS: production failed-sync recompare uses original roots/scope and new previews without writes, no duplicate comparison, fresh confirmation before retry/delete, unchecked siblings retained, history annotated, cancel/read-only compare, manual-login requirement, explicit replacement session and close/clear cleanup; hidden local fixtures only")
 }
}
