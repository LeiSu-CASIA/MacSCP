import Cocoa
@main struct NativeDropIntegrationTests {
 static func check(_ value:Bool,file:StaticString = #file,line:UInt = #line){precondition(value,file:file,line:line)}
 static func wait(_ value:()->Bool){let end=Date().addingTimeInterval(5);while !value(),Date()<end{RunLoop.current.run(until:Date().addingTimeInterval(0.01))};check(value())}
 static func main()throws{
  NSApplication.shared.setActivationPolicy(.prohibited)
  let fm=FileManager.default,root=fm.temporaryDirectory.appendingPathComponent("native-drop-integration-"+UUID().uuidString),suite="macscp-native-drop-"+UUID().uuidString,defaults=UserDefaults(suiteName:suite)!
  try fm.createDirectory(at:root.appendingPathComponent("目的"),withIntermediateDirectories:true);defer{try? fm.removeItem(at:root);defaults.removePersistentDomain(forName:suite)}
  let source=root.appendingPathComponent("源 %20 #.txt");try Data("fixture".utf8).write(to:source)
  let board=NSPasteboard(name:.init("macscp-private-drop-test-"+UUID().uuidString));defer{board.releaseGlobally()}
  func publicPayload(){let item=NSPasteboardItem();item.setString(source.absoluteString,forType:.fileURL);board.clearContents();check(board.writeObjects([item]))}
  publicPayload()
  let window=NSWindow(contentRect:NSRect(x:0,y:0,width:900,height:600),styleMask:[.titled],backing:.buffered,defer:false);window.isReleasedWhenClosed=false;defer{window.close()}
  let pane=Pane("本地文件",defaults:defaults);pane.frame=NSRect(x:0,y:0,width:700,height:580);window.contentView!.addSubview(pane);pane.acceptPath(root.path)
  func populate(){pane.entries=[Entry(name:"..",size:0,dir:true),Entry(name:"目的",size:0,dir:true),Entry(name:"普通.txt",size:1,dir:false),Entry(name:"链接",size:0,dir:true,symbolicLink:true)];pane.reload()}
  populate();func row(_ name:String)->Int{pane.entries.firstIndex{$0.name==name}!}
  var targets=[String](),failures=[String]();pane.canReceiveDrop={true};pane.receiveDrop={_ in targets.append(pane.currentPath);return true};pane.receiveDropAt={files,path in check(files.count==1 && files[0].path==source.path);targets.append(path);return true};pane.dropFailure={failures.append($0)}
  let info=MacSCPDraggingFixture();info.draggingPasteboard=board;info.draggingDestinationWindow=window;info.draggingSourceOperationMask = .copy;info.draggingSequenceNumber=1
  check(pane.tableView(pane.table,validateDrop:info,proposedRow:row("目的"),proposedDropOperation:.on) == .copy)
  check(pane.tableView(pane.table,acceptDrop:info,row:row("目的"),dropOperation:.on));check(targets==[root.appendingPathComponent("目的").path])
  check(pane.tableView(pane.table,validateDrop:info,proposedRow:row("普通.txt"),proposedDropOperation:.on) == .copy)
  check(pane.tableView(pane.table,acceptDrop:info,row:-1,dropOperation:.on));check(targets.last==root.path)
  check(pane.tableView(pane.table,validateDrop:info,proposedRow:row("链接"),proposedDropOperation:.on).isEmpty)
  check(!pane.tableView(pane.table,acceptDrop:info,row:row("链接"),dropOperation:.on))
  _ = pane.tableView(pane.table,validateDrop:info,proposedRow:row("目的"),proposedDropOperation:.on);pane.applyFilter();check(!pane.tableView(pane.table,acceptDrop:info,row:row("目的"),dropOperation:.on))
  _ = pane.tableView(pane.table,validateDrop:info,proposedRow:row("目的"),proposedDropOperation:.on);pane.acceptPath(root.appendingPathComponent("目的").path);check(!pane.tableView(pane.table,acceptDrop:info,row:row("目的"),dropOperation:.on));pane.acceptPath(root.path)
  _ = pane.tableView(pane.table,validateDrop:info,proposedRow:row("目的"),proposedDropOperation:.on);info.draggingSequenceNumber+=1;check(!pane.tableView(pane.table,acceptDrop:info,row:row("目的"),dropOperation:.on))
  info.draggingSourceOperationMask = .move;check(pane.tableView(pane.table,validateDrop:info,proposedRow:row("目的"),proposedDropOperation:.on).isEmpty);info.draggingSourceOperationMask = .copy
  let tree=DirectoryTreeView();tree.frame=NSRect(x:700,y:0,width:200,height:580);window.contentView!.addSubview(tree);tree.loader={path,done in done(.success(path==root.path ? [DirectoryTreeNode(path:root.appendingPathComponent("目的").path,name:"目的"),DirectoryTreeNode(path:root.appendingPathComponent("链接").path,name:"链接",link:true)] : []))};tree.canReceiveDrop={true};tree.receiveDrop={_,path in targets.append(path);return true};tree.setRoot(root.path);wait{tree.root?.children != nil}
  let child=tree.root!.children!.first{$0.name=="目的"}!,link=tree.root!.children!.first{$0.name=="链接"}!
  check(tree.outlineView(tree.outline,validateDrop:info,proposedItem:child,proposedChildIndex:-1) == .copy);check(tree.outlineView(tree.outline,acceptDrop:info,item:child,childIndex:-1))
  check(tree.outlineView(tree.outline,validateDrop:info,proposedItem:link,proposedChildIndex:-1).isEmpty)
  _ = tree.outlineView(tree.outline,validateDrop:info,proposedItem:child,proposedChildIndex:-1);tree.reset();check(!tree.outlineView(tree.outline,acceptDrop:info,item:child,childIndex:-1))
  let tab=SessionTabButton(title:"目标服务器",target:nil,action:nil);var available=true,hoverCount=0,received=[DragFile]()
  tab.acceptsDrop={available};tab.hover={hoverCount+=1};tab.receiveDrop={received=$0;return true};tab.dropFailure={failures.append($0)}
  let remote=DragFile(path:"/remote/源.txt",directory:false,size:4,connection:"origin-fixture");let remoteItem=NSPasteboardItem();remoteItem.setData(try JSONEncoder().encode(remote),forType:scpPasteboard);board.clearContents();check(board.writeObjects([remoteItem]))
  check(tab.draggingEntered(info) == .copy && tab.prepareForDragOperation(info));check(hoverCount==0 && tab.performDragOperation(info));check(received.first?.connection=="origin-fixture");tab.draggingExited(info)
  check(tab.draggingEntered(info) == .copy);tab.draggingEnded(info);check(!tab.performDragOperation(info))
  available=false;check(tab.draggingUpdated(info).isEmpty && !tab.performDragOperation(info));available=true
  let malformed=NSPasteboardItem();malformed.setData(Data("invalid".utf8),forType:scpPasteboard);malformed.setString(source.absoluteString,forType:.fileURL);board.clearContents();check(board.writeObjects([malformed]))
  _ = pane.tableView(pane.table,validateDrop:info,proposedRow:row("目的"),proposedDropOperation:.on);check(!pane.tableView(pane.table,acceptDrop:info,row:row("目的"),dropOperation:.on));check(!failures.isEmpty)
  check(!window.isVisible && targets.count==3)
  print("PASS: actual NSTableView/NSOutlineView drag delegates with private named pasteboard and NSDraggingInfo fixture; folder/background/link/source-mask routing, stale listing/path/tree rejection, session-tab copy/private origin/no-hover-switch/offline refusal and malformed-data errors; no general clipboard, user UI or network")
 }
}
