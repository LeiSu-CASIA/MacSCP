import Cocoa
@main struct NativeCommanderAppearanceTests {
 static func views(_ view:NSView)->[NSView]{[view]+view.subviews.flatMap{views($0)}}
 static func main()throws {
  NSApplication.shared.setActivationPolicy(.prohibited)
  let fm=FileManager.default,root=fm.temporaryDirectory.appendingPathComponent("native-commander-appearance-"+UUID().uuidString)
  try fm.createDirectory(at:root.appendingPathComponent("local/项目资料"),withIntermediateDirectories:true)
  try Data("offscreen test".utf8).write(to:root.appendingPathComponent("local/说明.txt"))
  let suite="macscp-appearance-"+UUID().uuidString
  let isolated=UserDefaults(suiteName:suite)!
  defer{try? fm.removeItem(at:root);isolated.removePersistentDomain(forName:suite)}
  var clientCalls=0
  let app=App(defaults:isolated,dataDirectory:root.appendingPathComponent("profile"),initialLocalDirectory:root.appendingPathComponent("local").path,automaticLogin:false,showsMainWindow:false,frameAutosaveName:nil,clientProvider:{_,_ in clientCalls+=1;throw SFTPError.message("unexpected connection")})
  app.applicationDidFinishLaunching(Notification(name:NSApplication.didFinishLaunchingNotification))
  let progress=SSHConnection(arguments:["60"],helper:"/unused",executable:"/unused",command:"/bin/sleep");defer{progress.stop()}
  let auth=NSWindow(contentRect:NSRect(x:0,y:0,width:200,height:100),styleMask:[.titled],backing:.buffered,defer:false);auth.isReleasedWhenClosed=false
  let site=Session(name:"示例服务器",host:"example.invalid",user:"demo",port:22,key:"")
  let tab=ConnectionTab(site,"appearance-fixture-socket",progress,auth,app.local.currentPath,defaults:isolated);tab.connected=true
  app.connections=[tab];app.selectedTab=0;app.session=site;app.socket=tab.socket;app.terminal=progress;app.auth=auth
  app.local.acceptPath("/Users/demo/Documents");app.local.entries=[Entry(name:"..",size:0,dir:true),Entry(name:"项目资料",size:0,dir:true,date:"2026/11/4 10:00",permissions:"755"),Entry(name:"说明.txt",size:2048,dir:false,date:"2026/11/4 10:05",permissions:"644"),Entry(name:"data.csv",size:51200,dir:false,date:"2026/11/4 10:10",permissions:"644")];app.local.reload()
  app.remote.acceptPath("/home/demo/project")
  app.remote.entries=[Entry(name:"..",size:0,dir:true),Entry(name:"数据",size:0,dir:true,date:"2026/11/4 10:20",permissions:"755"),Entry(name:"README.md",size:2048,dir:false,date:"2026/11/4 10:25",permissions:"644"),Entry(name:"results.csv",size:124800,dir:false,date:"2026/11/4 10:30",permissions:"644")]
  for pane in [app.local,app.remote]{
   pane.entries += [Entry(name:"analysis.py",size:16384,dir:false,date:"2026/11/4 09:20",permissions:"644"),Entry(name:"backup.zip",size:33554432,dir:false,date:"2026/11/3 23:00",permissions:"644"),Entry(name:"config.json",size:1024,dir:false,date:"2026/11/4 09:48",permissions:"644"),Entry(name:"deploy.sh",size:3072,dir:false,date:"2026/11/4 08:45",permissions:"755")]
  };app.local.reload()
  app.remote.reload();app.rebuildTabs();app.status.stringValue="界面预览 · 示例数据 · 未建立网络连接"
  app.jobs=[TransferJob(up:true,source:"/Users/demo/Documents/说明.txt",destination:"/home/demo/project/说明.txt",directory:false,size:2048)]
  app.reloadQueue()
  precondition(app.local.table.rowHeight==25 && app.remote.table.rowHeight==25)
  let buttons=views(app.window.contentView!).compactMap{$0 as? NSButton}
  let styled=buttons.filter{if $0.action == #selector(App.quickFileAction){return false};if let key=$0.identifier?.rawValue{return CommanderAppearance.style(key) != nil};return false}
  precondition(!styled.isEmpty && styled.allSatisfy{$0.image != nil && !($0.toolTip ?? "").isEmpty})
  precondition(app.queuePauseControls.count==2 && app.queuePauseControls.allSatisfy{$0.title=="暂停队列" && $0.action == #selector(App.togglePause)})
  app.togglePause();precondition(app.paused && app.transfers.isSuspended && app.queuePauseControls.allSatisfy{$0.title=="继续队列" && $0.state == .on && $0.image != nil})
  let pause=NSApp.mainMenu!.items.flatMap{$0.submenu?.items ?? []}.first{$0.identifier?.rawValue=="pause"}!
  _ = app.validateMenuItem(pause);precondition(pause.title=="继续全部传输" && pause.state == .on)
  app.togglePause();precondition(!app.paused && app.queuePauseControls.allSatisfy{$0.title=="暂停队列" && $0.state == .off})
  for group in CommanderMenus.groups {for command in group.1{precondition(CommanderAppearance.image(command.identifier) != nil,"missing system symbol for "+command.identifier)}}
  for pane in [app.local,app.remote] {
   precondition(pane.transferControl?.image != nil && pane.transferControl?.toolTip?.contains("F5")==true)
   precondition(pane.table.menu!.items.allSatisfy{$0.image != nil})
   let name=pane.table.tableColumns.first{$0.identifier.rawValue=="name"}!
   let cell=pane.tableView(pane.table,viewFor:name,row:0) as! CommanderFileCell
   cell.frame=NSRect(x:0,y:0,width:220,height:21);cell.layoutSubtreeIfNeeded()
   precondition(cell.imageView!.image != nil && cell.imageView!.frame.width==16 && cell.textField!.frame.width>100)
   let size=pane.table.tableColumns.first{$0.identifier.rawValue=="size"}!
   precondition(size.headerCell.alignment == .right && (pane.tableView(pane.table,viewFor:size,row:0) as! CommanderTextCell).textField!.alignment == .right)
  }
  let reuse=CommanderFileCell(frame:NSRect(x:0,y:0,width:220,height:21))
  reuse.configure(Entry(name:"broken",size:0,dir:false,symbolicLink:true,linkTarget:"missing",linkUnavailable:true))
  precondition(reuse.textField!.stringValue.hasPrefix("↗ ") && reuse.textField!.textColor == .systemRed && reuse.toolTip!.contains("无法访问"))
  reuse.configure(Entry(name:"plain.txt",size:1,dir:false))
  precondition(reuse.textField!.stringValue=="plain.txt" && reuse.textField!.textColor == .labelColor && reuse.toolTip=="plain.txt" && reuse.imageView?.image != nil)
  reuse.backgroundStyle = .emphasized;precondition(reuse.textField!.textColor == .alternateSelectedControlTextColor)
  reuse.configure(Entry(name:"broken-again",size:0,dir:false,symbolicLink:true,linkUnavailable:true));precondition(reuse.textField!.textColor == .alternateSelectedControlTextColor)
  reuse.backgroundStyle = .normal;precondition(reuse.textField!.textColor == .systemRed)
  precondition(views(app.window.contentView!).contains{$0 is CommanderWorkspace})
  let menuStrip=views(app.window.contentView!).compactMap{$0 as? CommanderMenuStrip}.first!
  precondition(menuStrip.menus.count==CommanderMenus.groups.count)
  for (button,group) in zip(menuStrip.menus,CommanderMenus.groups){
   precondition(button.menu!.items.dropFirst().map{$0.identifier!.rawValue}==group.1.map{$0.identifier})
   precondition(button.menu!.items.dropFirst().allSatisfy{$0.target === app && $0.action == #selector(App.menuCommand) && $0.keyEquivalent.isEmpty})
  }
  for width:CGFloat in [1180,900] {
   app.window.setContentSize(NSSize(width:width,height:780));app.window.contentView!.layoutSubtreeIfNeeded()
   precondition(app.window.contentView!.frame.width<=width+1)
   if width==1180 {
    let main=views(app.window.contentView!).compactMap{$0 as? QueueToolbar}.first{$0.bar.arrangedSubviews.contains(app.transferPresetPicker)}!
    precondition(main.bar.fittingSize.width<=main.contentSize.width+1,"main commands clipped at default width")
   }
   for pane in [app.local,app.remote]{let button=pane.transferControl!;precondition(pane.frame.width>=400 && button.frame.width>=button.fittingSize.width-1 && button.frame.maxX<=pane.bounds.width)}
  }
  app.connections=Array(repeating:tab,count:14);app.rebuildTabs();app.window.setContentSize(NSSize(width:900,height:660));app.window.contentView!.layoutSubtreeIfNeeded()
  precondition(app.window.contentView!.frame.width<=901 && app.local.frame.height>=350 && app.queueTable.enclosingScrollView!.frame.height>=76)
  let sessionScroll=views(app.window.contentView!).compactMap{$0 as? QueueToolbar}.first{$0.bar === app.tabBar}!
  precondition(sessionScroll.documentView!.frame.width>sessionScroll.contentSize.width)
  app.connections=[tab];app.rebuildTabs()
  app.window.setContentSize(NSSize(width:1180,height:780));app.window.contentView!.layoutSubtreeIfNeeded()
  app.local.table.selectRowIndexes(IndexSet(integer:2),byExtendingSelection:false);app.remote.table.selectRowIndexes(IndexSet(integer:2),byExtendingSelection:false)
  app.window.contentView!.layoutSubtreeIfNeeded()
  if CommandLine.arguments.count>1 {
   app.status.stringValue="界面预览 · 示例数据 · 未建立网络连接"
   if CommandLine.arguments.count>2,let position=Double(CommandLine.arguments[2]),let split=views(app.window.contentView!).compactMap({$0 as? CommanderFileSplitView}).first{split.setPosition(CGFloat(position),ofDividerAt:0);app.window.contentView!.layoutSubtreeIfNeeded()}
   let view=app.window.contentView!,bounds=view.bounds
   guard let bitmap=view.bitmapImageRepForCachingDisplay(in:bounds) else{fatalError("cannot create offscreen bitmap")}
   view.cacheDisplay(in:bounds,to:bitmap)
   guard let canvas=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:bitmap.pixelsWide,pixelsHigh:bitmap.pixelsHigh,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0),let context=NSGraphicsContext(bitmapImageRep:canvas) else{fatalError("cannot create preview background")}
   NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=context
   app.window.effectiveAppearance.performAsCurrentDrawingAppearance{app.window.backgroundColor.setFill();NSBezierPath(rect:NSRect(origin:.zero,size:canvas.size)).fill();let snapshot=NSImage(size:bounds.size);snapshot.addRepresentation(bitmap);snapshot.draw(in:NSRect(origin:.zero,size:canvas.size),from:.zero,operation:.sourceOver,fraction:1)}
   NSGraphicsContext.restoreGraphicsState()
   guard let png=canvas.representation(using:.png,properties:[:]) else{fatalError("cannot encode offscreen bitmap")}
   try png.write(to:URL(fileURLWithPath:CommandLine.arguments[1]));print("Offscreen preview: "+CommandLine.arguments[1])
  }
  tab.connected=false;app.refreshConnectionPresentation()
  precondition(!app.local.transferControl!.isEnabled && !app.remote.transferControl!.isEnabled && clientCalls==0 && !app.window.isVisible && !auth.isVisible)
  app.jobs=[];app.window.close();auth.close()
  print("PASS: real App toolbar/menu symbols and keyboard hints, pause/resume state/action synchronization, native file type cells and safe reuse after broken links, right-aligned sizes, 900/1180 point layouts, disabled connection state retained; no visible window/login/network")
 }
}
