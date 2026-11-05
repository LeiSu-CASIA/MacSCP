import Cocoa
@main struct NativeFTPImportTests {
 static func main()throws{
  NSApplication.shared.setActivationPolicy(.prohibited)
  let fm=FileManager.default,root=fm.temporaryDirectory.appendingPathComponent("native-ftp-import-"+UUID().uuidString);try fm.createDirectory(at:root,withIntermediateDirectories:true);defer{try? fm.removeItem(at:root)}
  let suite="native-ftp-import-"+UUID().uuidString,defaults=UserDefaults(suiteName:suite)!;defer{defaults.removePersistentDomain(forName:suite)}
  var connections=0;let app=App(defaults:defaults,dataDirectory:root.appendingPathComponent("profile"),initialLocalDirectory:root.path,automaticLogin:false,showsMainWindow:false,frameAutosaveName:nil,clientProvider:{_,_ in connections+=1;throw SFTPError.message("unexpected connection")});app.applicationDidFinishLaunching(Notification(name:NSApplication.didFinishLaunchingNotification))
  let source="[Sessions\\old-ssl]\nHostName=ssl.example\nUserName=demo\nFSProtocol=5\nFtps=2\nTimeout=42\nFtpUseMlsd=off\nPasswordPlain=private-not-imported\n[Sessions\\client-cert]\nHostName=blocked.example\nFSProtocol=5\nFtps=3\nTlsCertificateFile=C:%5Cclient.pem\n"
  let plan=try SiteImportPlan.read(Data(source.utf8),fileExtension:"ini"),controller=app.makeSiteImportController(plan,repository:app.siteStore!)
  controller.window!.contentView!.layoutSubtreeIfNeeded();precondition(!controller.importButton.isEnabled && !controller.window!.isVisible)
  controller.table.selectRowIndexes(IndexSet(integer:0),byExtendingSelection:false);controller.showDetails();precondition(controller.details.string.contains("AUTH SSL") && controller.details.string.contains("42") && controller.details.string.contains("仅 LIST") && !controller.details.string.contains("private-not-imported"))
  if CommandLine.arguments.count>1{let window=controller.window!;window.appearance=NSAppearance(named:.aqua);let view=window.contentView!;view.layoutSubtreeIfNeeded();if let bitmap=view.bitmapImageRepForCachingDisplay(in:view.bounds){view.cacheDisplay(in:view.bounds,to:bitmap);let canvas=NSImage(size:view.bounds.size);canvas.lockFocus();NSColor.windowBackgroundColor.setFill();view.bounds.fill();let image=NSImage(size:view.bounds.size);image.addRepresentation(bitmap);image.draw(in:view.bounds);canvas.unlockFocus();if let data=canvas.tiffRepresentation,let png=NSBitmapImageRep(data:data)?.representation(using:.png,properties:[:]){try png.write(to:URL(fileURLWithPath:CommandLine.arguments[1]))}}}
  let blocked=controller.tableView(controller.table,viewFor:controller.table.tableColumns[0],row:1) as! NSButton;precondition(!blocked.isEnabled)
  controller.selectAllEligible();precondition(controller.selection.checked==[0]);controller.importSelected();precondition(app.siteStore!.sites.count==1 && app.sitePicker.itemTitles.last!.contains("ftpsExplicit"))
  let site=app.siteStore!.sites[0],form=ConnectionForm(store:app.siteStore!,selected:site,localPath:root.path);precondition(form.fileProtocol == .ftpsExplicit && form.password.stringValue.isEmpty && form.write.state == .off)
  precondition(form.advancedFTP.timeout.stringValue=="42" && form.advancedFTP.listing.titleOfSelectedItem=="仅 LIST" && form.advancedFTP.authentication.indexOfSelectedItem==1)
  form.advancedFTP.listing.selectItem(at:1);form.advancedFTP.timeout.stringValue="19";form.advancedFTP.authentication.selectItem(at:0);form.ftpAdvanced=try form.advancedFTP.value(base:form.ftpAdvanced)
  let changed=try form.value(localPath:root.path);precondition(changed.ftpSettings.listingMode == .machineOnly && changed.ftpSettings.connectTimeout==19 && !changed.ftpSettings.prefersSSLAuth && !changed.ftpSettings.allowNonAtomicWrites)
  form.advancedFTP.timeout.stringValue="601";do{_ = try form.advancedFTP.value(base:form.ftpAdvanced);fatalError("invalid timeout")}catch{}
  precondition(connections==0 && app.connections.isEmpty && app.jobs.isEmpty && !app.window.isVisible);controller.close();app.window.close()
  print("PASS: hidden actual App FTP INI preview/import, SSL order/list mode/timeout details, client-certificate row disabled, selected-only save, login form retains advanced settings and empty password, validated edits, no login/network/window")
 }
}
