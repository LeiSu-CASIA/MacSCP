import Cocoa
@main struct NativeSiteImportTests {
 static func main()throws {
  NSApplication.shared.setActivationPolicy(.prohibited)
  let fm=FileManager.default,root=fm.temporaryDirectory.appendingPathComponent("native-site-import-"+UUID().uuidString)
  try fm.createDirectory(at:root,withIntermediateDirectories:true);defer{try? fm.removeItem(at:root)}
  let source="""
  [Sessions\\alpha]
  HostName=one.example
  UserName=test
  [Sessions\\beta]
  HostName=two.example
  UserName=test
  [Sessions\\alias]
  HostName=one.example
  UserName=test
  RemoteDirectory=/alias
  [Sessions\\unsupported]
  HostName=ftp.example
  FSProtocol=6
  """
  let store=try SiteStore(url:root.appendingPathComponent("sites.json")),plan=try SiteImportPlan.read(Data(source.utf8),fileExtension:"ini")
  let controller=SiteImportController(plan:plan,store:store)
  precondition(!controller.window!.isVisible && !controller.importButton.isEnabled)
  controller.window!.contentView!.layoutSubtreeIfNeeded()
  precondition(controller.table.enclosingScrollView!.frame.height>=150 && controller.details.enclosingScrollView!.frame.height>=150 && controller.details.frame.width>100)
  let checkColumn=controller.table.tableColumns[0]
  let stale=controller.tableView(controller.table,viewFor:checkColumn,row:1) as! NSButton
  precondition(stale.identifier?.rawValue=="siteImport.1")
  let unsupported=controller.tableView(controller.table,viewFor:checkColumn,row:3) as! NSButton
  precondition(!unsupported.isEnabled)
  controller.search.stringValue="beta";controller.filterChanged();precondition(controller.visible.count==1 && controller.visible[0].id==1)
  controller.selectAllEligible();precondition(controller.selection.checked==[1]);controller.selectNone();stale.state = .on;controller.toggleCheck(stale);precondition(controller.selection.checked==[1] && controller.importButton.isEnabled)
  var imported=0;controller.onImported={imported=$0};controller.importSelected()
  precondition(imported==1 && store.sites.map(\.host)==["two.example"] && controller.selection.checked.isEmpty)
  controller.search.stringValue="ftp.example";controller.filterChanged();precondition(controller.visible.count==1 && controller.visible[0].id==3);controller.search.stringValue="";controller.filterChanged();controller.selectAllEligible();precondition(controller.selection.checked==[0,1])
  let alias=controller.tableView(controller.table,viewFor:checkColumn,row:2) as! NSButton;alias.state = .on;controller.toggleCheck(alias);precondition(controller.selection.checked==[1,2])
  controller.table.selectRowIndexes(IndexSet(integer:2),byExtendingSelection:false);controller.showDetails();precondition(controller.details.string.contains("/alias"))
  controller.importSelected();precondition(store.sites.count==2 && store.sites.contains{$0.name=="alias"})
  controller.selection.setChecked(0,true);controller.search.stringValue="beta";controller.filterChanged();controller.selectAllEligible();precondition(controller.selection.checked==[0,1] && controller.summary.stringValue.contains("不在当前筛选中"));controller.search.stringValue="";controller.filterChanged();var changed=store.sites.first{$0.host=="two.example"}!;changed.name="user edit";try store.save(changed)
  controller.importSelected();precondition(controller.result.stringValue.contains("已改变") && store.sites.contains{$0.name=="user edit"} && store.sites.contains{$0.name=="alias"})
  controller.refreshExisting();controller.table.selectRowIndexes(IndexSet(integer:1),byExtendingSelection:false);controller.showDetails();precondition(controller.details.string.contains("user edit → beta"));controller.importSelected();precondition(store.sites.contains{$0.name=="beta"})
  controller.window!.setContentSize(NSSize(width:800,height:540));controller.window!.contentView!.layoutSubtreeIfNeeded();precondition(controller.window!.contentView!.frame.width<=801 && controller.importButton.frame.width>50 && controller.details.frame.width<=controller.details.enclosingScrollView!.contentSize.width+1)
  controller.close()
  print("PASS: hidden native import preview layout/details/filter, stable checkbox identity after filtering, disabled unsupported rows, duplicate endpoint exclusion, selected-only import callback, stale edits rejected/refreshed, 800-point width fits; no window shown or connection attempted")
 }
}
