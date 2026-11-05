import Cocoa
final class RecoveryController:NSWindowController,NSWindowDelegate,NSTableViewDataSource,NSTableViewDelegate {
 private(set) var selection:RecoverySelection
 let table=NSTableView(),summary=NSTextField(labelWithString:""),result=NSTextField(labelWithString:""),details=NSTextView()
 let restoreButton=NSButton(),removeButton=NSButton()
 var onRestore:(([RecoveryItem])->Void)?,onRemove:(([RecoveryItem])->Void)?,onRefresh:(()->Void)?,onClosed:(()->Void)?
 init(items:[RecoveryItem],connected:Set<String>){
  selection=RecoverySelection(items:items,connected:connected)
  let window=NSWindow(contentRect:NSRect(x:0,y:0,width:1080,height:660),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false);window.isReleasedWhenClosed=false
  super.init(window:window);window.title="恢复任务 · 核对后勾选";window.delegate=self;window.minSize=NSSize(width:800,height:560);window.center()
  let root=NSStackView();root.orientation = .vertical;root.spacing=8;root.edgeInsets=NSEdgeInsets(top:10,left:10,bottom:10,right:10);root.translatesAutoresizingMaskIntoConstraints=false;window.contentView!.addSubview(root)
  NSLayoutConstraint.activate([root.leadingAnchor.constraint(equalTo:window.contentView!.leadingAnchor),root.trailingAnchor.constraint(equalTo:window.contentView!.trailingAnchor),root.topAnchor.constraint(equalTo:window.contentView!.topAnchor),root.bottomAnchor.constraint(equalTo:window.contentView!.bottomAnchor)])
  let hint=NSTextField(wrappingLabelWithString:"勾选后恢复。中转按组处理，需登录两端；目录和已有暂存会在执行前重新校验。可保持本窗口打开后连接服务器，再刷新状态。")
  root.addArrangedSubview(hint);hint.widthAnchor.constraint(equalTo:root.widthAnchor,constant:-20).isActive=true
  let bar=NSStackView();for (title,action) in [("刷新记录",#selector(refresh)),("勾选已登录任务",#selector(selectReady)),("全不选",#selector(selectNone))]{bar.addArrangedSubview(NSButton(title:title,target:self,action:action))}
  restoreButton.title="恢复勾选项";restoreButton.target=self;restoreButton.action = #selector(restoreChecked);bar.addArrangedSubview(restoreButton)
  removeButton.title="移除勾选记录…";removeButton.target=self;removeButton.action = #selector(removeChecked);bar.addArrangedSubview(removeButton)
  root.addArrangedSubview(bar)
  for (id,title,width) in [("selected","勾选",45.0),("kind","类型",85.0),("source","源",370.0),("destination","目标",370.0),("status","登录 / 校验状态",260.0)]{let column=NSTableColumn(identifier:.init(id));column.title=title;column.width=width;table.addTableColumn(column)}
  table.dataSource=self;table.delegate=self;table.allowsMultipleSelection=false;table.rowHeight=29
  let list=NSScrollView();list.documentView=table;list.hasHorizontalScroller=true;list.hasVerticalScroller=true;root.addArrangedSubview(list);list.widthAnchor.constraint(equalTo:root.widthAnchor,constant:-20).isActive=true;list.heightAnchor.constraint(greaterThanOrEqualToConstant:200).isActive=true
  root.addArrangedSubview(summary);root.addArrangedSubview(result);result.textColor = .secondaryLabelColor;result.lineBreakMode = .byTruncatingMiddle;result.widthAnchor.constraint(equalTo:root.widthAnchor,constant:-20).isActive=true
  details.frame=NSRect(x:0,y:0,width:1040,height:160);details.textContainer?.widthTracksTextView=true;details.isHorizontallyResizable=false;details.isEditable=false;details.isRichText=false;details.font = .monospacedSystemFont(ofSize:11,weight:.regular);details.autoresizingMask = .width;details.string="选择一行查看完整路径和原传输设置。默认不勾选任何任务。"
  let detailScroll=NSScrollView();detailScroll.hasVerticalScroller=true;detailScroll.documentView=details;root.addArrangedSubview(detailScroll);detailScroll.widthAnchor.constraint(equalTo:root.widthAnchor,constant:-20).isActive=true;detailScroll.heightAnchor.constraint(equalToConstant:160).isActive=true
  updateControls()
 }
 required init?(coder:NSCoder){fatalError()}
 func update(items:[RecoveryItem],connected:Set<String>){let highlighted=selection.items.indices.contains(table.selectedRow) ? selection.items[table.selectedRow].key : nil;selection.refresh(items:items,connected:connected);table.reloadData();if let key=highlighted,let index=selection.items.firstIndex(where:{$0.key==key}){table.selectRowIndexes(IndexSet(integer:index),byExtendingSelection:false)}else{table.deselectAll(nil)};updateControls()}
 func numberOfRows(in tableView:NSTableView)->Int{selection.items.count}
 func tableView(_ tableView:NSTableView,viewFor column:NSTableColumn?,row:Int)->NSView?{
  let item=selection.items[row]
  if column?.identifier.rawValue=="selected"{let button=NSButton(checkboxWithTitle:"",target:self,action:#selector(toggle));button.identifier = .init(item.key.text);button.state=selection.selected.contains(item.key) ? .on : .off;return button}
  let text:String;switch column?.identifier.rawValue{case "kind":text=item.kind;case "source":text=item.source;case "destination":text=item.destination;default:text=item.status(selection.connected)}
  let label=NSTextField(labelWithString:text);label.lineBreakMode = .byTruncatingMiddle;label.toolTip=text;if !item.missingSites(selection.connected).isEmpty{label.textColor = .secondaryLabelColor};return label
 }
 @objc func toggle(_ sender:NSButton){guard let value=sender.identifier?.rawValue,let item=selection.items.first(where:{$0.key.text==value}) else{return};selection.set(item.key,selected:sender.state == .on);updateControls()}
 func setChecked(_ key:RecoveryKey,_ value:Bool){selection.set(key,selected:value);table.reloadData();updateControls()}
 @objc func selectReady(){selection.selectReady();table.reloadData();updateControls()}
 @objc func selectNone(){selection.clear();table.reloadData();updateControls()}
 @objc func refresh(){onRefresh?()}
 @objc func restoreChecked(){guard selection.canRestore else{return};onRestore?(selection.checked)}
 @objc func removeChecked(){guard !selection.checked.isEmpty else{return};onRemove?(selection.checked)}
 func tableViewSelectionDidChange(_ notification:Notification){guard selection.items.indices.contains(table.selectedRow) else{return};details.string=selection.items[table.selectedRow].details}
 private func updateControls(){let checked=selection.checked;let offline=checked.filter{!$0.missingSites(selection.connected).isEmpty}.count;summary.stringValue="已勾选 \(checked.count) / \(selection.items.count) 项 · \(offline) 项待登录 · 中转按一组计";restoreButton.isEnabled=selection.canRestore;removeButton.isEnabled = !checked.isEmpty}
 func report(_ message:String,errors:[String]=[]){result.stringValue=message;result.toolTip=message+(errors.isEmpty ? "" : "\n"+errors.joined(separator:"\n"));if !errors.isEmpty{details.string=message+"\n\n"+errors.prefix(200).joined(separator:"\n\n")}}
 func windowWillClose(_ notification:Notification){onClosed?()}
}
