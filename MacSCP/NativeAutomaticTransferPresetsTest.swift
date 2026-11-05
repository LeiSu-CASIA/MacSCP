import Cocoa
@main struct NativeAutomaticTransferPresetsTests {
 static func check(_ value:Bool,file:StaticString = #file,line:UInt = #line){precondition(value,file:file,line:line)}
 static func wait(file:StaticString = #file,line:UInt = #line,_ condition:()->Bool){let until=Date().addingTimeInterval(20);while !condition(),Date()<until{RunLoop.current.run(until:Date().addingTimeInterval(0.01))};check(condition(),file:file,line:line)}
 static func render(_ window:NSWindow,to path:String)throws{
  let view=window.contentView!;view.layoutSubtreeIfNeeded();let bounds=view.bounds,bitmap=view.bitmapImageRepForCachingDisplay(in:view.bounds)!;view.cacheDisplay(in:bounds,to:bitmap)
  let canvas=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:bitmap.pixelsWide,pixelsHigh:bitmap.pixelsHigh,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!,graphics=NSGraphicsContext(bitmapImageRep:canvas)!
  NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=graphics
  window.effectiveAppearance.performAsCurrentDrawingAppearance{window.backgroundColor.setFill();NSBezierPath(rect:NSRect(origin:.zero,size:canvas.size)).fill();let snapshot=NSImage(size:bounds.size);snapshot.addRepresentation(bitmap);snapshot.draw(in:NSRect(origin:.zero,size:canvas.size),from:.zero,operation:.sourceOver,fraction:1)}
  NSGraphicsContext.restoreGraphicsState();try canvas.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:path))
 }
 static func main()throws {
  NSApplication.shared.setActivationPolicy(.prohibited)
  let fm=FileManager.default,root=fm.temporaryDirectory.appendingPathComponent("macscp-auto-presets-"+UUID().uuidString).resolvingSymlinksInPath(),suite="macscp-auto-presets-"+UUID().uuidString,defaults=UserDefaults(suiteName:suite)!
  for dir in ["local/a/payload","local/b/payload","remote/a","remote/b","remote/other"]{try fm.createDirectory(at:root.appendingPathComponent(dir),withIntermediateDirectories:true)}
  defer{try? fm.removeItem(at:root);defaults.removePersistentDomain(forName:suite)}
  for dir in ["local/a/payload","local/b/payload"]{for name in ["keep.txt","table.csv"]{try Data(name.utf8).write(to:root.appendingPathComponent(dir+"/"+name))}}
  let probe=try SFTPClient(command:"/usr/libexec/sftp-server",arguments:[]);let remote=try probe.canonical(root.appendingPathComponent("remote").path);probe.close()
  let local=root.appendingPathComponent("local").resolvingSymlinksInPath().path,manual=TransferPreferences(concurrency:2)
  let txt=TransferPreferences(concurrency:3,kibibytesPerSecond:128,policy:TransferPolicy(include:"*.txt",verifyChecksum:true)),csv=TransferPreferences(concurrency:4,kibibytesPerSecond:256,policy:TransferPolicy(include:"*.csv",verifyChecksum:true))
  var library=TransferPresetLibrary();library.defaultPreferences=manual
  let textID=try library.add(name:"文本项目",preferences:txt,rule:TransferPresetRule(enabled:true,host:"auto.invalid",user:"fixture",local:local+"/a/",remote:remote+"/a/"))
  let csvID=try library.add(name:"数据项目",preferences:csv,rule:TransferPresetRule(enabled:true,host:"auto.invalid",remote:remote+"/b/"))
  library.selectedID=nil;try library.save(defaults);defaults.set(try JSONEncoder().encode(manual),forKey:"transferPreferences");let original=defaults.data(forKey:"transferPreferences")!,originalLibrary=defaults.data(forKey:TransferPresetLibrary.key)!
  var clients=0
  let app=App(defaults:defaults,dataDirectory:root.appendingPathComponent("profile"),initialLocalDirectory:local+"/a",automaticLogin:false,showsMainWindow:false,frameAutosaveName:nil,clientProvider:{_,_ in clients+=1;return try SFTPClient(command:"/usr/libexec/sftp-server",arguments:[])})
  app.applicationDidFinishLaunching(Notification(name:NSApplication.didFinishLaunchingNotification));app.transfers.isSuspended=true
  let progress=SSHConnection(arguments:["300"],helper:"/unused",executable:"/unused",command:"/bin/sleep")
  let auth=NSWindow(contentRect:NSRect(x:0,y:0,width:100,height:100),styleMask:[.titled],backing:.buffered,defer:false);auth.isReleasedWhenClosed=false
  let site=Session(name:"自动匹配测试",host:"auto.invalid",user:"fixture",port:22,key:"")
  let tab=ConnectionTab(site,"auto-fixture-only",progress,auth,local+"/a",defaults:defaults);tab.connected=true
  defer{app.transferSettingsWindow?.cancel();app.transfers.isSuspended=false;for job in app.jobs where !job.finished{job.cancel()};app.transfers.refresh();progress.stop();auth.close();app.window.close()}
  app.connections=[tab];app.selectedTab=0;app.session=site;app.socket=tab.socket;app.remote.acceptPath(remote+"/a");app.refreshConnectionPresentation()
  check(app.automaticTransferPresetID==textID && app.effectiveTransferPreferences==txt && app.preferences==manual && clients==0)
  check(defaults.data(forKey:"transferPreferences")==original && defaults.data(forKey:TransferPresetLibrary.key)==originalLibrary)
  check(app.transferPresetPicker.itemTitle(at:0).contains("自动 · 文本项目"))
  app.remote.path.stringValue=remote+"/missing";app.loadRemote(origin:.passive);wait{!app.browsing};check(app.remote.currentPath==remote+"/a" && app.automaticTransferPresetID==textID);app.remote.path.stringValue=remote+"/a"
  // A real upload captures the rule of its original context while paused.
  let first=TransferJob(up:true,source:local+"/a/payload",destination:remote+"/a/payload",directory:true,size:0);first.factory={try SFTPClient(command:"/usr/libexec/sftp-server",arguments:[])};app.jobs.append(first);app.schedule(first)
  check(first.policy==txt.filePolicy && !first.finished)
  let standard=app.transferPresetPicker.itemArray.first{$0.representedObject as? String=="default"}!
  app.selectTransferPreset(standard);app.reevaluateTransferPreset();check(app.automaticTransferPresetID==nil && app.effectiveTransferPreferences==manual)
  app.local.path.stringValue=local+"/b";app.loadLocal();check(app.automaticTransferPresetID==nil)
  app.remote.path.stringValue=remote+"/b";app.loadRemote();wait{!app.browsing && app.remote.currentPath==remote+"/b"}
  check(app.automaticTransferPresetID==csvID && app.effectiveTransferPreferences==csv && first.policy==txt.filePolicy)
  let second=TransferJob(up:true,source:local+"/b/payload",destination:remote+"/b/payload",directory:true,size:0);second.factory={try SFTPClient(command:"/usr/libexec/sftp-server",arguments:[])};app.jobs.append(second);app.schedule(second);check(second.policy==csv.filePolicy)
  app.transfers.isSuspended=false;app.transfers.refresh();wait{first.finished && second.finished && !first.isExecuting && !second.isExecuting && !app.transfers.contains(first.id) && !app.transfers.contains(second.id)}
  check(!first.failed && !second.failed && fm.fileExists(atPath:remote+"/a/payload/keep.txt") && !fm.fileExists(atPath:remote+"/a/payload/table.csv"))
  check(fm.fileExists(atPath:remote+"/b/payload/table.csv") && !fm.fileExists(atPath:remote+"/b/payload/keep.txt"))
  // Passive refresh of the same context must not undo an explicit manual override.
  app.selectTransferPreset(standard);app.remote.path.stringValue=remote+"/b";app.loadRemote(origin:.passive);wait{!app.browsing};check(app.automaticTransferPresetID==nil)
  app.remote.path.stringValue=remote+"/a";app.loadRemote();wait{!app.browsing};check(app.automaticTransferPresetID==nil) // local b fails text condition
  app.local.path.stringValue=local+"/a";app.loadLocal();check(app.automaticTransferPresetID==textID)
  app.toggleAutomaticTransferPresets();check(app.transferPresets.automaticSelectionEnabled==false && app.automaticTransferPresetID==nil && app.effectiveTransferPreferences==manual)
  app.toggleAutomaticTransferPresets();check(app.automaticTransferPresetID==textID)
  // Rule sheet edits stay in the parent draft; cancellation never persists them.
  app.transferSettings();let parent=app.transferSettingsWindow!;parent.editRule();let editor=parent.ruleEditor!
  editor.window!.contentView!.layoutSubtreeIfNeeded();editor.useCurrent();let exact=try editor.value();check(try exact.matches(app.transferPresetContext!))
  editor.host.stringValue="[";editor.apply();check(parent.ruleEditor === editor && editor.notice.textColor == .systemRed)
  editor.useCurrent();editor.enabled.state = .off;editor.apply();check(parent.ruleEditor==nil && parent.library.preset(textID)?.rule?.enabled==false)
  let beforeCancel=defaults.data(forKey:TransferPresetLibrary.key);parent.cancel();check(defaults.data(forKey:TransferPresetLibrary.key)==beforeCancel && app.automaticTransferPresetID==textID)
  app.transferSettings();let applied=app.transferSettingsWindow!;applied.editRule();applied.ruleEditor!.useCurrent();applied.ruleEditor!.apply();applied.apply()
  let storedManual=try JSONDecoder().decode(TransferPreferences.self,from:defaults.data(forKey:"transferPreferences")!);check(TransferPresetLibrary.equivalent(storedManual,manual) && app.automaticTransferPresetID==textID && app.preferences==manual)
  app.transferSettings();let preview=app.transferSettingsWindow!;preview.editRule();let shown=preview.ruleEditor!;shown.useCurrent()
  for control in [shown.host,shown.user,shown.local,shown.remote]{check(control.frame.minX>=0 && control.frame.maxX<=650 && control.frame.minY>=0 && control.frame.maxY<=390)}
  if CommandLine.arguments.count>1{shown.local.stringValue="/Users/demo/Documents/project";shown.remote.stringValue="/srv/project/";try render(shown.window!,to:CommandLine.arguments[1]);if CommandLine.arguments.count>2{try render(preview.window!,to:CommandLine.arguments[2])}}
  shown.cancel();preview.cancel()
  // Disconnecting and changing session discard only the automatic overlay.
  let other=ConnectionTab(Session(name:"其他站点",host:"elsewhere.invalid",user:"fixture",port:22,key:""),"other-fixture",progress,auth,local+"/a",defaults:defaults);other.connected=true;other.remotePath=remote+"/a";app.connections.append(other);app.stashTab();app.activateTab(1);wait{!app.browsing};check(app.automaticTransferPresetID==nil && app.effectiveTransferPreferences==manual)
  app.activateTab(0);wait{!app.browsing};check(app.automaticTransferPresetID==textID)
  app.transferSettings();let removed=app.transferSettingsWindow!;removed.remove();removed.apply();check(app.automaticTransferPresetID==nil && app.preferences==manual && app.transferPresets.preset(textID)==nil)
  tab.connected=false;app.refreshConnectionPresentation();check(app.automaticTransferPresetID==nil && app.effectiveTransferPreferences==manual)
  check(!app.window.isVisible && !auth.isVisible && !shown.window!.isVisible)
  print("PASS: production App auto selection on accepted local/remote paths and session switches, manual override survives passive refresh, no-match/disconnect restores manual settings, toggle state/persistence, queue policy capture and actual filtered/checksummed SFTP uploads, hidden rule sheet validation/Current/cancel; own stdio server only")
 }
}
