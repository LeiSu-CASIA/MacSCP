import Cocoa
@main struct NativeRecoveryTests {
 static func main()throws{
  NSApplication.shared.setActivationPolicy(.prohibited)
  let a=Session(name:"A",host:"a.invalid",user:"u",port:22,key:""),b=Session(name:"B",host:"b.invalid",user:"u",port:22,key:"")
  let id=UUID(),ordinary=TransferRecord(id:id,site:a,up:true,source:"/local/中文 a.txt",destination:"/remote/a.txt",directory:false,size:123,overwrite:false,resumes:[],completed:[],created:[])
  let other=TransferRecord(id:UUID(),site:b,up:false,source:"/remote/b.txt",destination:"/local/b.txt",directory:false,size:222,overwrite:true,resumes:[],completed:[],created:[])
  let stage=FileManager.default.temporaryDirectory.appendingPathComponent("MacSCP-Relay-"+UUID().uuidString).path
  let down=TransferRecord(id:UUID(),site:a,up:false,source:"/source/c.txt",destination:stage+"/c.txt",directory:false,size:333,overwrite:false,resumes:[],completed:[],created:[],policy:TransferPolicy(include:"*.txt"))
  let up=TransferRecord(id:UUID(),site:b,up:true,source:stage+"/c.txt",destination:"/destination/c.txt",directory:false,size:333,overwrite:false,resumes:[],completed:[],created:[])
  let relay=RelayRecord(id:id,staging:stage,download:down,upload:up)
  precondition(RecoveryItem.relay(relay).details.contains("包含：*.txt"))
  let items:[RecoveryItem]=[.transfer(ordinary),.transfer(other),.relay(relay)]
  var model=RecoverySelection(items:items,connected:[a.identity]);precondition(model.checked.isEmpty && !model.canRestore)
  model.selectReady();precondition(model.selected==[.transfer(id)] && model.canRestore)
  model.set(.relay(id),selected:true);precondition(model.checked.count==2 && !model.canRestore) // Kind separates equal UUIDs.
  model.refresh(items:items,connected:[a.identity,b.identity]);precondition(model.canRestore && model.checked.count==2)
  model.refresh(items:[items[2],items[1]],connected:[b.identity]);precondition(model.selected==[.relay(id)] && !model.canRestore)
  model.clear();precondition(model.checked.isEmpty)
  let endpoints=[a.identity:RecoveryEndpoint(site:a,socket:"socket-a"),b.identity:RecoveryEndpoint(site:b,socket:"socket-b")]
  let plan=try PreparedRecovery.make(.transfer(ordinary),connections:endpoints,factory:{_,_ in fatalError("preparation must not open network clients")})
  precondition(plan.jobs.count==1 && plan.sessionsStillMatch(endpoints))
  precondition(!plan.sessionsStillMatch([a.identity:RecoveryEndpoint(site:a,socket:"replacement")]))
  do{_ = try PreparedRecovery.make(.relay(relay),connections:[a.identity:endpoints[a.identity]!],factory:{_,_ in fatalError()});fatalError("missing endpoint accepted")}catch{}

  let controller=RecoveryController(items:items,connected:[a.identity])
  controller.window!.contentView!.layoutSubtreeIfNeeded();precondition(!controller.window!.isVisible && controller.table.enclosingScrollView!.frame.height>=200 && controller.details.enclosingScrollView!.frame.height==160 && controller.details.frame.height>0)
  precondition(!controller.restoreButton.isEnabled && !controller.removeButton.isEnabled)
  let checkbox=controller.tableView(controller.table,viewFor:controller.table.tableColumns[0],row:0) as! NSButton
  controller.update(items:items.reversed(),connected:[a.identity]);checkbox.state = .on;controller.toggle(checkbox)
  precondition(controller.selection.selected==[.transfer(id)] && controller.restoreButton.isEnabled)
  controller.setChecked(.relay(id),true);precondition(!controller.restoreButton.isEnabled && controller.removeButton.isEnabled)
  var restored=[RecoveryKey](),removed=[RecoveryKey]()
  controller.onRestore={restored=$0.map{$0.key}};controller.onRemove={removed=$0.map{$0.key}}
  controller.restoreChecked();precondition(restored.isEmpty);controller.removeChecked();precondition(Set(removed)==[.transfer(id),.relay(id)])
  controller.update(items:items,connected:[a.identity,b.identity]);controller.restoreChecked();precondition(Set(restored)==[.transfer(id),.relay(id)])
  controller.table.selectRowIndexes(IndexSet(integer:0),byExtendingSelection:false);controller.tableViewSelectionDidChange(Notification(name:NSTableView.selectionDidChangeNotification));precondition(controller.details.string.contains(ordinary.source) && controller.details.string.contains(ordinary.destination))
  controller.report("1 项失败",errors:["暂存文件不存在"]);precondition(controller.details.string.contains("暂存文件不存在"))
  controller.selectNone();precondition(!controller.removeButton.isEnabled)
  print("PASS: explicit per-item selection, offline restore blocked/delete allowed, login refresh preserves intent, typed key separates UUID collisions, endpoint changes rejected before execution; hidden native controls/details/checkbox identity remain correct after row reorder; no network/window shown")
 }
}
