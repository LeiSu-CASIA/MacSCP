import Cocoa
final class SyncContentsController:NSWindowController,NSWindowDelegate,NSOutlineViewDataSource,NSOutlineViewDelegate {
 final class Item {let path:String;init(_ path:String){self.path=path}}
 let deletion:Bool
 private(set) var contents:SyncContents
 let outline=NSOutlineView(),summary=NSTextField(labelWithString:"")
 private var items=[String:Item]();var onApply:((SyncContents)->Void)?,onClosed:(()->Void)?
 init(contents:SyncContents,deletion:Bool=false){self.contents=contents;self.deletion=deletion;for path in contents.manifest.keys{items[path]=Item(path)}
  let window=NSWindow(contentRect:NSRect(x:0,y:0,width:680,height:520),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false);window.title=(deletion ? "选择清理内容 · " : "选择目录内容 · ")+contents.root;window.minSize=NSSize(width:520,height:400);window.isReleasedWhenClosed=false;window.appearance=NSAppearance(named:.aqua)
  super.init(window:window);window.delegate=self
  let stack=NSStackView();stack.orientation = .vertical;stack.spacing=9;stack.alignment = .leading;stack.edgeInsets=NSEdgeInsets(top:12,left:12,bottom:12,right:12);stack.translatesAutoresizingMaskIntoConstraints=false;window.contentView!.addSubview(stack);NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo:window.contentView!.leadingAnchor),stack.trailingAnchor.constraint(equalTo:window.contentView!.trailingAnchor),stack.topAnchor.constraint(equalTo:window.contentView!.topAnchor),stack.bottomAnchor.constraint(equalTo:window.contentView!.bottomAnchor)])
  let explanation=NSTextField(wrappingLabelWithString:deletion ? "选择要清理的文件和空目录；勾选完整子树时，其目录会一并清理，半选目录会保留。此处只返回预览，执行前还会确认。本地移到废纸篓，远程永久删除。" : "只传输勾选的文件或空目录，并创建必要的父目录。点击目录复选框可选择其整个子树；半选表示仅选择了部分内容。此处不执行删除。")
  explanation.font = .systemFont(ofSize:12);explanation.textColor=deletion ? .systemRed : .labelColor;stack.addArrangedSubview(explanation);explanation.widthAnchor.constraint(equalTo:stack.widthAnchor,constant:-24).isActive=true
  let bar=NSStackView();for(title,action) in [("全选",#selector(selectAllContents)),("全不选",#selector(selectNone)),("展开全部",#selector(expandAll)),("折叠",#selector(collapseAll)),("确认选择",#selector(apply))]{let button=NSButton(title:title,target:self,action:action);button.bezelStyle = .rounded;bar.addArrangedSubview(button)};stack.addArrangedSubview(bar)
  for(id,title,width) in [("path","文件 / 目录",350.0),("size","大小",80.0),("time","修改时间",180.0)]{let column=NSTableColumn(identifier:.init(id));column.title=title;column.width=width;column.minWidth=id=="path" ? 120 : id=="time" ? 150 : 60;outline.addTableColumn(column)}
  outline.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle;outline.outlineTableColumn=outline.tableColumns[0];outline.dataSource=self;outline.delegate=self;outline.rowHeight=27;outline.style = .plain;outline.usesAlternatingRowBackgroundColors=true
  let scroll=NSScrollView();scroll.documentView=outline;scroll.hasVerticalScroller=true;scroll.hasHorizontalScroller=true;stack.addArrangedSubview(scroll);scroll.widthAnchor.constraint(equalTo:stack.widthAnchor,constant:-24).isActive=true;scroll.heightAnchor.constraint(greaterThanOrEqualToConstant:220).isActive=true
  stack.addArrangedSubview(summary);summary.font = .systemFont(ofSize:12);reload();outline.expandItem(items[contents.root]);window.center()
 }
 required init?(coder:NSCoder){fatalError()}
 func outlineView(_ outlineView:NSOutlineView,numberOfChildrenOfItem item:Any?)->Int{guard let item=item as? Item else{return 1};return contents.children[item.path]?.count ?? 0}
 func outlineView(_ outlineView:NSOutlineView,child index:Int,ofItem item:Any?)->Any{if let item=item as? Item{return items[contents.children[item.path]![index]]!};return items[contents.root]!}
 func outlineView(_ outlineView:NSOutlineView,isItemExpandable item:Any)->Bool{guard let item=item as? Item else{return false};return !(contents.children[item.path]?.isEmpty ?? true)}
 func outlineView(_ outlineView:NSOutlineView,viewFor column:NSTableColumn?,item:Any)->NSView?{guard let item=item as? Item,let node=contents.manifest[item.path] else{return nil}
  if column?.identifier.rawValue=="path"{let button=NSButton(checkboxWithTitle:(item.path as NSString).lastPathComponent+(node.directory ? "/" : ""),target:self,action:#selector(toggle));button.identifier = .init(item.path);button.allowsMixedState=true;switch contents.state(item.path){case .on:button.state = .on;case .off:button.state = .off;case .mixed:button.state = .mixed};button.font = .systemFont(ofSize:12);if deletion{button.contentTintColor = .systemRed};button.toolTip=item.path;button.setAccessibilityLabel(item.path);return button}
  let cell=CommanderTextCell(frame:.zero);cell.configure(column?.identifier.rawValue=="size" ? (node.directory ? "—" : ByteCountFormatter.string(fromByteCount:Int64(clamping:node.size),countStyle:.file)) : SyncComparison.timeDescription(node.modified),alignment:column?.identifier.rawValue=="size" ? .right : .left);return cell
 }
 @objc func toggle(_ sender:NSButton){guard let path=sender.identifier?.rawValue else{return};set(path,on:contents.state(path) != .on)}
 func set(_ path:String,on:Bool){contents.set(path,on:on);reload()}
 private func reload(){outline.reloadData();summary.stringValue=(deletion ? "将清理 \(contents.selectedRoots.count) 个项目 / 子树 · " : "")+contents.summary}
 @objc func selectAllContents(){contents.setAll(true);reload()}
 @objc func selectNone(){contents.setAll(false);reload()}
 @objc func expandAll(){outline.expandItem(nil,expandChildren:true)}
 @objc func collapseAll(){outline.collapseItem(nil,collapseChildren:true);outline.expandItem(items[contents.root])}
 @objc func apply(){onApply?(contents);close()}
 func windowWillClose(_ notification:Notification){onClosed?()}
}
