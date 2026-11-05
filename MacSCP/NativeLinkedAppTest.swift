import Cocoa
final class BrowseClientGate {
 private let lock=NSLock();private let semaphore=DispatchSemaphore(value:0);private var blockNext=false,counter=0
 var count:Int{lock.lock();defer{lock.unlock()};return counter}
 func arm(){lock.lock();blockNext=true;lock.unlock()}
 func release(){semaphore.signal()}
 func make()throws->SFTPClient{lock.lock();counter+=1;let block=blockNext;blockNext=false;lock.unlock();if block{precondition(semaphore.wait(timeout:.now()+5) == .success)};return try SFTPClient(command:"/usr/libexec/sftp-server",arguments:[])}
}
@main struct NativeLinkedAppTests {
 static func wait(_ condition:()->Bool){let deadline=Date().addingTimeInterval(5);while !condition() && Date()<deadline{RunLoop.current.run(until:Date().addingTimeInterval(0.01))};precondition(condition(),"native app linked browsing timeout")}
 static func main()throws{
  NSApplication.shared.setActivationPolicy(.prohibited)
  let fm=FileManager.default,root=fm.temporaryDirectory.appendingPathComponent("native-linked-"+UUID().uuidString)
  for path in ["local/a","local/b","remote/a","remote/b","local/create","local/decline","local/stale","local/clash"]{try fm.createDirectory(at:root.appendingPathComponent(path),withIntermediateDirectories:true)}
  defer{try? fm.removeItem(at:root)}
  let marker=Data("unchanged".utf8);try marker.write(to:root.appendingPathComponent("remote/clash"))
  let client=try SFTPClient(command:"/usr/libexec/sftp-server",arguments:[]);let remote=try client.canonical(root.appendingPathComponent("remote").path);client.close()
  let local=root.appendingPathComponent("local").resolvingSymlinksInPath().path
  let suite="macscp-native-profile-"+UUID().uuidString
  let defaults=UserDefaults(suiteName:suite)!
  defer{defaults.removePersistentDomain(forName:suite)}
  let gate=BrowseClientGate(),app=App(defaults:defaults,dataDirectory:root.appendingPathComponent("profile"),initialLocalDirectory:root.path,automaticLogin:false,frameAutosaveName:nil,clientProvider:{_,_ in try gate.make()})
  let progress=SSHConnection(arguments:["60"],helper:"/unused",executable:"/unused",command:"/bin/sleep");defer{progress.stop()}
  let site=Session(name:"linked fixture",host:"linked-fixture.invalid",user:"fixture",port:22,key:"")
  let auth=NSWindow(contentRect:NSRect(x:0,y:0,width:200,height:100),styleMask:[.titled],backing:.buffered,defer:false);auth.isReleasedWhenClosed=false
  let tab=ConnectionTab(site,"fixture-socket",progress,auth,local);tab.connected=true
  app.connections=[tab];app.selectedTab=0;app.session=site;app.socket=tab.socket;app.remote.path.isEnabled=true
  app.confirmLinkedDirectoryCreation={_,_ in false}
  func pairRoots(){tab.linkedBrowsing.setEnabled(true);app.local.acceptPath(local);app.local.entries=[];app.local.reload();app.remote.acceptPath(remote);app.remote.entries=[];app.remote.reload();app.lastLocalPath=local;app.lastRemotePath=remote;app.localHistory=[];app.remoteHistory=[]}
  pairRoots()
  app.local.path.stringValue=local+"/a";app.loadLocal();wait{!app.browsing && app.remote.currentPath==remote+"/a"}
  precondition(app.local.currentPath==local+"/a" && gate.count==1)
  app.remote.path.stringValue=remote;app.loadRemote();wait{!app.browsing && app.local.currentPath==local}
  precondition(app.remote.currentPath==remote && gate.count==2)

  app.remoteHistory=[];gate.arm();let before=gate.count;app.local.path.stringValue=local+"/a";app.loadLocal();wait{gate.count==before+1}
  app.local.path.stringValue=local+"/b";app.loadLocal();precondition(app.pendingRemoteNavigation?.target==remote+"/b")
  gate.release();wait{!app.browsing && app.pendingRemoteNavigation==nil && app.remote.currentPath==remote+"/b"}
  precondition(app.local.currentPath==local+"/b" && gate.count==before+2 && !app.remoteHistory.contains(remote+"/a"))

  gate.arm();let userBefore=gate.count;app.remote.path.stringValue=remote+"/a";app.loadRemote();wait{gate.count==userBefore+1}
  app.local.path.stringValue=local+"/a";app.loadLocal();gate.release()
  wait{!app.browsing && app.pendingRemoteNavigation==nil && app.remote.currentPath==remote+"/a"}
  precondition(app.local.currentPath==local+"/a" && gate.count==userBefore+2)

  gate.arm();let refreshBefore=gate.count;app.remote.path.stringValue=remote+"/b";app.loadRemote();wait{gate.count==refreshBefore+1};app.refresh();precondition(app.pendingRemoteNavigation==nil);gate.release()
  wait{!app.browsing && app.local.currentPath==local+"/b" && app.remote.currentPath==remote+"/b"};precondition(tab.linkedBrowsing.enabled)

  pairRoots();var prompts=0
  app.confirmLinkedDirectoryCreation={request,host in prompts+=1;precondition(request.path==remote+"/create" && host==site.identity);return true}
  app.local.path.stringValue=local+"/create";app.loadLocal();wait{!app.browsing && app.remote.currentPath==remote+"/create"}
  precondition(prompts==1 && fm.fileExists(atPath:remote+"/create"))

  pairRoots();app.confirmLinkedDirectoryCreation={_,_ in prompts+=1;return false}
  app.local.path.stringValue=local+"/decline";app.loadLocal();wait{!app.browsing && !tab.linkedBrowsing.enabled}
  precondition(prompts==2 && !fm.fileExists(atPath:remote+"/decline") && app.remote.currentPath==remote)

  pairRoots();app.confirmLinkedDirectoryCreation={_,_ in app.generation+=1;tab.linkedBrowsing.invalidate();prompts+=1;return true}
  app.local.path.stringValue=local+"/stale";app.loadLocal();wait{!app.browsing && prompts==3}
  precondition(!fm.fileExists(atPath:remote+"/stale"))

  pairRoots();app.confirmLinkedDirectoryCreation={_,_ in fatalError("file conflict must not offer creation")}
  app.local.path.stringValue=local+"/clash";app.loadLocal();wait{!app.browsing && !tab.linkedBrowsing.enabled}
  let preserved=try Data(contentsOf:root.appendingPathComponent("remote/clash"));precondition(preserved==marker && app.remote.currentPath==remote)
  precondition(NSApp.windows.allSatisfy{!$0.isVisible})
  print("PASS: actual App hidden-pane navigation follows in both directions without loops; delayed and competing requests discard stale results; refresh preserves pending intent; creation accept/decline, session change during confirmation, and file collision preserve targets; no visible window/user session accessed")
 }
}
