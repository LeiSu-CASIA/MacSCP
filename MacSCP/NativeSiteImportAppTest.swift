import Cocoa
@main struct NativeSiteImportAppTests {
 static func main()throws {
  NSApplication.shared.setActivationPolicy(.prohibited)
  let fm=FileManager.default,root=fm.temporaryDirectory.appendingPathComponent("native-site-import-app-"+UUID().uuidString)
  try fm.createDirectory(at:root,withIntermediateDirectories:true)
  let suite="macscp-site-import-app-"+UUID().uuidString
  let isolated=UserDefaults(suiteName:suite)!
  defer{try? fm.removeItem(at:root);isolated.removePersistentDomain(forName:suite)}
  var clientCalls=0
  let app=App(defaults:isolated,dataDirectory:root.appendingPathComponent("profile"),initialLocalDirectory:root.path,automaticLogin:false,showsMainWindow:false,frameAutosaveName:nil,clientProvider:{_,_ in clientCalls+=1;throw SFTPError.message("unexpected network access")})
  app.applicationDidFinishLaunching(Notification(name:NSApplication.didFinishLaunchingNotification))
  let data=Data("[Sessions\\a]\nHostName=a.example\nUserName=test\n[Sessions\\b]\nHostName=b.example\nUserName=test".utf8)
  let plan=try SiteImportPlan.read(data,fileExtension:"ini"),store=app.siteStore!
  let controller=app.makeSiteImportController(plan,repository:store)
  precondition(app.siteImportWindows.count==1 && !controller.window!.isVisible)
  controller.selection.setChecked(1,true);controller.importSelected()
  precondition(store.sites.map(\.host)==["b.example"] && app.sitePicker.numberOfItems==2)
  precondition(app.sitePicker.itemTitles.last!.contains("b.example") && app.status.stringValue.contains("已导入 1"))
  controller.selection.setChecked(0,true);controller.importSelected()
  precondition(store.sites.count==2 && app.sitePicker.numberOfItems==3)
  precondition(app.connections.isEmpty && app.jobs.isEmpty && clientCalls==0 && app.auth==nil && !app.window.isVisible)
  controller.close();precondition(app.siteImportWindows.isEmpty)
  let saved=try SiteStore(url:store.url);precondition(saved.sites==store.sites)
  app.window.close()
  print("PASS: actual hidden App opens preview without showing it, imports only checked real INI rows, refreshes site picker/status, saves/reloads selected sites and releases closed preview; no login/authentication/transfer or client connection attempted")
 }
}
