import Cocoa
@main struct NativeSyncTimestampTests {
 static func check(_ value:Bool,file:StaticString = #file,line:UInt = #line){precondition(value,file:file,line:line)}
 static func refused(_ action:()throws->Void){do{try action();fatalError("invalid metadata queue accepted")}catch{}}
 static func views(_ root:NSView)->[NSView]{[root]+root.subviews.flatMap{views($0)}}
 static func main()throws {
  NSApplication.shared.setActivationPolicy(.prohibited)
  let options=SyncOptionsView(permitsUpload:true);check(options.operation.numberOfItems==3)
  options.size.state = .on;options.checksum.state = .on;options.cleanup.state = .on;options.operation.selectItem(at:2);options.changedOptions();options.sameSizeOnly.state = .on
  var settings=try options.settings();check(settings.comparison.fileMode == .timestamps && settings.comparison.timestampSameSizeOnly && !settings.cleanup && !settings.comparison.size && !settings.comparison.checksum && !settings.comparison.existingOnly)
  check(options.existingOnly.isHidden && !options.sameSizeOnly.isHidden && !options.cleanup.isEnabled && !options.checksum.isEnabled && !options.modificationTime.isEnabled && options.explanation.stringValue.contains("不传输内容"))
  options.direction.selectItem(at:2);options.changedDirection();options.operation.menu?.update();check(options.operation.item(at:1)?.isEnabled==false);settings=try options.settings();check(settings.direction == .both && settings.comparison.fileMode == .timestamps && options.operation.isEnabled)
  let restored=SyncOptionsView(permitsUpload:true,settings:settings);check(try restored.settings()==settings)
  let ftp=SyncOptionsView(permitsUpload:true,settings:settings,permitsTimestamps:false);check(ftp.operation.numberOfItems==2 && ftp.fileMode == .synchronize)
  let readonly=SyncOptionsView(permitsUpload:false,settings:settings,permitsTimestamps:false);check(readonly.mode == .download && readonly.operation.numberOfItems==2 && readonly.fileMode == .synchronize)
  let host=NSWindow(contentRect:NSRect(x:0,y:0,width:500,height:330),styleMask:[.titled],backing:.buffered,defer:false);host.isReleasedWhenClosed=false;host.contentView=options;options.layoutSubtreeIfNeeded();check(options.sameSizeOnly.frame.minX>=0 && options.sameSizeOnly.frame.maxY<=options.bounds.height && !host.isVisible);host.close()
  let fm=FileManager.default,root=fm.temporaryDirectory.appendingPathComponent("native-sync-timestamps-"+UUID().uuidString),local=root.appendingPathComponent("local"),remote=root.appendingPathComponent("remote")
  for dir in [local,remote]{try fm.createDirectory(at:dir,withIntermediateDirectories:true)}
  let suite="native-sync-timestamps-"+UUID().uuidString,defaults=UserDefaults(suiteName:suite)!
  defer{try? fm.removeItem(at:root);defaults.removePersistentDomain(forName:suite)}
  try settings.save(to:defaults);check(SyncSettings.load(from:defaults)==settings)
  try Data("source data".utf8).write(to:local.appendingPathComponent("file.txt"));try Data("keep target".utf8).write(to:remote.appendingPathComponent("file.txt"))
  try fm.setAttributes([.modificationDate:Date(timeIntervalSince1970:1700000010)],ofItemAtPath:local.appendingPathComponent("file.txt").path);try fm.setAttributes([.modificationDate:Date(timeIntervalSince1970:1800000030)],ofItemAtPath:remote.appendingPathComponent("file.txt").path)
  let client=try SFTPClient(command:"/usr/libexec/sftp-server",arguments:[]);defer{client.close()}
  let l=try SyncPlanner.local(local.path),r=try SyncPlanner.remote(remote.path,client:client),chosen=SyncSettings(comparison:SyncComparisonOptions(fileMode:.timestamps,timeTolerance:0))
  let rows=try SyncComparison.plannedCandidates(local:l,remote:r,settings:chosen),plan=try SyncTimestampPlan.prepare(rows[0],localRoot:local.path,remoteRoot:remote.path,client:client)
  var opened=0
  let app=App(defaults:defaults,dataDirectory:root.appendingPathComponent("profile"),initialLocalDirectory:local.path,automaticLogin:false,showsMainWindow:false,frameAutosaveName:nil,clientProvider:{_,_ in opened+=1;return try SFTPClient(command:"/usr/libexec/sftp-server",arguments:[])})
  app.applicationDidFinishLaunching(Notification(name:NSApplication.didFinishLaunchingNotification));app.transfers.isSuspended=true
  let ssh=SSHConnection(arguments:["60"],helper:"/unused",executable:"/unused",command:"/bin/sleep");defer{ssh.stop()}
  let auth=NSWindow(contentRect:NSRect(x:0,y:0,width:200,height:100),styleMask:[.titled],backing:.buffered,defer:false);auth.isReleasedWhenClosed=false
  let site=Session(name:"fixture",host:"example.invalid",user:"fixture",port:22,key:"");let tab=ConnectionTab(site,"timestamp-fixture",ssh,auth,local.path,defaults:defaults);tab.connected=true
  app.connections=[tab];app.selectedTab=0;app.session=site;app.socket=tab.socket
  let preview=app.makeSyncPreview(rows,localRoot:local.path,remoteRoot:remote.path,localSnapshot:l,remoteSnapshot:r,deletions:[:],site:site,socket:tab.socket,policy:TransferPolicy(),comparisonSummary:chosen.comparison.summary,timestampPlans:["file.txt":plan])
  preview.window!.contentView!.layoutSubtreeIfNeeded();check(preview.summary.stringValue.contains("1 项仅时间戳"))
  let versionButtons=views(preview.window!.contentView!).compactMap{$0 as? NSButton}.filter{$0.action == #selector(SyncPreviewController.useLocal) || $0.action == #selector(SyncPreviewController.useRemote)};check(versionButtons.count==2 && versionButtons.allSatisfy{$0.isEnabled && $0.title.contains("时间")})
  preview.table.selectRowIndexes(IndexSet(integer:0),byExtendingSelection:false)
  preview.useRemote();check(preview.candidates[0].upload==false);check(preview.table.selectedRowIndexes==IndexSet(integer:0))
  preview.useLocal();check(preview.candidates[0].upload==true);check(preview.table.selectedRowIndexes==IndexSet(integer:0))
  let column=preview.table.tableColumns.first{$0.identifier.rawValue=="local"}!,cell=preview.tableView(preview.table,viewFor:column,row:0) as! NSTableCellView
  check(cell.textField!.stringValue.contains("2023/") && cell.textField!.stringValue.hasSuffix(":30"))
  preview.apply();check(app.jobs.count==1 && opened==0 && !preview.window!.isVisible)
  let job=app.jobs[0];check(job.customOperation != nil && !job.retryAllowed && job.recoveryRecord()==nil && job.column("direction")=="远程时间")
  job.execute({});check(job.finished && !job.failed && job.transferredBytes==0 && opened==1)
  check(try client.attributes(remote.appendingPathComponent("file.txt").path)?.modified==1700000010 && Data(contentsOf:remote.appendingPathComponent("file.txt"))==Data("keep target".utf8))
  try app.enqueueSync(rows,localRoot:local.path,remoteRoot:remote.path,localSnapshot:l,remoteSnapshot:r,deletions:[:],site:site,socket:tab.socket,policy:TransferPolicy(),timestampPlans:["file.txt":plan])
  app.jobs.last!.execute({});check(app.jobs.last!.failed && opened==2)
  app.queueTable.selectRowIndexes(IndexSet(integer:1),byExtendingSelection:false);app.retrySelected();check(opened==2 && app.status.stringValue.contains("时间戳") && app.status.stringValue.contains("重新比较"))
  let count=app.jobs.count
  refused{try app.enqueueSync(rows,localRoot:local.path,remoteRoot:remote.path,localSnapshot:l,remoteSnapshot:r,deletions:[:],site:site,socket:tab.socket,policy:TransferPolicy())}
  refused{try app.enqueueSync(rows,localRoot:local.path+"/different",remoteRoot:remote.path,localSnapshot:l,remoteSnapshot:r,deletions:[:],site:site,socket:tab.socket,policy:TransferPolicy(),timestampPlans:["file.txt":plan])}
  var wrong=site;wrong.protocolKind = .ftp
  refused{try app.enqueueSync(rows,localRoot:local.path,remoteRoot:remote.path,localSnapshot:l,remoteSnapshot:r,deletions:[:],site:wrong,socket:tab.socket,policy:TransferPolicy(),timestampPlans:["file.txt":plan])}
  check(app.jobs.count==count && opened==2)
  try fm.setAttributes([.modificationDate:Date(timeIntervalSince1970:1800000030)],ofItemAtPath:remote.appendingPathComponent("file.txt").path)
  let dl=try SyncPlanner.local(local.path),dr=try SyncPlanner.remote(remote.path,client:client)
  var download=try SyncComparison.plannedCandidates(local:dl,remote:dr,settings:chosen)
  let down=try SyncTimestampPlan.prepare(download[0],localRoot:local.path,remoteRoot:remote.path,client:client);check(down.candidate.upload==true);check(SyncComparison.resolve(&download[0],upload:false))
  try app.enqueueSync(download,localRoot:local.path,remoteRoot:remote.path,localSnapshot:dl,remoteSnapshot:dr,deletions:[:],site:site,socket:tab.socket,policy:TransferPolicy(),timestampPlans:["file.txt":down])
  app.jobs.last!.execute({});check(app.jobs.last!.finished && !app.jobs.last!.failed && app.jobs.last!.transferredBytes==0 && app.jobs.last!.column("direction")=="本地时间")
  check(try Data(contentsOf:local.appendingPathComponent("file.txt"))==Data("source data".utf8))
  check(!app.window.isVisible && !auth.isVisible)
  app.transfers.cancelAllOperations();app.jobs=[];app.connections=[];app.window.close();auth.close()
  print("PASS: hidden timestamp controls/SFTP-only mode/same-size/both/settings, second-precision preview and explicit per-row time-source reversal, real production App metadata queue changes times with zero bytes, stale/missing/cross-root/protocol plans rejected and no blind retry/recovery; no visible auth or network server")
 }
}
