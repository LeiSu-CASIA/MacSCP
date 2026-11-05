import Cocoa
@main struct NativeFilePropertiesTests {
 static func wait(_ predicate:()->Bool){let end=Date().addingTimeInterval(10);while !predicate() && Date()<end{RunLoop.current.run(until:Date().addingTimeInterval(0.01))};precondition(predicate(),"properties timeout")}
 static func main()throws{
  NSApplication.shared.setActivationPolicy(.prohibited)
  let fm=FileManager.default,root=fm.temporaryDirectory.appendingPathComponent("native-properties-"+UUID().uuidString),suite="macscp-properties-"+UUID().uuidString
  try fm.createDirectory(at:root.appendingPathComponent("data/nested"),withIntermediateDirectories:true);try Data(repeating:1,count:17).write(to:root.appendingPathComponent("data/nested/中文.txt"));try Data(repeating:1,count:5).write(to:root.appendingPathComponent("file.txt"))
  let defaults=UserDefaults(suiteName:suite)!;defer{try? fm.removeItem(at:root);defaults.removePersistentDomain(forName:suite)}
  let lock=NSLock();var calls=0,receivedSocket=""
  let app=App(defaults:defaults,dataDirectory:root.appendingPathComponent("profile"),initialLocalDirectory:root.path,automaticLogin:false,showsMainWindow:false,frameAutosaveName:nil,clientProvider:{_,sock in lock.lock();calls+=1;receivedSocket=sock;lock.unlock();return try SFTPClient(command:"/usr/libexec/sftp-server",arguments:[])})
  app.applicationDidFinishLaunching(Notification(name:NSApplication.didFinishLaunchingNotification));defer{app.window.close()}
  app.local.entries=[Entry(name:"..",size:0,dir:true),Entry(name:"data",size:0,dir:true,permissions:"755"),Entry(name:"file.txt",size:5,dir:false,permissions:"644")];app.local.reload();app.local.table.selectAll(nil)
  let local=app.makeFileProperties(true)!;precondition(local.paths.count==2 && app.propertiesWindows.count==1 && !local.window!.isVisible && !local.busy && calls==0)
  for size in [NSSize(width:680,height:500),NSSize(width:560,height:420)]{local.window!.setContentSize(size);local.window!.contentView!.layoutSubtreeIfNeeded();precondition(local.output.enclosingScrollView!.frame.height>=150 && local.startButton.frame.width>60 && local.message.frame.width>400 && local.window!.contentView!.frame.width<=size.width+1)}
  local.start();wait{!local.busy};precondition(local.result?.bytes==22 && local.result?.files==2 && local.result?.directories==2 && local.result?.complete==true && local.size.stringValue.contains("22 字节") && local.message.stringValue.contains("统计完成"))
  local.start();wait{!local.busy};precondition(local.result?.bytes==22 && !local.output.string.contains("统计警告"))
  local.close();precondition(app.propertiesWindows.isEmpty)
  precondition(app.makeFileProperties(false)==nil)
  let ssh=SSHConnection(arguments:["60"],helper:"/unused",executable:"/unused",command:"/bin/sleep");defer{ssh.stop()}
  let auth=NSWindow(contentRect:NSRect(x:0,y:0,width:100,height:100),styleMask:[.titled],backing:.buffered,defer:false);auth.isReleasedWhenClosed=false;defer{auth.close()}
  let site=Session(name:"fixture",host:"fixture.invalid",user:"fixture",port:22,key:""),sock=root.appendingPathComponent("absent-socket").path
  let tab=ConnectionTab(site,sock,ssh,auth,root.path,defaults:defaults);tab.connected=true;app.connections=[tab];app.selectedTab=0;app.session=site;app.socket=sock;app.refreshConnectionPresentation();app.remote.acceptPath(root.path);app.remote.entries=[Entry(name:"data",size:0,dir:true)];app.remote.reload();app.remote.table.selectAll(nil)
  let remote=app.makeFileProperties(false)!;precondition(calls==0 && !remote.window!.isVisible);app.socket="changed-after-properties-opened";remote.start();wait{!remote.busy};precondition(remote.result?.bytes==17 && remote.result?.complete==true && calls==1 && receivedSocket==sock);remote.close();precondition(app.propertiesWindows.isEmpty)
  let entered=DispatchSemaphore(value:0),release=DispatchSemaphore(value:0)
  let cancelled=FilePropertiesController(paths:[root.path],entries:[Entry(name:"root",size:0,dir:true)],remote:true,factory:{entered.signal();release.wait();return try SFTPClient(command:"/usr/libexec/sftp-server",arguments:[])})
  cancelled.start();precondition(entered.wait(timeout:.now()+5) == .success);cancelled.cancel();release.signal();wait{!cancelled.busy};precondition(cancelled.result==nil && cancelled.message.stringValue.contains("统计已取消") && cancelled.startButton.isEnabled && !cancelled.cancelButton.isEnabled);cancelled.close()
  let missing=FilePropertiesController(paths:[root.appendingPathComponent("missing").path],entries:[Entry(name:"missing",size:0,dir:false)],remote:false,factory:nil)
  missing.start();wait{!missing.busy};precondition(missing.result?.complete==false && missing.message.stringValue.contains("不完整") && missing.output.string.contains("统计警告"));missing.start();wait{!missing.busy};precondition(missing.output.string.components(separatedBy:"统计警告").count==2);missing.close()
  let single=FilePropertiesController(paths:[root.appendingPathComponent("file.txt").path],entries:[Entry(name:"file.txt",size:5,dir:false)],remote:false,factory:nil)
  precondition(single.size.stringValue.contains("5 字节") && single.output.string.contains("列表属性") && !single.busy);single.close()
  let exitEntered=DispatchSemaphore(value:0),exitRelease=DispatchSemaphore(value:0)
  let exiting=FilePropertiesController(paths:[root.path],entries:[Entry(name:"root",size:0,dir:true)],remote:true,factory:{exitEntered.signal();exitRelease.wait();return try SFTPClient(command:"/usr/libexec/sftp-server",arguments:[])})
  app.propertiesWindows.append(exiting);exiting.start();precondition(exitEntered.wait(timeout:.now()+5) == .success);try app.finishExit();exitRelease.signal();wait{!exiting.busy};precondition(exiting.result==nil && exiting.message.stringValue.contains("统计已取消"));exiting.close()
  precondition(!app.window.isVisible && !auth.isVisible)
  print("PASS: hidden real App multi-item properties, 560/680 point layout, async local/SFTP totals, no automatic connection, captured endpoint, cancel during client setup, restart clears old warnings, incomplete errors and controller release; no network/login/user window")
 }
}
