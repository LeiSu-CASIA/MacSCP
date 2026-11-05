import Cocoa
@main struct NativeKeyboardTests {
 static func check(_ value:Bool,file:StaticString = #file,line:UInt = #line){precondition(value,file:file,line:line)}
 static func event(_ code:UInt16,_ flags:NSEvent.ModifierFlags=[],window:NSWindow?=nil)->NSEvent{NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:flags,timestamp:0,windowNumber:window?.windowNumber ?? 0,context:nil,characters:"",charactersIgnoringModifiers:"",isARepeat:false,keyCode:code)!}
 static func main()throws{
  NSApplication.shared.setActivationPolicy(.prohibited)
  let root=FileManager.default.temporaryDirectory.appendingPathComponent("macscp-keyboard-"+UUID().uuidString),suite="macscp-keyboard-"+UUID().uuidString,defaults=UserDefaults(suiteName:suite)!
  try FileManager.default.createDirectory(at:root,withIntermediateDirectories:false)
  defer{try? FileManager.default.removeItem(at:root);defaults.removePersistentDomain(forName:suite)}
  var clients=0
  let app=App(defaults:defaults,dataDirectory:root.appendingPathComponent("profile"),initialLocalDirectory:root.path,automaticLogin:false,showsMainWindow:false,frameAutosaveName:nil,clientProvider:{_,_ in clients+=1;throw SFTPError.message("unexpected client")})
  app.applicationDidFinishLaunching(Notification(name:NSApplication.didFinishLaunchingNotification));defer{app.window.close()}
  let pane=app.local,original=pane.command;var actions=[String]();pane.command={actions.append($0)}
  for (code,flags,expected) in [(UInt16(98),NSEvent.ModifierFlags(),"mkdir"),(101,[],"properties"),(36,.option,"properties"),(123,.option,"back"),(124,.option,"forward"),(126,.option,"up"),(42,.command,"root"),(48,.shift,"otherPane"),(76,[],"activate")]{
   // Activate uses the pane's open callback; the other keys route to its real command callback.
   let old=pane.open;pane.open={actions.append("activate")};pane.table.keyDown(with:event(code,flags));pane.open=old;check(actions.last==expected)
  }
  check(FileKeyAction.resolve(code:100,command:false,shift:false,option:false,control:true)==nil)
  for code:UInt16 in [96,98,100,101,118,120]{check(FileKeyAction.resolve(code:code,command:false,shift:true,option:false)==nil);check(FileKeyAction.resolve(code:code,command:true,shift:false,option:false)==nil)}
  check(FileKeyAction.resolve(code:15,command:true,shift:true,option:false)==nil && FileKeyAction.resolve(code:8,command:true,shift:true,option:false)=="copyPath")
  pane.command=original
  let entries=[Entry(name:"..",size:0,dir:true),Entry(name:"folder.z",size:0,dir:true),Entry(name:"z.txt",size:1,dir:false,permissions:"600",modified:10),Entry(name:"a.csv",size:20,dir:false,permissions:"644",modified:30),Entry(name:"b.txt",size:3,dir:false,permissions:"755",modified:20)]
  pane.entries=entries;pane.reload();pane.table.selectRowIndexes(IndexSet(integer:pane.entries.firstIndex{$0.name=="a.csv"}!),byExtendingSelection:false)
  check(app.window.makeFirstResponder(pane.table))
  let expected:[String:[String]]=["sortName":["a.csv","b.txt","z.txt"],"sortSize":["z.txt","b.txt","a.csv"],"sortDate":["z.txt","b.txt","a.csv"],"sortExtension":["a.csv","b.txt","z.txt"],"sortPermissions":["z.txt","a.csv","b.txt"]]
  for (code,command) in [(UInt16(18),"sortName"),(19,"sortSize"),(20,"sortDate"),(21,"sortExtension"),(23,"sortPermissions")]{
   pane.table.sortDescriptors=[];check(pane.table.performKeyEquivalent(with:event(code,[.command,.option],window:app.window)))
   check(pane.entries.prefix(2).map{$0.name}==["..","folder.z"] && pane.entries.dropFirst(2).map{$0.name}==expected[command]!)
   check(pane.selected.map{$0.name}==["a.csv"])
   check(pane.table.performKeyEquivalent(with:event(code,[.command,.option],window:app.window)))
   if command != "sortExtension"{check(pane.entries.dropFirst(2).map{$0.name}==Array(expected[command]!.reversed()))}
   check(pane.table.sortDescriptors.first?.ascending==false && pane.entries.first?.name=="..")
  }
  app.paneCommand(true,"sortExtension");check(pane.table.tableColumns[0].headerCell.stringValue.contains("扩展名"));app.paneCommand(true,"sortName");check(pane.table.tableColumns[0].headerCell.stringValue=="名称")
  check(pane.table.performKeyEquivalent(with:event(3,.command,window:app.window)))
  check(pane.filter.currentEditor() === app.window.firstResponder && app.activePaneIsLocal())
  var unexpected=0;pane.table.keyCommand={_ in unexpected+=1}
  check(!pane.table.performKeyEquivalent(with:event(98,window:app.window)) && unexpected==0)
  // A disconnected pane may cycle tabs, but must not invoke its file operations.
  var remoteActions=[String]();app.remote.command={remoteActions.append($0)}
  app.remote.table.keyDown(with:event(98));check(remoteActions.isEmpty)
  app.remote.table.keyDown(with:event(48,.control));check(remoteActions==["nextTab"])
  app.remote.table.keyDown(with:event(48,[.control,.shift]));check(remoteActions.last=="previousTab")
  // Real App tab routing wraps while offline and never starts authentication or a client.
  var tabs=[ConnectionTab]()
  for i in 0..<2{
   let process=SSHConnection(arguments:["60"],helper:"/unused",executable:"/unused",command:"/bin/sleep"),auth=NSWindow(contentRect:NSRect(x:0,y:0,width:100,height:100),styleMask:[.titled],backing:.buffered,defer:false);auth.isReleasedWhenClosed=false
   tabs.append(ConnectionTab(Session(name:"offline-\(i)",host:"offline-\(i).invalid",user:"fixture",port:22,key:""),"fixture-\(UUID().uuidString)",process,auth,root.path,defaults:defaults))
  }
  defer{for tab in tabs{tab.stop();tab.auth?.close()};app.connections=[]}
  app.connections=tabs;app.activateTab(0);app.paneCommand(false,"previousTab");check(app.selectedTab==1);app.paneCommand(false,"nextTab");check(app.selectedTab==0)
  let commands=CommanderMenus.build(target:app,action:#selector(App.menuCommand)).flatMap{$0.submenu!.items}
  let sorts=commands.filter{FileKeyAction.sortKeys[$0.identifier?.rawValue ?? ""] != nil};check(sorts.count==5 && sorts.allSatisfy{$0.keyEquivalentModifierMask==[.command,.option] && $0.image != nil})
  check(clients==0 && !app.window.isVisible && tabs.allSatisfy{$0.auth?.isVisible != true})
  print("PASS: actual native key events for folder/properties/navigation/Return/Tab, modified function keys refused, focus-aware equivalents leave text editing intact, five sorts preserve selected names and pinned parent/directories, extension header, filter focus, offline tab cycling/wrap and offline file refusal; isolated data, no clipboard/auth/client/network")
 }
}
