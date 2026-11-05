import Cocoa
final class DirectedDropGate {
 private let lock=NSLock();private var semaphore:DispatchSemaphore?,enteredValue=false,createdValue=false
 func install(){lock.lock();semaphore=DispatchSemaphore(value:0);enteredValue=false;createdValue=false;lock.unlock()}
 func point(){lock.lock();let value=semaphore;if value != nil{enteredValue=true};lock.unlock();value?.wait()}
 func created(){lock.lock();createdValue=true;lock.unlock()}
 var entered:Bool{lock.lock();defer{lock.unlock()};return enteredValue}
 var finishedFactory:Bool{lock.lock();defer{lock.unlock()};return createdValue}
 func release(){lock.lock();let value=semaphore;semaphore=nil;lock.unlock();value?.signal()}
}
@main struct NativeDirectedDropTests {
 static func check(_ value:Bool,file:StaticString = #file,line:UInt = #line){precondition(value,file:file,line:line)}
 static func wait(_ value:()->Bool,file:StaticString = #file,line:UInt = #line){let end=Date().addingTimeInterval(10);while !value(),Date()<end{RunLoop.current.run(until:Date().addingTimeInterval(0.01))};check(value(),file:file,line:line)}
 static func main()throws{
  NSApplication.shared.setActivationPolicy(.prohibited)
  let fm=FileManager.default,root=fm.temporaryDirectory.appendingPathComponent("directed-drop-"+UUID().uuidString),suite="macscp-directed-drop-"+UUID().uuidString,defaults=UserDefaults(suiteName:suite)!
  for name in ["local/投放目录","remote-a/子目录","remote-b"]{try fm.createDirectory(at:root.appendingPathComponent(name),withIntermediateDirectories:true)};defer{try? fm.removeItem(at:root);defaults.removePersistentDomain(forName:suite)}
  let source=root.appendingPathComponent("local/notes.txt"),bytes=Data("exact\n中文 %20 #\r\n".utf8);try bytes.write(to:source)
  let reader=LocalReadClient(),local=try reader.canonical(root.appendingPathComponent("local").path),a=try reader.canonical(root.appendingPathComponent("remote-a").path),b=try reader.canonical(root.appendingPathComponent("remote-b").path)
  let child=a+"/子目录",old=Data("old".utf8);try old.write(to:URL(fileURLWithPath:child+"/notes.txt"));try fm.createSymbolicLink(atPath:a+"/link",withDestinationPath:child)
  let gate=DirectedDropGate();var errors=[String](),conflicts=0
  let app=App(defaults:defaults,dataDirectory:root.appendingPathComponent("profile"),initialLocalDirectory:local,automaticLogin:false,showsMainWindow:false,transferOptionsEnabled:true,frameAutosaveName:nil,clientProvider:{site,_ in if site.host=="b.invalid"{gate.point()};let client=try SFTPClient(command:"/usr/libexec/sftp-server",arguments:[]);if site.host=="b.invalid"{gate.created()};return client})
  app.alertPresenter={errors.append($0)};app.transferOptionsPresenter={_ in};app.relayStagingRoot={try RelayStorage.prepare(at:fm.temporaryDirectory)};app.applicationDidFinishLaunching(Notification(name:NSApplication.didFinishLaunchingNotification));let localView=app.local.currentPath
  var tabs=[ConnectionTab]()
  for (name,path) in [("a",a),("b",b)]{let process=SSHConnection(arguments:["120"],helper:"/unused",executable:"/unused",command:"/bin/sleep"),auth=NSWindow(contentRect:NSRect(x:0,y:0,width:100,height:100),styleMask:[.titled],backing:.buffered,defer:false);auth.isReleasedWhenClosed=false;let tab=ConnectionTab(Session(name:name,host:name+".invalid",user:"fixture",port:22,key:""),"directed-"+UUID().uuidString,process,auth,local,defaults:defaults);tab.connected=true;tab.remotePath=path;tabs.append(tab)}
  defer{gate.release();app.cancelPendingDrops();app.transferConfirmation?.cancel();for job in app.jobs{job.cancel()};app.transfers.cancelAllOperations();app.transfers.isSuspended=false;for tab in tabs{tab.stop();tab.auth?.close()};app.connections=[];app.window.close()}
  app.connections=tabs;app.selectedTab=0;app.socket=tabs[0].socket;app.session=tabs[0].session;app.terminal=tabs[0].terminal;app.auth=tabs[0].auth;app.remote.setConnectionState(.connected);app.remote.acceptPath(a)
  func populate(){app.remote.entries=[Entry(name:"..",size:0,dir:true),Entry(name:"子目录",size:0,dir:true),Entry(name:"file.txt",size:1,dir:false),Entry(name:"link",size:0,dir:true,symbolicLink:true),Entry(name:"broken",size:0,dir:true,linkUnavailable:true)];app.remote.reload()}
  func row(_ name:String)->Int{app.remote.entries.firstIndex{$0.name==name}!}
  populate();let file=DragFile(path:source.path,directory:false,size:UInt64(bytes.count),connection:nil)
  check(app.remote.dropDirectory(row:row("子目录"),operation:.on)==child && app.remote.dropDirectory(row:row("file.txt"),operation:.on)==a && app.remote.dropDirectory(row:row("子目录"),operation:.above)==a)
  check(app.remote.dropDirectory(row:0,operation:.on)==nil && app.remote.dropDirectory(row:row("link"),operation:.on)==nil && app.remote.dropDirectory(row:row("broken"),operation:.on)==nil)
  app.transferConflictPrompt={_ in conflicts+=1;return .init(action:.skip)}
  check(app.remote.receiveDroppedFiles([file],row:row("子目录"),operation:.on));check(app.transferConfirmation?.destination.stringValue==child && app.jobs.isEmpty);app.transferConfirmation!.apply();wait{app.transferConfirmation==nil};check(try app.jobs.isEmpty && conflicts==1 && (try Data(contentsOf:URL(fileURLWithPath:child+"/notes.txt")))==old)
  app.transferConflictPrompt={_ in conflicts+=1;return .init(action:.replace)};populate();check(app.remote.receiveDroppedFiles([file],row:row("子目录"),operation:.on));app.transferConfirmation!.apply();wait{app.jobs.count==1 && app.jobs[0].finished};check(!app.jobs[0].failed && app.remote.currentPath==a && app.local.currentPath==localView);check(try Data(contentsOf:URL(fileURLWithPath:child+"/notes.txt"))==bytes)
  app.local.entries=[Entry(name:"投放目录",size:0,dir:true)];app.local.reload();check(app.local.receiveDroppedFiles([file],row:0,operation:.on));check(app.transferConfirmation!.localOnly);app.transferConfirmation!.apply();wait{app.jobs.count==2 && app.jobs[1].finished};check(try Data(contentsOf:URL(fileURLWithPath:local+"/投放目录/notes.txt"))==bytes)
  if !app.remote.treeVisible{app.remote.toggleTree()};app.remote.directoryTree.setRoot(a);wait{app.remote.directoryTree.root?.children != nil}
  let tree=app.remote.directoryTree,node=tree.root!.children!.first{$0.name=="子目录"}!,link=tree.root!.children!.first{$0.name=="link"}!
  check(tree.dropPath(node,childIndex:-1)==child && tree.dropPath(link,childIndex:-1)==nil && tree.dropPath(node,childIndex:0)==nil)
  check(tree.receiveDroppedFiles([file],on:node,childIndex:-1));app.transferConfirmation!.cancel();tree.reset();check(tree.dropPath(node,childIndex:-1)==nil)
  // Another tab uses its own rule/limit while current tab and global/manual preferences remain unchanged.
  let manual=TransferPreferences(concurrency:3,kibibytesPerSecond:128),ruleA=TransferPreferences(concurrency:2,kibibytesPerSecond:256,policy:TransferPolicy(include:"*.csv")),ruleB=TransferPreferences(concurrency:7,kibibytesPerSecond:64,policy:TransferPolicy(include:"*.txt",verifyChecksum:true))
  app.preferences=manual;app.transferPresets=TransferPresetLibrary();let presetA=try app.transferPresets.add(name:"A CSV",preferences:ruleA,rule:TransferPresetRule(enabled:true,host:"a.invalid"));_ = try app.transferPresets.add(name:"B TXT",preferences:ruleB,rule:TransferPresetRule(enabled:true,host:"b.invalid"));app.reevaluateTransferPreset(force:true);app.rebuildTabs()
  check(app.automaticTransferPresetID==presetA);let beforeGeneration=app.generation,button=app.tabBar.arrangedSubviews.compactMap{$0 as? SessionTabButton}[1]
  check(button.acceptsDrop?()==true && button.receiveDrop?([file])==true);let confirmation=app.transferConfirmation!;check(confirmation.destination.stringValue==b && confirmation.base==ruleB && confirmation.independent.state == .on)
  app.transfers.isSuspended=true;confirmation.apply();wait{app.jobs.count==3 && app.transferConfirmation==nil};let upload=app.jobs.last!
  check(app.selectedTab==0 && app.generation==beforeGeneration && app.remote.currentPath==a && app.preferences==manual && app.automaticTransferPresetID==presetA && app.effectiveTransferPreferences==ruleA)
  check(upload.recoverySite?.identity==tabs[1].session.identity && upload.policy==ruleB.filePolicy && upload.overrideSpeedLimit==65536 && upload.speedLimit==65536 && app.transfers.maxConcurrentOperationCount==2)
  app.transfers.isSuspended=false;wait{upload.finished};check(try !upload.failed && (try Data(contentsOf:URL(fileURLWithPath:b+"/notes.txt")))==bytes)
  let remoteSource=a+"/remote-source.txt";try bytes.write(to:URL(fileURLWithPath:remoteSource));let remoteFile=DragFile(path:remoteSource,directory:false,size:UInt64(bytes.count),connection:tabs[0].socket)
  app.dragTransferOptionsEnabled=false;check(button.receiveDrop?([remoteFile])==true);check(app.transferConfirmation==nil);wait{app.jobs.count==5 && app.jobs.suffix(2).allSatisfy{$0.finished}}
  check(app.jobs.suffix(2).allSatisfy{!$0.failed && $0.overrideSpeedLimit==65536});check(try Data(contentsOf:URL(fileURLWithPath:b+"/remote-source.txt"))==bytes);check(app.selectedTab==0 && app.remote.currentPath==a)
  for _ in 0..<8{app.pendingDropProbes[UUID()]=TransferDestinationProbe()};check(button.receiveDrop?([file])==false && app.status.stringValue.contains("过多"));app.cancelPendingDrops()
  let count=app.jobs.count;gate.install();check(button.receiveDrop?([file])==true);wait{gate.entered};check(!app.pendingDropProbes.isEmpty);let escape=NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:[],timestamp:0,windowNumber:app.window.windowNumber,context:nil,characters:"\u{1b}",charactersIgnoringModifiers:"\u{1b}",isARepeat:false,keyCode:53)!;app.remote.table.keyDown(with:escape);gate.release();wait{gate.finishedFactory};RunLoop.current.run(until:Date().addingTimeInterval(0.15));check(app.jobs.count==count && app.pendingDropProbes.isEmpty)
  app.transferConflictPrompt={_ in app.activateTab(1);return .init(action:.replace)};check(button.receiveDrop?([file])==true);wait{app.pendingDropProbes.isEmpty};check(app.jobs.count==count && app.selectedTab==1);app.stashTab();app.activateTab(0)
  gate.install();check(button.receiveDrop?([file])==true);wait{gate.entered};app.connections=[tabs[0]];gate.release();wait{app.pendingDropProbes.isEmpty};check(app.jobs.count==count && app.status.stringValue.contains("变化"));check(button.acceptsDrop?()==false)
  check(errors.isEmpty && !app.window.isVisible && tabs.allSatisfy{$0.auth?.isVisible != true})
  print("PASS: real pane/tree folder routes and link/parent/stale rejection, custom-target skip/replace and local copy exact bytes; inactive-tab upload and two-endpoint relay keep current tab/path/preferences, target-specific auto policy/limit, independent queue limits, direct-mode probe cancellation and removed-target refusal; own SFTP stdio/memory data only, no UI/auth/network")
 }
}
