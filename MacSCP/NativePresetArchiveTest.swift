import Cocoa
@main struct NativePresetArchiveTests {
 static func check(_ value:Bool,file:StaticString = #file,line:UInt = #line){precondition(value,file:file,line:line)}
 static func main()throws{
  NSApplication.shared.setActivationPolicy(.prohibited)
  let root=FileManager.default.temporaryDirectory.appendingPathComponent("native-preset-archive-"+UUID().uuidString),suite="macscp-preset-archive-"+UUID().uuidString,defaults=UserDefaults(suiteName:suite)!
  try FileManager.default.createDirectory(at:root,withIntermediateDirectories:false);defer{try? FileManager.default.removeItem(at:root);defaults.removePersistentDomain(forName:suite)}
  let base=TransferPreferences(concurrency:2),changed=TransferPreferences(concurrency:5,kibibytesPerSecond:128,policy:TransferPolicy(include:"*.txt",verifyChecksum:true,text:TextTransferOptions(mode:.automatic,remote:.crlf,removeBOM:true)))
  var library=TransferPresetLibrary();let localID=try library.add(name:"代码",preferences:base);library.defaultPreferences=base;try library.save(defaults);defaults.set(try JSONEncoder().encode(base),forKey:"transferPreferences")
  var incoming=TransferPresetLibrary();let remoteID=try incoming.add(name:"代码",preferences:changed,rule:TransferPresetRule(enabled:true,host:"*.fixture.invalid"));_ = try incoming.add(name:"数据",preferences:TransferPreferences(concurrency:4));incoming.selectedID=remoteID;incoming.defaultPreferences=TransferPreferences(concurrency:6);incoming.automaticSelectionEnabled=false
  let data=try TransferPresetArchive.exportData(incoming,current:changed),oldData=defaults.data(forKey:TransferPresetLibrary.key)!,oldPrefs=defaults.data(forKey:"transferPreferences")!
  var network=0
  let app=App(defaults:defaults,dataDirectory:root.appendingPathComponent("profile"),initialLocalDirectory:root.path,automaticLogin:false,showsMainWindow:false,frameAutosaveName:nil,clientProvider:{_,_ in network+=1;throw SFTPError.message("unexpected network")})
  app.applicationDidFinishLaunching(Notification(name:NSApplication.didFinishLaunchingNotification));defer{app.transferSettingsWindow?.cancel();app.jobs=[];app.window.close()}
  let queued=TransferJob(up:true,source:"/fixture/source",destination:"/fixture/target",directory:false,size:0);queued.policy=TransferPolicy();queued.policyConfigured=true;app.jobs=[queued]
  app.transferSettings();let cancelled=app.transferSettingsWindow!,preview=try cancelled.beginImport(data)
  check(!preview.applyButton.isEnabled && !preview.window!.isVisible)
  preview.setChecked(0,true);preview.setChecked(1,true);preview.table.selectRowIndexes(IndexSet(integer:0),byExtendingSelection:false);preview.showDetails();check(preview.details.string.contains("本机原设置") && preview.details.string.contains("导入设置") && preview.details.string.contains("CRLF"))
  check(preview.details.string.contains("文件默认配置") && preview.details.string.contains("文件当前传输设置"))
  preview.search.stringValue="数据";preview.reload();check(preview.visible.count==1 && preview.selection.checked.count==2)
  preview.search.stringValue="";preview.reload()
  for size in [NSSize(width:820,height:720),NSSize(width:720,height:700)]{preview.window!.setContentSize(size);preview.window!.contentView!.layoutSubtreeIfNeeded();let bounds=preview.window!.contentView!.bounds
   for control in [preview.search,preview.defaults,preview.current,preview.applyButton,preview.details.enclosingScrollView!] as [NSView]{let rect=control.convert(control.bounds,to:preview.window!.contentView!);check(rect.minX>=0 && rect.maxX<=bounds.width+1 && rect.minY>=0 && rect.maxY<=bounds.height+1)}
   check(preview.table.enclosingScrollView!.frame.height>=150 && preview.details.frame.width<=preview.details.enclosingScrollView!.contentSize.width+1)
  }
  cancelled.apply();check(app.transferSettingsWindow === cancelled && defaults.data(forKey:TransferPresetLibrary.key)==oldData)
  preview.apply();check(cancelled.importPreview==nil && cancelled.library.preset(localID)?.preferences==changed && app.preferences==base && defaults.data(forKey:TransferPresetLibrary.key)==oldData)
  var exported:Data?;cancelled.exportSink={exported=$0};cancelled.exportFile();check(try TransferPresetArchive.decode(exported!).presets.count==2 && defaults.data(forKey:"transferPreferences")==oldPrefs)
  cancelled.cancel();check(defaults.data(forKey:TransferPresetLibrary.key)==oldData && app.preferences==base)
  app.transferSettings();let applied=app.transferSettingsWindow!,restore=try applied.beginImport(data);restore.selectAllCompatible();restore.defaults.state = .on;restore.current.state = .on;restore.optionsChanged();restore.apply();check(try applied.form.value()==changed)
  applied.apply();let saved=try TransferPresetLibrary.load(defaults);check(saved.presets.count==2 && saved.preset(localID)?.preferences==changed && saved.selectedID==localID && saved.defaultPreferences?.concurrency==6 && saved.automaticSelectionEnabled==false && app.preferences==changed && queued.policy.text==nil)
  // A closed preview cannot subsequently mutate the still-open parent.
  app.transferSettings();let parent=app.transferSettingsWindow!,closed=try parent.beginImport(data);closed.setChecked(0,true);closed.cancel();let before=parent.library;closed.apply();check(parent.library==before)
  let stale=try parent.beginImport(data);stale.setChecked(0,true);var external=try TransferPresetLibrary.load(defaults);_ = try external.add(name:"外部更改",preferences:base);try external.save(defaults);stale.apply();parent.apply();check(app.transferSettingsWindow === parent && parent.notice.textColor == .systemRed);parent.cancel()
  // Optional current restore does not happen without its checkbox.
  app.transferSettings();let view=app.transferSettingsWindow!,screen=try view.beginImport(data);screen.setChecked(0,true);screen.setAction(0,.copy);screen.table.selectRowIndexes(IndexSet(integer:0),byExtendingSelection:false);screen.showDetails();check(screen.details.string.contains("另存副本") && screen.current.state == .off)
  screen.window!.setContentSize(NSSize(width:820,height:720));screen.window!.contentView!.layoutSubtreeIfNeeded()
  if CommandLine.arguments.count>1{
   let window=screen.window!,content=window.contentView!,bounds=content.bounds,bitmap=content.bitmapImageRepForCachingDisplay(in:bounds)!;content.cacheDisplay(in:bounds,to:bitmap)
   let canvas=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:bitmap.pixelsWide,pixelsHigh:bitmap.pixelsHigh,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!,graphics=NSGraphicsContext(bitmapImageRep:canvas)!
   NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=graphics;window.effectiveAppearance.performAsCurrentDrawingAppearance{window.backgroundColor.setFill();NSBezierPath(rect:NSRect(origin:.zero,size:canvas.size)).fill();let snapshot=NSImage(size:bounds.size);snapshot.addRepresentation(bitmap);snapshot.draw(in:NSRect(origin:.zero,size:canvas.size),from:.zero,operation:.sourceOver,fraction:1)};NSGraphicsContext.restoreGraphicsState();try canvas.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:CommandLine.arguments[1]))
  }
  screen.cancel();view.cancel()
  let process=SSHConnection(arguments:["60"],helper:"/unused",executable:"/unused",command:"/bin/sleep");let auth=NSWindow(contentRect:NSRect(x:0,y:0,width:100,height:100),styleMask:[.titled],backing:.buffered,defer:false);auth.isReleasedWhenClosed=false
  defer{process.stop();auth.close();app.connections=[]}
  let site=Session(name:"fixture",host:"auto.fixture.invalid",user:"fixture",port:22,key:""),tab=ConnectionTab(site,"archive-fixture-only",process,auth,app.local.currentPath,defaults:defaults);tab.connected=true;app.connections=[tab];app.selectedTab=0;app.session=site;app.socket=tab.socket;app.remote.acceptPath("/srv/project")
  var autoLibrary=app.transferPresets;autoLibrary.automaticSelectionEnabled=true;autoLibrary.selectedID=nil;try app.commitTransferSettings(base,library:autoLibrary);app.reevaluateTransferPreset(force:true);check(app.automaticTransferPresetID==localID && app.effectiveTransferPreferences==changed)
  let newest=TransferPreferences(concurrency:7,policy:changed.policy);try incoming.update(remoteID,preferences:newest);let newData=try TransferPresetArchive.exportData(incoming,current:newest)
  app.transferSettings();let automatic=app.transferSettingsWindow!,update=try automatic.beginImport(newData);update.setChecked(0,true);update.apply();automatic.apply()
  check(app.preferences==base && app.automaticTransferPresetID==localID && app.effectiveTransferPreferences==newest && queued.policy.text==nil)
  let persisted=try JSONDecoder().decode(TransferPreferences.self,from:defaults.data(forKey:"transferPreferences")!);check(persisted==base)
  check(network==0 && !app.window.isVisible && !auth.isVisible)
  print("PASS: hidden preset import preview layouts/filter/check/action/details, two-level draft Cancel/Apply/export, explicit default/current restore, stable local IDs, no closed-preview application, concurrent stored change refusal, queued policy retained; no file panels, network, credentials or clipboard")
 }
}
