import Cocoa
final class MemoryFileClipboard:FileClipboardAccess {var value=FileClipboardSnapshot();var writes=0,reads=0;func read()throws->FileClipboardSnapshot{reads+=1;return value};func write(_ value:FileClipboardSnapshot)throws{self.value=value;writes+=1}}
@main struct NativeFileClipboardTests {
 static func check(_ value:Bool,file:StaticString = #file,line:UInt = #line){precondition(value,file:file,line:line)}
 static func wait(_ value:()->Bool){let end=Date().addingTimeInterval(10);while !value(),Date()<end{RunLoop.current.run(until:Date().addingTimeInterval(0.01))};check(value())}
 static func main()throws{
  NSApplication.shared.setActivationPolicy(.prohibited)
  let fm=FileManager.default,root=fm.temporaryDirectory.appendingPathComponent("macscp-clipboard-"+UUID().uuidString),suite="macscp-clipboard-"+UUID().uuidString,defaults=UserDefaults(suiteName:suite)!
  for folder in ["from/folder/empty","local","remote-a","remote-b"]{try fm.createDirectory(at:root.appendingPathComponent(folder),withIntermediateDirectories:true)}
  defer{try? fm.removeItem(at:root);defaults.removePersistentDomain(forName:suite)}
  let filename="中文 %20 # 文件.txt",source=root.appendingPathComponent("from/"+filename),data=Data("original\r\nunchanged\n".utf8);try data.write(to:source)
  try Data("tree".utf8).write(to:root.appendingPathComponent("from/folder/file.txt"))
  let owner=UUID(),one=DragFile(path:source.path,directory:false,size:UInt64(data.count),connection:nil)
  check(try FileClipboardEnvelope.files(FileClipboardEnvelope.encode(owner:owner,files:[one,one]),owner:owner)?.count==1)
  let canonicalSource=try LocalReadClient().canonical(source.path),canonicalFile=DragFile(path:canonicalSource,directory:false,size:UInt64(data.count),connection:"remote-fixture")
  check(try FileClipboardEnvelope.files(FileClipboardEnvelope.encode(owner:owner,files:[canonicalFile]),owner:owner)?.first?.path==canonicalSource)

  check(try FileClipboardEnvelope.files(FileClipboardEnvelope.encode(owner:UUID(),files:[one]),owner:owner)?.first?.path==source.path)
  for invalid in ["/","relative","/tmp/../file","/tmp/\0file"]{do{_ = try FileClipboardEnvelope.encode(owner:owner,files:[DragFile(path:invalid,directory:false,size:0,connection:nil)]);fatalError("expected invalid path")}catch{}}
  do{_ = try FileClipboardEnvelope.encode(owner:owner,files:Array(repeating:one,count:10001));fatalError("expected count limit")}catch{}
  do{_ = try FileClipboardEnvelope.files(FileClipboardSnapshot(payload:JSONEncoder().encode(FileClipboardEnvelope(version:2,owner:owner,files:[one]))),owner:owner);fatalError("expected version refusal")}catch{}
  do{_ = try FileClipboardEnvelope.directoryText("/one\n/two");fatalError("expected multiline refusal")}catch{}
  do{_ = try FileClipboardEnvelope.files(FileClipboardSnapshot(urls:[URL(string:"file://remote-host/file")!]),owner:owner);fatalError("expected foreign file URL refusal")}catch{}
  let clipboard=MemoryFileClipboard();var clients=0
  let app=App(defaults:defaults,dataDirectory:root.appendingPathComponent("profile"),initialLocalDirectory:root.appendingPathComponent("from").path,automaticLogin:false,showsMainWindow:false,transferOptionsEnabled:false,frameAutosaveName:nil,clientProvider:{_,_ in clients+=1;return try SFTPClient(command:"/usr/libexec/sftp-server",arguments:[])})
  var errors=[String]();app.alertPresenter={errors.append($0)};app.relayStagingRoot={try RelayStorage.prepare(at:fm.temporaryDirectory)};app.fileClipboard=clipboard;app.applicationDidFinishLaunching(Notification(name:NSApplication.didFinishLaunchingNotification));defer{app.jobs=[];app.window.close()}
  let fileRow=app.local.entries.firstIndex{$0.name==filename}!;app.local.table.selectRowIndexes(IndexSet(integer:fileRow),byExtendingSelection:false)
  check(app.local.table.responds(to:#selector(NSText.copy(_:))) && app.local.table.responds(to:#selector(NSText.paste(_:))));app.local.table.copy(nil);check(clipboard.writes==1 && clipboard.value.urls==[source] && clipboard.value.payload != nil)
  check(app.window.makeFirstResponder(app.local.table))
  let copyKey=NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:.command,timestamp:0,windowNumber:app.window.windowNumber,context:nil,characters:"c",charactersIgnoringModifiers:"c",isARepeat:false,keyCode:8)!
  check(app.local.table.performKeyEquivalent(with:copyKey) && clipboard.writes==2)

  let local=root.appendingPathComponent("local");app.local.path.stringValue=local.path;app.loadLocal();app.preferences.policy=TransferPolicy(text:TextTransferOptions(mode:.text,local:.lf))
  let pasteKey=NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:.command,timestamp:0,windowNumber:app.window.windowNumber,context:nil,characters:"v",charactersIgnoringModifiers:"v",isARepeat:false,keyCode:9)!
  check(app.local.table.performKeyEquivalent(with:pasteKey));wait{app.jobs.count==1 && app.jobs[0].finished};check(!app.jobs[0].failed && app.jobs[0].column("direction")=="本地复制");check(try Data(contentsOf:local.appendingPathComponent(filename))==data && app.jobs[0].policy.text==nil && clients==0)
  var conflicts=0;app.transferConflictPrompt={_ in conflicts+=1;return TransferConflictResponse(action:.skip)};app.pasteFiles(true);check(conflicts==1 && app.jobs.count==1)
  app.transferConflictPrompt={_ in TransferConflictResponse(action:.replace)};app.pasteFiles(true);wait{app.jobs.count==2 && app.jobs[1].finished};check(!app.jobs[1].failed)
  // Finder-style URLs without the internal representation are accepted as local sources.
  clipboard.value=FileClipboardSnapshot(urls:[root.appendingPathComponent("from/folder")]);app.pasteFiles(true);wait{app.jobs.count==3 && app.jobs[2].finished};check(!app.jobs[2].failed && fm.fileExists(atPath:local.appendingPathComponent("folder/empty").path))
  clipboard.value=try FileClipboardEnvelope.encode(owner:app.clipboardOwner,files:[DragFile(path:root.appendingPathComponent("from").path,directory:true,size:0,connection:nil)])
  app.local.path.stringValue=root.appendingPathComponent("from/folder").path;app.loadLocal();let count=app.jobs.count;app.pasteFiles(true);check(app.jobs.count==count && app.status.stringValue.contains("子目录"))
  clipboard.value=FileClipboardSnapshot(text:local.path);app.pasteFiles(true);check(app.local.currentPath==local.path)
  clipboard.value=FileClipboardSnapshot(payload:Data("invalid".utf8),text:root.path);app.pasteFiles(true);check(app.local.currentPath==local.path && app.jobs.count==count)
  app.local.table.selectRowIndexes(IndexSet(integer:app.local.entries.firstIndex{$0.name==filename}!),byExtendingSelection:false);app.paneCommand(true,"copyPath");check(clipboard.value.payload==nil && clipboard.value.urls.isEmpty && clipboard.value.text==local.appendingPathComponent(filename).path)
  var tabs=[ConnectionTab]()
  for i in 0..<2{let process=SSHConnection(arguments:["60"],helper:"/unused",executable:"/unused",command:"/bin/sleep"),auth=NSWindow(contentRect:NSRect(x:0,y:0,width:100,height:100),styleMask:[.titled],backing:.buffered,defer:false);auth.isReleasedWhenClosed=false
   let tab=ConnectionTab(Session(name:"fixture-\(i)",host:"clipboard-\(i).invalid",user:"fixture",port:22,key:""),"clipboard-\(UUID().uuidString)",process,auth,local.path,defaults:defaults);tab.connected=true;tabs.append(tab)
  }
  defer{for tab in tabs{tab.stop();tab.auth?.close()};app.connections=[]}
  app.connections=tabs;app.selectedTab=0;app.session=tabs[0].session;app.socket=tabs[0].socket;app.terminal=tabs[0].terminal;app.auth=tabs[0].auth
  let remoteA=root.appendingPathComponent("remote-a"),remoteB=root.appendingPathComponent("remote-b");app.remote.setConnectionState(.connected);app.remote.acceptPath(remoteA.path);app.remote.reload();app.preferences=TransferPreferences()
  clipboard.value=FileClipboardSnapshot(urls:[source]);app.pasteFiles(false);wait{app.jobs.count==count+1 && app.jobs.last!.finished};check(try !app.jobs.last!.failed && (try Data(contentsOf:remoteA.appendingPathComponent(filename)))==data)
  app.remote.entries=[Entry(name:filename,size:UInt64(data.count),dir:false)];app.remote.reload();app.remote.table.selectRowIndexes(IndexSet(integer:0),byExtendingSelection:false);app.copyFiles(false);check(clipboard.value.urls.isEmpty)
  // Download to a fresh local directory, then copy from the original remote tab to a second tab.
  let download=root.appendingPathComponent("download");try fm.createDirectory(at:download,withIntermediateDirectories:false);app.local.path.stringValue=download.path;app.loadLocal();app.pasteFiles(true);wait{app.jobs.count==count+2 && app.jobs.last!.finished};check(try !app.jobs.last!.failed && (try Data(contentsOf:download.appendingPathComponent(filename)))==data)
  app.stashTab();tabs[1].remotePath=remoteB.path;app.activateTab(1);app.pasteFiles(false);if !errors.isEmpty{print(errors)}
  wait{app.jobs.count==count+4 && app.jobs.suffix(2).allSatisfy{$0.finished}};check(try app.jobs.suffix(2).allSatisfy{!$0.failed} && (try Data(contentsOf:remoteB.appendingPathComponent(filename)))==data)
  let writable=app.session;app.session?.protocolKind = .ftp;let deniedCount=app.jobs.count,deniedClients=clients;app.pasteFiles(false);check(app.jobs.count==deniedCount && clients==deniedClients && app.status.stringValue.contains("不可写"));app.session=writable
  tabs[0].connected=false;let before=app.jobs.count;app.pasteFiles(true);check(app.jobs.count==before && app.status.stringValue.contains("来源服务器"))
  clipboard.value=try FileClipboardEnvelope.encode(owner:UUID(),files:[DragFile(path:"/source/file",directory:false,size:1,connection:"other")]);app.pasteFiles(true);check(app.jobs.count==before && app.status.stringValue.contains("另一实例"))
  app.remote.setConnectionState(.disconnected);let reads=clipboard.reads;app.remote.table.paste(nil);check(clipboard.reads==reads)
  check(errors.isEmpty && !app.window.isVisible && tabs.allSatisfy{$0.auth?.isVisible != true})
  print("PASS: real hidden App copy/paste actions with memory clipboard, Finder-style URL upload, binary local copy/recursive empty dir/conflict skip+replace, local download and two-session relay exact bytes, self-descendant/closed/foreign/malformed refusal, text path navigation and path-only copy, offline no read; owned SFTP stdio, no system clipboard/auth/network")
 }
}
