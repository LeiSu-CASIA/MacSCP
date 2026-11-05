import Cocoa
@main struct NativeSyncOptionsTests {
 static func check(_ value:Bool,file:StaticString = #file,line:UInt = #line){precondition(value,file:file,line:line)}
 static func refused(_ action:()throws->Void){do{try action();fatalError("invalid options accepted")}catch{}}
 static func main()throws {
  NSApplication.shared.setActivationPolicy(.prohibited)
  let options=SyncOptionsView(permitsUpload:true)
  check(try options.settings()==SyncSettings() && options.remember.state == .off)
  options.operation.selectItem(at:1);options.changedOptions();options.size.state = .on;options.existingOnly.state = .on;options.cleanup.state = .on
  let mirror=try options.settings();check(mirror.comparison.fileMode == .mirror && mirror.comparison.size && mirror.comparison.existingOnly && mirror.cleanup && options.explanation.stringValue.contains("较新"))
  options.direction.selectItem(at:2);options.changedDirection()
  check(options.operation.isEnabled && options.operation.item(at:1)?.isEnabled==false && !options.size.isEnabled && !options.checksum.isEnabled && !options.cleanup.isEnabled)
  let both=try options.settings();check(both.direction == .both && both.comparison.fileMode == .synchronize && both.comparison.modificationTime && !both.comparison.size && !both.comparison.checksum && !both.cleanup)
  options.direction.selectItem(at:1);options.changedDirection();check(options.operation.isEnabled && options.checksum.isEnabled && !options.deleteExtraneous)
  for text in ["", "bad", "NaN", "-1", "301"]{options.tolerance.stringValue=text;refused{_ = try options.settings()}}
  options.tolerance.stringValue="0";check(try options.settings().comparison.timeTolerance==0)
  let restore=SyncOptionsView(permitsUpload:true,settings:mirror);check(try restore.settings()==mirror)
  let readOnly=SyncOptionsView(permitsUpload:false,settings:mirror);check(try readOnly.settings().direction == .download && readOnly.settings().comparison.fileMode == .mirror)
  let focusedRemote=SyncOptionsView(permitsUpload:true,initialDirection:.download);check(focusedRemote.mode == .download)
  let host=NSWindow(contentRect:NSRect(x:0,y:0,width:500,height:330),styleMask:[.titled],backing:.buffered,defer:false);host.isReleasedWhenClosed=false;host.contentView=options;options.layoutSubtreeIfNeeded()
  for control in [options.direction,options.operation,options.modificationTime,options.size,options.checksum,options.cleanup,options.existingOnly,options.remember,options.tolerance] as [NSView]{check(control.frame.width>30 && control.frame.minX>=0 && control.frame.maxX<=options.bounds.width && control.frame.maxY<=options.bounds.height)}
  check(!host.isVisible);host.close()

  let fm=FileManager.default,root=fm.temporaryDirectory.appendingPathComponent("native-sync-options-"+UUID().uuidString),local=root.appendingPathComponent("local"),remote=root.appendingPathComponent("remote")
  for dir in [local,remote]{try fm.createDirectory(at:dir,withIntermediateDirectories:true)}
  let suite="native-sync-options-"+UUID().uuidString,defaults=UserDefaults(suiteName:suite)!
  defer{try? fm.removeItem(at:root);defaults.removePersistentDomain(forName:suite)}
  try mirror.save(to:defaults);let reloaded=SyncOptionsView(permitsUpload:true,settings:SyncSettings.load(from:defaults));check(try reloaded.settings()==mirror)
  let client=try SFTPClient(command:"/usr/libexec/sftp-server",arguments:[]);defer{client.close()}
  func put(_ base:URL,_ text:String,_ date:Double)throws{let path=base.appendingPathComponent("file.txt");try Data(text.utf8).write(to:path);try fm.setAttributes([.modificationDate:Date(timeIntervalSince1970:date)],ofItemAtPath:path.path)}
  try put(local,"older source",1700000000);try put(remote,"newer target",1800000000)
  let l=try SyncPlanner.local(local.path),r=try SyncPlanner.remote(remote.path,client:client)
  check(try SyncComparison.plannedCandidates(local:l,remote:r,settings:SyncSettings()).isEmpty)
  let chosen=SyncSettings(comparison:SyncComparisonOptions(fileMode:.mirror,timeTolerance:0))
  let candidates=try SyncComparison.plannedCandidates(local:l,remote:r,settings:chosen)
  check(candidates.count==1 && candidates[0].mirror && candidates[0].replacing)
  var clients=0
  let app=App(defaults:defaults,dataDirectory:root.appendingPathComponent("profile"),initialLocalDirectory:local.path,automaticLogin:false,showsMainWindow:false,frameAutosaveName:nil,clientProvider:{_,_ in clients+=1;return try SFTPClient(command:"/usr/libexec/sftp-server",arguments:[])})
  app.applicationDidFinishLaunching(Notification(name:NSApplication.didFinishLaunchingNotification));app.transfers.isSuspended=true
  let ssh=SSHConnection(arguments:["60"],helper:"/unused",executable:"/unused",command:"/bin/sleep");defer{ssh.stop()}
  let auth=NSWindow(contentRect:NSRect(x:0,y:0,width:200,height:100),styleMask:[.titled],backing:.buffered,defer:false);auth.isReleasedWhenClosed=false
  let site=Session(name:"fixture",host:"example.invalid",user:"fixture",port:22,key:"");let tab=ConnectionTab(site,"mirror-fixture-only",ssh,auth,local.path,defaults:defaults);tab.connected=true
  app.connections=[tab];app.selectedTab=0;app.session=site;app.socket=tab.socket
  let preview=app.makeSyncPreview(candidates,localRoot:local.path,remoteRoot:remote.path,localSnapshot:l,remoteSnapshot:r,deletions:[:],site:site,socket:tab.socket,policy:TransferPolicy(),comparisonSummary:chosen.comparison.summary)
  preview.apply();check(app.jobs.count==1 && clients==0 && app.jobs[0].overwrite)
  app.jobs[0].execute({});check(!app.jobs[0].failed && clients==1)
  check(try Data(contentsOf:remote.appendingPathComponent("file.txt"))==Data("older source".utf8))
  check(try client.attributes(remote.appendingPathComponent("file.txt").path)?.modified==1700000000)
  try put(local,"newer local target",1800000000)
  let dl=try SyncPlanner.local(local.path),dr=try SyncPlanner.remote(remote.path,client:client),download=SyncSettings(direction:.download,comparison:SyncComparisonOptions(fileMode:.mirror))
  check(try SyncComparison.plannedCandidates(local:dl,remote:dr,settings:SyncSettings(direction:.download)).isEmpty)
  let downloads=try SyncComparison.plannedCandidates(local:dl,remote:dr,settings:download)
  try app.enqueueSync(downloads,localRoot:local.path,remoteRoot:remote.path,localSnapshot:dl,remoteSnapshot:dr,deletions:[:],site:site,socket:tab.socket,policy:TransferPolicy())
  app.jobs.last!.execute({});check(try !app.jobs.last!.failed && clients==2 && Data(contentsOf:local.appendingPathComponent("file.txt"))==Data("older source".utf8))
  // Changing the newer target after the mirror preview must still block replacement.
  try put(local,"source",1700000000);try put(remote,"newer target",1800000000)
  let staleL=try SyncPlanner.local(local.path),staleR=try SyncPlanner.remote(remote.path,client:client),stale=try SyncComparison.plannedCandidates(local:staleL,remote:staleR,settings:chosen)
  try app.enqueueSync(stale,localRoot:local.path,remoteRoot:remote.path,localSnapshot:staleL,remoteSnapshot:staleR,deletions:[:],site:site,socket:tab.socket,policy:TransferPolicy())
  try put(remote,"concurrent replacement",1800000001)
  app.jobs.last!.execute({});check(try app.jobs.last!.failed && Data(contentsOf:remote.appendingPathComponent("file.txt"))==Data("concurrent replacement".utf8))
  try fm.createDirectory(at:local.appendingPathComponent("folder/nested"),withIntermediateDirectories:true)
  try Data("included".utf8).write(to:local.appendingPathComponent("folder/nested/keep.txt"));try Data("excluded".utf8).write(to:local.appendingPathComponent("folder/nested/keep.bin"))
  let hashRule=TransferPolicy(include:"folder/**/*.txt",verifyChecksum:true),predicate=try hashRule.predicate(),allows:(String,Bool)->Bool={predicate($0,($0 as NSString).lastPathComponent,$1)}
  let rawL=try SyncPlanner.local(local.path),rawR=try SyncPlanner.remote(remote.path,client:client)
  let hashL=try SyncChecksums.local(rawL,root:local.path,paths:SyncComparison.checksumPaths(rawL,allows:allows)),hashR=try SyncChecksums.remote(rawR,root:remote.path,client:client,paths:SyncComparison.checksumPaths(rawR,allows:allows))
  let hashSettings=SyncSettings(comparison:SyncComparisonOptions(modificationTime:false,checksum:true)),hashCandidates=try SyncComparison.plannedCandidates(local:hashL,remote:hashR,settings:hashSettings,allows:allows)
  check(hashCandidates.count==1 && hashCandidates[0].directory)
  try app.enqueueSync(hashCandidates,localRoot:local.path,remoteRoot:remote.path,localSnapshot:hashL,remoteSnapshot:hashR,deletions:[:],site:site,socket:tab.socket,policy:hashRule)
  app.jobs.last!.execute({});check(try !app.jobs.last!.failed && Data(contentsOf:remote.appendingPathComponent("folder/nested/keep.txt"))==Data("included".utf8) && !fm.fileExists(atPath:remote.appendingPathComponent("folder/nested/keep.bin").path))
  check(!app.window.isVisible && !auth.isVisible)
  app.transfers.cancelAllOperations();app.jobs=[];app.connections=[];app.window.close();auth.close()
  print("PASS: hidden complete sync options/defaults, both-mode interlocks, readonly download mirror, validation and remembered settings, real production App mirror upload/download of older sources with timestamps preserved, stale target refusal; temporary local SFTP only, no credentials/windows")
 }
}
