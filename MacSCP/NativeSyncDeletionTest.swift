import Cocoa
@main struct NativeSyncDeletionTests {
 static func check(_ value:Bool,file:StaticString = #file,line:UInt = #line){precondition(value,file:file,line:line)}
 static func refused(_ action:()throws->Void){do{try action();fatalError("invalid sync accepted")}catch{}}
 static func main()throws {
  NSApplication.shared.setActivationPolicy(.prohibited)
  let fm=FileManager.default,root=fm.temporaryDirectory.appendingPathComponent("native-sync-deletion-"+UUID().uuidString),local=root.appendingPathComponent("local"),remote=root.appendingPathComponent("remote"),bin=root.appendingPathComponent("test-recycle")
  for dir in [local,remote,bin]{try fm.createDirectory(at:dir,withIntermediateDirectories:true)}
  let suite="native-sync-deletion-"+UUID().uuidString,defaults=UserDefaults(suiteName:suite)!
  defer{try? fm.removeItem(at:root);defaults.removePersistentDomain(forName:suite)}
  let options=SyncOptionsView(permitsUpload:true)
  check(!options.deleteExtraneous && options.mode == .upload && options.cleanup.state == .off)
  options.cleanup.state = .on;check(options.deleteExtraneous)
  options.direction.selectItem(at:2);options.changedDirection();check(!options.deleteExtraneous && !options.cleanup.isEnabled && options.cleanup.state == .off)
  options.direction.selectItem(at:1);options.changedDirection();check(options.cleanup.isEnabled && !options.deleteExtraneous && options.mode == .download)
  let readOnly=SyncOptionsView(permitsUpload:false);check(readOnly.mode == .download && readOnly.direction.numberOfItems==1 && !readOnly.deleteExtraneous)

  try Data("remove".utf8).write(to:remote.appendingPathComponent("obsolete.txt"))
  let client=try SFTPClient(command:"/usr/libexec/sftp-server",arguments:[]);defer{client.close()}
  let l=try SyncPlanner.local(local.path),r=try SyncPlanner.remote(remote.path,client:client)
  let candidates=SyncComparison.candidates(local:l,remote:r,direction:.upload,deleteExtraneous:true)
  let plan=try SyncDeletionPlan.prepare(candidates[0],localRoot:local.path,remoteRoot:remote.path,localSnapshot:l,remoteSnapshot:r,client:client)
  let ui=SyncPreviewController(candidates:candidates,context:"隔离测试目录")
  ui.window!.contentView!.layoutSubtreeIfNeeded();check(!ui.window!.isVisible && ui.summary.stringValue.contains("1 项清理"))
  let actionColumn=ui.table.tableColumns.first{$0.identifier.rawValue=="action"}!
  let actionCell=ui.tableView(ui.table,viewFor:actionColumn,row:0) as! NSTableCellView
  actionCell.frame=NSRect(x:0,y:0,width:actionColumn.width,height:27);actionCell.layoutSubtreeIfNeeded()
  let label=actionCell.textField!
  check(label.frame.minX>=0 && label.frame.maxX<=actionCell.bounds.width && label.frame.width>100)
  ui.window!.setContentSize(NSSize(width:800,height:500));ui.window!.contentView!.layoutSubtreeIfNeeded()
  check(ui.window!.contentView!.frame.width<=801 && ui.table.enclosingScrollView!.hasHorizontalScroller)
  ui.window!.setContentSize(NSSize(width:1040,height:620));ui.window!.contentView!.layoutSubtreeIfNeeded()
  check(label.textColor == .systemRed && label.stringValue.contains("永久"))
  ui.table.selectRowIndexes(IndexSet(integer:0),byExtendingSelection:false);ui.useRemote();check(ui.candidates[0].deletion && ui.candidates[0].upload==true)
  var confirmations=0,applied=0
  ui.confirmDeletion={rows in confirmations+=1;check(rows.count==1 && rows[0].deletion);return false};ui.onApply={_ in applied+=1}
  ui.apply();check(confirmations==1 && applied==0 && fm.fileExists(atPath:remote.appendingPathComponent("obsolete.txt").path))
  ui.selectNone();ui.apply();check(confirmations==1 && applied==0)
  ui.selectExecutable();ui.confirmDeletion={_ in confirmations+=1;return true};ui.apply();check(confirmations==2 && applied==1)

  var opened=0
  let app=App(defaults:defaults,dataDirectory:root.appendingPathComponent("profile"),initialLocalDirectory:local.path,automaticLogin:false,showsMainWindow:false,frameAutosaveName:nil,clientProvider:{_,_ in opened+=1;return try SFTPClient(command:"/usr/libexec/sftp-server",arguments:[])})
  app.applicationDidFinishLaunching(Notification(name:NSApplication.didFinishLaunchingNotification));app.transfers.isSuspended=true
  let ssh=SSHConnection(arguments:["60"],helper:"/unused",executable:"/unused",command:"/bin/sleep");defer{ssh.stop()}
  let auth=NSWindow(contentRect:NSRect(x:0,y:0,width:200,height:100),styleMask:[.titled],backing:.buffered,defer:false);auth.isReleasedWhenClosed=false
  let site=Session(name:"fixture",host:"example.invalid",user:"fixture",port:22,key:"")
  let tab=ConnectionTab(site,"sync-fixture-only",ssh,auth,local.path,defaults:defaults);tab.connected=true
  app.connections=[tab];app.selectedTab=0;app.session=site;app.socket=tab.socket
  let preview=app.makeSyncPreview(candidates,localRoot:local.path,remoteRoot:remote.path,localSnapshot:l,remoteSnapshot:r,deletions:["obsolete.txt":plan],site:site,socket:tab.socket,policy:TransferPolicy())
  preview.confirmDeletion={_ in true};preview.apply()
  check(app.jobs.count==1 && opened==0 && !preview.window!.isVisible)
  let job=app.jobs[0];check(job.customOperation != nil && !job.retryAllowed && job.recoveryRecord()==nil && job.column("direction")=="删除远程")
  job.execute({});check(job.finished && !job.failed && opened==1 && !fm.fileExists(atPath:remote.appendingPathComponent("obsolete.txt").path))
  try app.enqueueSync(candidates,localRoot:local.path,remoteRoot:remote.path,localSnapshot:l,remoteSnapshot:r,deletions:["obsolete.txt":plan],site:site,socket:tab.socket,policy:TransferPolicy())
  app.jobs.last!.execute({});check(app.jobs.last!.failed && opened==2)
  app.queueTable.selectRowIndexes(IndexSet(integer:1),byExtendingSelection:false);app.retrySelected();check(opened==2 && app.status.stringValue.contains("重新比较"))
  let originalCount=app.jobs.count
  refused{try app.enqueueSync(candidates,localRoot:local.path,remoteRoot:remote.path,localSnapshot:l,remoteSnapshot:r,deletions:[:],site:site,socket:tab.socket,policy:TransferPolicy())};check(app.jobs.count==originalCount)
  tab.connected=false
  refused{try app.enqueueSync(candidates,localRoot:local.path,remoteRoot:remote.path,localSnapshot:l,remoteSnapshot:r,deletions:["obsolete.txt":plan],site:site,socket:tab.socket,policy:TransferPolicy())};check(app.jobs.count==originalCount)
  tab.connected=true

  try fm.createDirectory(at:local.appendingPathComponent("folder"),withIntermediateDirectories:true)
  try Data("download cleanup".utf8).write(to:local.appendingPathComponent("folder/old"))
  let localSnapshot=try SyncPlanner.local(local.path),remoteSnapshot=try SyncPlanner.remote(remote.path,client:client)
  let download=SyncComparison.candidates(local:localSnapshot,remote:remoteSnapshot,direction:.download,deleteExtraneous:true)
  let localPlan=try SyncDeletionPlan.prepare(download[0],localRoot:local.path,remoteRoot:remote.path,localSnapshot:localSnapshot,remoteSnapshot:remoteSnapshot,client:client)
  var recycled=0
  app.localTrashHandler={url in recycled+=1;try fm.moveItem(at:url,to:bin.appendingPathComponent(url.lastPathComponent))}
  try app.enqueueSync(download,localRoot:local.path,remoteRoot:remote.path,localSnapshot:localSnapshot,remoteSnapshot:remoteSnapshot,deletions:["folder":localPlan],site:site,socket:tab.socket,policy:TransferPolicy())
  app.jobs.last!.execute({});check(!app.jobs.last!.failed && recycled==1 && fm.fileExists(atPath:bin.appendingPathComponent("folder/old").path))

  // Included/excluded relative paths must apply inside a grouped directory transfer too.
  try fm.createDirectory(at:local.appendingPathComponent("upload/nested"),withIntermediateDirectories:true)
  try Data("wanted".utf8).write(to:local.appendingPathComponent("upload/nested/keep.txt"))
  try Data("excluded".utf8).write(to:local.appendingPathComponent("upload/nested/keep.bin"))
  let source=try SyncPlanner.local(local.path),target=try SyncPlanner.remote(remote.path,client:client),policy=TransferPolicy(include:"upload/**/*.txt")
  let predicate=try policy.predicate()
  let transfers=SyncComparison.candidates(local:source,remote:target,direction:.upload,allows:{predicate($0,($0 as NSString).lastPathComponent,$1)})
  try app.enqueueSync(transfers,localRoot:local.path,remoteRoot:remote.path,localSnapshot:source,remoteSnapshot:target,deletions:[:],site:site,socket:tab.socket,policy:policy)
  app.jobs.last!.execute({});check(!app.jobs.last!.failed && fm.fileExists(atPath:remote.appendingPathComponent("upload/nested/keep.txt").path) && !fm.fileExists(atPath:remote.appendingPathComponent("upload/nested/keep.bin").path))
  check(!app.window.isVisible && !auth.isVisible)
  app.transfers.cancelAllOperations();app.jobs=[];app.connections=[];app.window.close();auth.close()
  print("PASS: hidden one-way-only cleanup options/default off, red preview and explicit cancel/confirm, production App queue dispatch and real SFTP cleanup, no blind retry/recovery, stale connection/missing plan rejected, injected local recycler, grouped transfers retain relative masks; no server/password/visible prompt")
 }
}
