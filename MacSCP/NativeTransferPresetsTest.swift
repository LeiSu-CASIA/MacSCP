import Cocoa
@main struct NativeTransferPresetsTests {
 static func main()throws {
  NSApplication.shared.setActivationPolicy(.prohibited)
  let root=FileManager.default.temporaryDirectory.appendingPathComponent("macscp-presets-ui-"+UUID().uuidString),suite="macscp-presets-ui-"+UUID().uuidString,defaults=UserDefaults(suiteName:suite)!
  try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
  defer{try? FileManager.default.removeItem(at:root);defaults.removePersistentDomain(forName:suite)}
  let base=TransferPreferences(concurrency:2)
  defaults.set(try JSONEncoder().encode(base),forKey:"transferPreferences")
  var calls=0
  let app=App(defaults:defaults,dataDirectory:root.appendingPathComponent("profile"),initialLocalDirectory:root.path,automaticLogin:false,showsMainWindow:false,frameAutosaveName:nil,clientProvider:{_,_ in calls+=1;throw SFTPError.message("unexpected network")})
  app.applicationDidFinishLaunching(Notification(name:NSApplication.didFinishLaunchingNotification))
  defer{app.transferSettingsWindow?.cancel();app.window.close()}
  let configured=TransferPreferences(concurrency:5,kibibytesPerSecond:128,policy:TransferPolicy(include:"*.txt",exclude:"*.tmp",verifyChecksum:true))
  app.transferSettings();let cancelled=app.transferSettingsWindow!;app.transferSettings();precondition(app.transferSettingsWindow === cancelled)
  cancelled.form.load(configured);cancelled.name.stringValue="文档传输";cancelled.add()
  precondition(cancelled.library.presets.count==1 && defaults.object(forKey:TransferPresetLibrary.key)==nil && app.preferences==base)
  cancelled.cancel();precondition(app.transferSettingsWindow==nil && defaults.object(forKey:TransferPresetLibrary.key)==nil)
  app.transferSettings();let saved=app.transferSettingsWindow!
  saved.form.load(configured);saved.name.stringValue="文档传输";saved.add();saved.window!.contentView!.layoutSubtreeIfNeeded()
  for button in [saved.addButton,saved.updateButton,saved.renameButton,saved.deleteButton,saved.upButton,saved.downButton,saved.defaultButton,saved.resetButton,saved.applyButton,saved.cancelButton]{
   let rect=button.convert(button.bounds,to:saved.window!.contentView!);precondition(rect.minX>=0 && rect.maxX<=saved.window!.contentView!.bounds.width && rect.minY>=0 && rect.maxY<=saved.window!.contentView!.bounds.height,"preset control outside window")
  }
  saved.apply();precondition(app.transferSettingsWindow==nil && app.preferences==configured && app.transfers.maxConcurrentOperationCount==5)
  let library=try TransferPresetLibrary.load(defaults);precondition(library.presets.count==1 && library.defaultPreferences==base && library.selectedID != nil)
  precondition(app.transferPresetPicker.itemTitle(at:0).contains("文档传输"))
  let standard=app.transferPresetPicker.itemArray.first{$0.representedObject as? String=="default"}!
  app.selectTransferPreset(standard);precondition(app.preferences==base)
  let named=app.transferPresetPicker.itemArray.first{$0.representedObject as? String==library.presets[0].id.uuidString}!
  app.selectTransferPreset(named);precondition(app.preferences==configured)
  app.transferSettings();let stale=app.transferSettingsWindow!;var external=try TransferPresetLibrary.load(defaults);_ = try external.add(name:"外部设置",preferences:base);try external.save(defaults)
  let bytes=defaults.data(forKey:TransferPresetLibrary.key);stale.form.load(base);stale.apply()
  precondition(app.transferSettingsWindow === stale && app.preferences==configured && defaults.data(forKey:TransferPresetLibrary.key)==bytes && !stale.notice.stringValue.isEmpty);stale.cancel()
  let corrupt=Data("corrupt".utf8);defaults.set(corrupt,forKey:TransferPresetLibrary.key)
  app.transferSettings();let recovery=app.transferSettingsWindow!;precondition(!recovery.addButton.isEnabled && recovery.readError != nil)
  recovery.form.load(base);recovery.apply();precondition(TransferPresetLibrary.equivalent(app.preferences,base) && defaults.data(forKey:TransferPresetLibrary.key)==corrupt)
  app.transferSettings();let reset=app.transferSettingsWindow!;reset.confirmReset={true};reset.reset();precondition(defaults.data(forKey:TransferPresetLibrary.key)==corrupt)
  reset.apply();let resetLibrary=try TransferPresetLibrary.load(defaults);precondition(resetLibrary.presets.isEmpty)
  precondition(calls==0 && !app.window.isVisible && !saved.window!.isVisible)
  print("PASS: hidden preset UI layout, singleton, Cancel rollback, Apply/picker/default persistence, concurrent modification refusal and corrupt library preservation/reset; no login/network/Keychain")
 }
}
