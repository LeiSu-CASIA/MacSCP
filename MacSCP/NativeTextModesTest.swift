import Cocoa
@main struct NativeTextModesTests {
 static func check(_ value:Bool,file:StaticString = #file,line:UInt = #line){precondition(value,file:file,line:line)}
 static func main()throws{
  NSApplication.shared.setActivationPolicy(.prohibited)
  let root=FileManager.default.temporaryDirectory.appendingPathComponent("native-text-mode-"+UUID().uuidString),suite="macscp-text-mode-"+UUID().uuidString,defaults=UserDefaults(suiteName:suite)!
  try FileManager.default.createDirectory(at:root,withIntermediateDirectories:false);defer{try? FileManager.default.removeItem(at:root);defaults.removePersistentDomain(forName:suite)}
  let options=TextTransferOptions(mode:.automatic,mask:"*.txt;*.csv",remote:.crlf,local:.lf,removeBOM:true,removeEOF:true),policy=TransferPolicy(verifyChecksum:true,text:options),value=TransferPreferences(concurrency:4,kibibytesPerSecond:64,policy:policy)
  let form=TextTransferOptionsView(options);check(try form.value()==options);check(form.mask.isEnabled && form.bom.isEnabled)
  for control in [form.mode,form.mask,form.remote,form.local,form.bom,form.eof] as [NSView]{check(control.frame.width>200 && control.frame.minY>=0 && control.frame.maxY<=275)}
  form.mode.selectItem(at:0);form.update();check(!form.mask.isEnabled && !form.remote.isEnabled && !form.bom.isEnabled)
  form.mode.selectItem(at:2);form.update();check(form.mask.isEnabled)
  let settings=TransferSettingsView(preferences:value);check(try settings.value()==value && settings.modeButton.title.contains("自动"));settings.load(TransferPreferences());check(try settings.value().filePolicy.text==nil)
  var network=0
  let app=App(defaults:defaults,dataDirectory:root.appendingPathComponent("profile"),initialLocalDirectory:root.path,automaticLogin:false,showsMainWindow:false,frameAutosaveName:nil,clientProvider:{_,_ in network+=1;throw SFTPError.message("unexpected network")})
  app.applicationDidFinishLaunching(Notification(name:NSApplication.didFinishLaunchingNotification));defer{app.transferSettingsWindow?.cancel();app.window.close()}
  let old=TransferJob(up:true,source:"/fixture/source",destination:"/fixture/target",directory:false,size:0);old.policy=TransferPolicy();old.policyConfigured=true;app.jobs=[old]
  app.transferSettings();let panel=app.transferSettingsWindow!;panel.form.load(value);panel.name.stringValue="Windows 文本";panel.add();panel.apply();check(app.preferences==value && old.policy.text==nil)
  let saved=try TransferPresetLibrary.load(defaults);check(saved.presets.first?.preferences.filePolicy.text==options)
  let binary=app.transferPresetPicker.itemArray.first{$0.action == #selector(App.selectTransferMode) && $0.representedObject as? String=="binary"}!
  app.selectTransferMode(binary);check(app.effectiveTransferPreferences.filePolicy.text?.mode == .binary && app.transferPresets.selectedID==nil && old.policy.text==nil)
  let automatic=app.transferPresetPicker.itemArray.first{$0.action == #selector(App.selectTransferMode) && $0.representedObject as? String=="automatic"}!;app.selectTransferMode(automatic);check(app.effectiveTransferPreferences.filePolicy.text==options)
  let window=NSWindow(contentRect:NSRect(x:0,y:0,width:590,height:315),styleMask:[.titled],backing:.buffered,defer:false);window.isReleasedWhenClosed=false;window.appearance=NSAppearance(named:.aqua);form.frame.origin=NSPoint(x:20,y:20);window.contentView!.addSubview(form)
  if CommandLine.arguments.count>1{
   let view=window.contentView!,bounds=view.bounds,bitmap=view.bitmapImageRepForCachingDisplay(in:view.bounds)!;view.cacheDisplay(in:bounds,to:bitmap)
   let canvas=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:bitmap.pixelsWide,pixelsHigh:bitmap.pixelsHigh,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!,graphics=NSGraphicsContext(bitmapImageRep:canvas)!
   NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=graphics
   window.effectiveAppearance.performAsCurrentDrawingAppearance{window.backgroundColor.setFill();NSBezierPath(rect:NSRect(origin:.zero,size:canvas.size)).fill();let snapshot=NSImage(size:bounds.size);snapshot.addRepresentation(bitmap);snapshot.draw(in:NSRect(origin:.zero,size:canvas.size),from:.zero,operation:.sourceOver,fraction:1)}
   NSGraphicsContext.restoreGraphicsState();try canvas.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:CommandLine.arguments[1]))
  }
  check(!window.isVisible && !app.window.isVisible && network==0);window.close();app.jobs=[]
  print("PASS: hidden text mode controls/layout/dependent enable state, settings/preset/legacy round trip, quick mode selection retains text options, old queued rules unchanged; no connection or password prompt")
 }
}
