import Cocoa
final class OptionsClipboard:FileClipboardAccess {var value=FileClipboardSnapshot();func read()throws->FileClipboardSnapshot{value};func write(_ value:FileClipboardSnapshot)throws{self.value=value}}
@main struct NativeTransferOptionsTests {
 static func check(_ value:Bool,file:StaticString = #file,line:UInt = #line){precondition(value,file:file,line:line)}
 static func wait(_ value:()->Bool,file:StaticString = #file,line:UInt = #line){let end=Date().addingTimeInterval(10);while !value(),Date()<end{RunLoop.current.run(until:Date().addingTimeInterval(0.01))};check(value(),file:file,line:line)}
 static func render(_ window:NSWindow,to path:String)throws{let view=window.contentView!,bounds=view.bounds,bitmap=view.bitmapImageRepForCachingDisplay(in:bounds)!;view.cacheDisplay(in:bounds,to:bitmap);let canvas=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:bitmap.pixelsWide,pixelsHigh:bitmap.pixelsHigh,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!,context=NSGraphicsContext(bitmapImageRep:canvas)!;NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=context;window.effectiveAppearance.performAsCurrentDrawingAppearance{window.backgroundColor.setFill();NSBezierPath(rect:NSRect(origin:.zero,size:canvas.size)).fill();let image=NSImage(size:bounds.size);image.addRepresentation(bitmap);image.draw(in:NSRect(origin:.zero,size:canvas.size),from:.zero,operation:.sourceOver,fraction:1)};NSGraphicsContext.restoreGraphicsState();try canvas.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:path))}
 static func main()throws{
  NSApplication.shared.setActivationPolicy(.prohibited)
  let fm=FileManager.default,root=fm.temporaryDirectory.appendingPathComponent("transfer-options-"+UUID().uuidString),suite="macscp-transfer-options-"+UUID().uuidString,defaults=UserDefaults(suiteName:suite)!
  for name in ["local","remote","target","download","copy"]{try fm.createDirectory(at:root.appendingPathComponent(name),withIntermediateDirectories:true)};defer{try? fm.removeItem(at:root);defaults.removePersistentDomain(forName:suite)}
  let local=root.appendingPathComponent("local"),remote=root.appendingPathComponent("remote"),target=root.appendingPathComponent("target"),source=local.appendingPathComponent("说明.txt"),bytes=Data("line\nline\n".utf8);try bytes.write(to:source);try Data("existing".utf8).write(to:target.appendingPathComponent("说明.txt"))
  var clients=0,gate:DispatchSemaphore?,entered=false,errors=[String](),conflicts=0
  let app=App(defaults:defaults,dataDirectory:root.appendingPathComponent("profile"),initialLocalDirectory:local.path,automaticLogin:false,showsMainWindow:false,transferOptionsEnabled:true,frameAutosaveName:nil,clientProvider:{_,_ in clients+=1;if let wait=gate{entered=true;wait.wait()};return try SFTPClient(command:"/usr/libexec/sftp-server",arguments:[])})
  app.relayStagingRoot={try RelayStorage.prepare(at:fm.temporaryDirectory)};let clipboard=OptionsClipboard();app.fileClipboard=clipboard;clipboard.value=try FileClipboardEnvelope.encode(owner:app.clipboardOwner,files:[DragFile(path:source.path,directory:false,size:UInt64(bytes.count),connection:nil)]);app.alertPresenter={errors.append($0)};app.transferOptionsPresenter={_ in};app.applicationDidFinishLaunching(Notification(name:NSApplication.didFinishLaunchingNotification));app.transfers.isSuspended=true
  let ssh=SSHConnection(arguments:["60"],helper:"/unused",executable:"/unused",command:"/bin/sleep"),auth=NSWindow(contentRect:NSRect(x:0,y:0,width:100,height:100),styleMask:[.titled],backing:.buffered,defer:false);auth.isReleasedWhenClosed=false
  let site=Session(name:"示例服务器",host:"options.invalid",user:"fixture",port:22,key:""),tab=ConnectionTab(site,"options-"+UUID().uuidString,ssh,auth,local.path,defaults:defaults);tab.connected=true
  app.connections=[tab];app.selectedTab=0;app.session=site;app.socket=tab.socket;app.terminal=ssh;app.auth=auth;app.remote.setConnectionState(.connected);app.remote.acceptPath(try LocalReadClient().canonical(remote.path));app.remote.reload()
  defer{app.transferConfirmation?.cancel();for job in app.jobs{job.cancel()};app.transfers.cancelAllOperations();app.transfers.isSuspended=false;tab.stop();auth.close();app.window.close()}
  func select(){app.local.path.stringValue=local.path;app.loadLocal();app.local.table.selectRowIndexes(IndexSet(integer:app.local.entries.firstIndex{$0.name=="说明.txt"}!),byExtendingSelection:false)}
  select();app.enqueue(true);let cancelled=app.transferConfirmation!;check(app.jobs.isEmpty && clients==0 && !cancelled.window!.isVisible)
  cancelled.suppress.state = .on;cancelled.cancel();check(app.transferConfirmation==nil && app.transferOptionsEnabled && app.jobs.isEmpty);cancelled.apply();check(app.jobs.isEmpty)
  select();app.enqueue(true);let invalid=app.transferConfirmation!;invalid.destination.stringValue="relative";invalid.apply();check(!invalid.closed && invalid.notice.textColor == .systemRed && app.jobs.isEmpty);invalid.cancel()
  app.pasteFiles(true);check(app.transferConfirmation != nil);let same=app.transferConfirmation!;same.apply();check(!same.closed && same.notice.stringValue.contains("自身") && app.jobs.isEmpty);same.cancel()
  select();app.enqueue(true);let stale=app.transferConfirmation!;app.local.acceptPath(root.appendingPathComponent("copy").path);stale.apply();check(!stale.closed && stale.notice.stringValue.contains("变化") && app.jobs.isEmpty);stale.cancel();select()
  let presetPrefs=TransferPreferences(concurrency:8,kibibytesPerSecond:64,policy:TransferPolicy(include:"*.txt",verifyChecksum:true,text:TextTransferOptions(mode:.text,remote:.crlf)))
  _ = try app.transferPresets.add(name:"文本与校验",preferences:presetPrefs)
  app.preferences=TransferPreferences(concurrency:3,kibibytesPerSecond:128);let original=app.preferences
  app.enqueue(true);let dialog=app.transferConfirmation!
  for size in [NSSize(width:700,height:720),NSSize(width:660,height:700)]{dialog.window!.setContentSize(size);dialog.window!.contentView!.layoutSubtreeIfNeeded();let view=dialog.window!.contentView!
   for control in [dialog.destination,dialog.form,dialog.independent,dialog.suppress,dialog.applyButton,dialog.notice] as [NSView]{let rect=control.convert(control.bounds,to:view);check(rect.minX>=0 && rect.maxX<=view.bounds.width+1 && rect.minY>=0 && rect.maxY<=view.bounds.height+1)}
   check(dialog.table.enclosingScrollView!.frame.height>=75 && dialog.form.concurrency.superview==nil)
  }
  dialog.preset.selectItem(at:1);dialog.pickPreset();check(dialog.independent.state == .on && dialog.form.speed.isEnabled)
  dialog.destination.stringValue=target.path;app.transferConflictPrompt={_ in conflicts+=1;return .init(action:.replace)}

  dialog.apply();check(dialog.busy && app.jobs.isEmpty);wait{app.transferConfirmation==nil && app.jobs.count==1}
  let job=app.jobs[0];check(conflicts==1 && job.destination==(try! LocalReadClient().canonical(target.path) as NSString).appendingPathComponent("说明.txt") && job.policy==presetPrefs.filePolicy && job.overrideSpeedLimit==65536 && job.speedLimit==65536 && app.preferences==original && app.transfers.maxConcurrentOperationCount==3)
  app.preferences.kibibytesPerSecond=256;app.refreshTransferRuntime();check(job.speedLimit==65536)
  check(try TransferJob.restore(job.snapshot(site:site)).overrideSpeedLimit==65536)
  app.transfers.isSuspended=false;wait{job.finished && !job.isExecuting};check(try !job.failed && (try Data(contentsOf:target.appendingPathComponent("说明.txt")))==Data("line\r\nline\r\n".utf8))
  // Cancel a target probe while its factory is delayed: no late task may be submitted.
  app.transfers.isSuspended=true;select();app.enqueue(true);let late=app.transferConfirmation!;late.destination.stringValue=target.path;let semaphore=DispatchSemaphore(value:0);gate=semaphore;entered=false;late.apply();wait{entered};late.cancel();semaphore.signal();gate=nil
  let clientCount=clients;var drained=false;DispatchQueue.global().async{Thread.sleep(forTimeInterval:0.1);DispatchQueue.main.async{drained=true}};wait{drained};check(app.jobs.count==1 && app.transferConfirmation==nil)
  select();app.enqueue(true);let missing=app.transferConfirmation!;missing.destination.stringValue=root.appendingPathComponent("missing").path;missing.apply();wait{!missing.busy};check(!missing.closed && missing.notice.textColor == .systemRed && app.jobs.count==1 && !fm.fileExists(atPath:root.appendingPathComponent("missing").path));missing.cancel()
  select();app.enqueue(true);let changed=app.transferConfirmation!;changed.destination.stringValue=target.path;let held=DispatchSemaphore(value:0);gate=held;entered=false;changed.apply();wait{entered};app.remote.acceptPath(remote.appendingPathComponent("changed").path);held.signal();gate=nil;wait{!changed.busy};check(changed.notice.stringValue.contains("变化") && app.jobs.count==1);changed.cancel();app.remote.acceptPath(try LocalReadClient().canonical(remote.path))
  // Download and local copy confirm the explicit local directory and keep the main pane path.
  app.remote.entries=[Entry(name:"说明.txt",size:UInt64(bytes.count),dir:false)];app.remote.acceptPath(try LocalReadClient().canonical(target.path));app.remote.reload();app.remote.table.selectRowIndexes(IndexSet(integer:0),byExtendingSelection:false);app.enqueue(false);if app.transferConfirmation==nil{print("missing download confirmation:",app.status.stringValue,"selected",app.remote.selected.count,"ready",app.remoteConnectionReady);fflush(stdout)};check(app.transferConfirmation != nil);let download=app.transferConfirmation!;download.destination.stringValue=root.appendingPathComponent("download").path;download.apply();check(app.jobs.count==2 && !app.jobs[1].up && app.jobs[1].destination.hasPrefix(try! LocalReadClient().canonical(root.appendingPathComponent("download").path)) && app.local.currentPath==local.path)
  app.transfers.isSuspended=false;wait{app.jobs[1].finished};check(!app.jobs[1].failed)
  app.transfers.isSuspended=true;let file=DragFile(path:source.path,directory:false,size:UInt64(bytes.count),connection:nil);app.pasteFiles(true);check(app.transferConfirmation != nil);let copy=app.transferConfirmation!;check(copy.localOnly && !copy.form.modeButton.isEnabled && !copy.preset.isEnabled);copy.destination.stringValue=root.appendingPathComponent("copy").path;copy.apply();check(app.jobs.count==3 && app.jobs[2].policy.text==nil)
  app.transfers.isSuspended=false;wait{app.jobs[2].finished};check(try Data(contentsOf:root.appendingPathComponent("copy/说明.txt"))==bytes)
  // Relay snapshots and both running stages retain explicit unlimited speed.
  app.transfers.isSuspended=true
  let remoteFile=DragFile(path:target.appendingPathComponent("说明.txt").path,directory:false,size:12,connection:tab.socket)
  check(app.requestTransfer([remoteFile],toRemote:true,origin:.paste));let relayDialog=app.transferConfirmation!;relayDialog.destination.stringValue=remote.path;relayDialog.independent.state = .on;relayDialog.changeIndependent();relayDialog.form.speed.stringValue="0";relayDialog.apply();wait{app.transferConfirmation==nil && app.jobs.count==5}
  let relay=app.relayTransfers.last!;check(relay.download.speedLimit==0 && relay.upload.speedLimit==0 && relay.download.snapshot(site:site).overrideSpeedLimit==0 && relay.upload.snapshot(site:site).overrideSpeedLimit==0)
  app.transfers.isSuspended=false;wait{relay.download.finished && relay.upload.finished};check(!relay.download.failed && !relay.upload.failed)
  check(try Data(contentsOf:remote.appendingPathComponent("说明.txt"))==Data("line\r\nline\r\n".utf8))
  // Suppression is opt-in, channel-specific, and cancel does not save it.
  app.transfers.isSuspended=true;select();check(app.handleDrop([file],toRemote:true));let drag=app.transferConfirmation!;drag.suppress.state = .on;drag.apply();check(app.transferConfirmation==nil && !app.dragTransferOptionsEnabled && app.transferOptionsEnabled && defaults.bool(forKey:"confirmDragTransfers")==false)
  select();app.enqueue(true);check(app.transferConfirmation != nil);app.transferConfirmation!.cancel()
  check(errors.isEmpty && clients>=clientCount && !app.window.isVisible && !auth.isVisible)
  if CommandLine.arguments.count>1{
   let example=[DragFile(path:"/Users/demo/Documents/说明.txt",directory:false,size:2048,connection:nil),DragFile(path:"/Users/demo/Documents/config.json",directory:false,size:1536,connection:nil),DragFile(path:"/Users/demo/Documents/项目资料",directory:true,size:0,connection:nil)]
   let preview=TransferOptionsController(files:example,directory:"/srv/project/releases",toRemote:true,endpoint:"demo@example.com:22",preferences:original,presets:[try TransferPreset(id:UUID(),name:"文本与校验",preferences:presetPrefs)])
   preview.preset.selectItem(at:1);preview.pickPreset();preview.window!.contentView!.layoutSubtreeIfNeeded();try render(preview.window!,to:CommandLine.arguments[1]);preview.close()
  }
  print("PASS: hidden production App confirmation Cancel/closed/invalid/stale handling, 660/700 layouts, preset-only batch policy and persistent independent limit, async changed-target listing/conflicts and exact converted bytes, cancelled probe has no late submission, download/local-copy targets and binary bytes, separate drag suppression; own SFTP stdio, no auth/network/clipboard")
 }
}
