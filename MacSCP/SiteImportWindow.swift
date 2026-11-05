import Cocoa
final class SiteImportDetailsScrollView:NSScrollView {
 override func tile(){super.tile();guard let text=documentView as? NSTextView else{return};let size=contentSize;guard size.width>0 else{return};if abs(text.frame.width-size.width)>0.5 || text.frame.height<size.height{text.setFrameSize(NSSize(width:size.width,height:max(size.height,text.frame.height)))}}
}
final class SiteImportController:NSWindowController,NSTableViewDataSource,NSTableViewDelegate,NSSearchFieldDelegate,NSWindowDelegate {
 let selection:SiteImportSelection;let store:SiteStore;let table=NSTableView();let search=NSSearchField();let details=NSTextView();let summary=NSTextField(labelWithString:"");let result=NSTextField(labelWithString:"");let importButton=NSButton();private(set) var visible=[SiteImportCandidate]()
 var onImported:((Int)->Void)?;var onClosed:(()->Void)?
 init(plan:SiteImportPlan,store:SiteStore){selection=SiteImportSelection(plan:plan,existing:store.sites);self.store=store
  let window=NSWindow(contentRect:NSRect(x:0,y:0,width:1000,height:660),styleMask:[.titled,.closable,.resizable,.miniaturizable],backing:.buffered,defer:false);window.title="导入站点 · "+plan.format.rawValue;window.minSize=NSSize(width:800,height:540);window.appearance=NSAppearance(named:.aqua);window.isReleasedWhenClosed=false
  super.init(window:window);window.delegate=self
  let root=NSStackView();root.orientation = .vertical;root.spacing=10;root.edgeInsets=NSEdgeInsets(top:14,left:14,bottom:14,right:14);root.translatesAutoresizingMaskIntoConstraints=false;window.contentView!.addSubview(root);NSLayoutConstraint.activate([root.leadingAnchor.constraint(equalTo:window.contentView!.leadingAnchor),root.trailingAnchor.constraint(equalTo:window.contentView!.trailingAnchor),root.topAnchor.constraint(equalTo:window.contentView!.topAnchor),root.bottomAnchor.constraint(equalTo:window.contentView!.bottomAnchor)])
  let intro=NSTextField(wrappingLabelWithString:"勾选要导入的站点。相同用户名、地址和端口将合并更新；重复来源一次只能选择一项。Windows 私钥需在 Mac 重新选择，密码及主机信任记录由连接时验证。")
  root.addArrangedSubview(intro);intro.widthAnchor.constraint(equalTo:root.widthAnchor,constant:-28).isActive=true
  search.placeholderString="筛选站点名称、服务器或迁移提示";search.delegate=self;search.target=self;search.action = #selector(filterChanged);root.addArrangedSubview(search);search.widthAnchor.constraint(equalTo:root.widthAnchor,constant:-28).isActive=true
  for(id,title,width) in [("check","导入",45.0),("name","站点",190.0),("server","服务器",225.0),("action","操作",90.0),("notes","兼容情况",380.0)] {let c=NSTableColumn(identifier:.init(id));c.title=title;c.width=width;table.addTableColumn(c)}
  table.delegate=self;table.dataSource=self;table.rowHeight=25;table.usesAlternatingRowBackgroundColors=true;table.allowsMultipleSelection=false
  let scroll=NSScrollView();scroll.documentView=table;scroll.hasVerticalScroller=true;scroll.hasHorizontalScroller=true;scroll.borderType = .bezelBorder;root.addArrangedSubview(scroll);scroll.widthAnchor.constraint(equalTo:root.widthAnchor,constant:-28).isActive=true;scroll.heightAnchor.constraint(greaterThanOrEqualToConstant:150).isActive=true
  let info=SiteImportDetailsScrollView();details.frame=NSRect(x:0,y:0,width:950,height:155);details.isVerticallyResizable=true;details.maxSize=NSSize(width:CGFloat.greatestFiniteMagnitude,height:CGFloat.greatestFiniteMagnitude);details.isEditable=false;details.isRichText=false;details.font = .systemFont(ofSize:12);details.textContainer?.widthTracksTextView=true;details.isHorizontallyResizable=false;details.autoresizingMask = .width;info.documentView=details;info.hasVerticalScroller=true;info.borderType = .bezelBorder;root.addArrangedSubview(info);info.widthAnchor.constraint(equalTo:root.widthAnchor,constant:-28).isActive=true;info.heightAnchor.constraint(equalToConstant:155).isActive=true
  summary.font = .systemFont(ofSize:12);root.addArrangedSubview(summary);result.lineBreakMode = .byTruncatingMiddle;result.setContentCompressionResistancePriority(.defaultLow,for:.horizontal);root.addArrangedSubview(result);result.widthAnchor.constraint(lessThanOrEqualTo:root.widthAnchor,constant:-28).isActive=true
  let buttons=NSStackView();buttons.spacing=8;for(title,action) in [("勾选显示项",#selector(selectAllEligible)),("取消全部勾选",#selector(selectNone)),("刷新现有站点",#selector(refreshExisting))]{buttons.addArrangedSubview(NSButton(title:title,target:self,action:action))};importButton.title="导入勾选站点";importButton.target=self;importButton.action = #selector(importSelected);importButton.bezelStyle = .rounded;buttons.addArrangedSubview(importButton);buttons.addArrangedSubview(NSButton(title:"关闭",target:self,action:#selector(closeWindow)));root.addArrangedSubview(buttons)
  reload();window.center()
 }
 required init?(coder:NSCoder){fatalError()}
 func numberOfRows(in tableView:NSTableView)->Int{visible.count}
 func tableView(_ tableView:NSTableView,viewFor tableColumn:NSTableColumn?,row:Int)->NSView? {
  guard visible.indices.contains(row) else{return nil};let item=visible[row],key=tableColumn?.identifier.rawValue ?? ""
  if key=="check"{let check=NSButton(checkboxWithTitle:"",target:self,action:#selector(toggleCheck));check.identifier = .init("siteImport.\(item.id)");check.state=selection.checked.contains(item.id) ? .on : .off;check.isEnabled=item.eligible;check.toolTip=item.name;return check}
  let text:String
  switch key {case "name":text=item.name;case "server":text=item.address;case "action":text=selection.action(item);default:text=([item.issue].compactMap{$0}+item.notes+(selection.duplicate(item) ? ["同一服务器有多个来源配置，仅导入一个"] : [])+(!selection.changes(item).isEmpty ? ["变更："+selection.changes(item).map{$0.0}.joined(separator:"、")] : [])).joined(separator:"；")}
  let label=NSTextField(labelWithString:text);label.lineBreakMode = .byTruncatingMiddle;label.toolTip=text;if !item.eligible{label.textColor = .secondaryLabelColor};return label
 }
 @objc func toggleCheck(_ sender:NSButton){guard let value=sender.identifier?.rawValue.split(separator:".").last,let id=Int(value) else{return};selection.setChecked(id,sender.state == .on);reload();if let row=visible.firstIndex(where:{$0.id==id}){table.selectRowIndexes(IndexSet(integer:row),byExtendingSelection:false);showDetails()}}
 @objc func filterChanged(){reload()}
 func controlTextDidChange(_ obj:Notification){reload()}
 func reload(){let highlighted=table.selectedRow>=0 && visible.indices.contains(table.selectedRow) ? visible[table.selectedRow].id : nil;let query=search.stringValue.trimmingCharacters(in:.whitespacesAndNewlines);visible=selection.plan.candidates.filter{query.isEmpty || ($0.name+" "+$0.address+" "+($0.issue ?? "")+" "+$0.notes.joined(separator:" ")).localizedCaseInsensitiveContains(query)};table.reloadData();if let id=highlighted,let row=visible.firstIndex(where:{$0.id==id}){table.selectRowIndexes(IndexSet(integer:row),byExtendingSelection:false)}else{table.deselectAll(nil)};let hidden=selection.checked.subtracting(Set(visible.map(\.id))).count;summary.stringValue="显示 \(visible.count) / \(selection.plan.candidates.count) 项，已勾选 \(selection.checked.count) 项"+(hidden>0 ? "（其中 \(hidden) 项不在当前筛选中）" : "");importButton.isEnabled = !selection.checked.isEmpty;showDetails()}
 func tableViewSelectionDidChange(_ notification:Notification){showDetails()}
 func showDetails(){guard visible.indices.contains(table.selectedRow) else{details.string="选中一行查看目录、认证方式和兼容情况。";return};let row=visible[table.selectedRow];details.string=row.detail+"\n导入操作："+selection.action(row);let changes=selection.changes(row);if !changes.isEmpty{details.string += "\n将更新以下设置：\n"+changes.map{"\($0.0)：\($0.1.isEmpty ? "（空）" : $0.1) → \($0.2.isEmpty ? "（空）" : $0.2)"}.joined(separator:"\n")}}
 @objc func selectAllEligible(){var endpoints=Set<String>();for row in visible where row.eligible{if let site=row.session,endpoints.insert(site.identity).inserted{selection.setChecked(row.id,true)}};reload()}
 @objc func selectNone(){selection.selectNone();reload()}
 @objc func refreshExisting(){selection.refreshExisting(store.sites);result.stringValue="现有站点信息已刷新，请核对更新项。";result.textColor = .secondaryLabelColor;reload()}
 @objc func importSelected(){do{let count=try selection.apply(to:store);selection.selectNone();selection.refreshExisting(store.sites);result.stringValue="已导入 \(count) 个站点配置；可在连接窗口中选择。";result.textColor = .labelColor;reload();onImported?(count)}catch{result.stringValue=error.localizedDescription;result.toolTip=error.localizedDescription;result.textColor = .systemRed}}
 @objc func closeWindow(){close()}
 func windowWillClose(_ notification:Notification){onClosed?()}
}
