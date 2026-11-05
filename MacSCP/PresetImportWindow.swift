import Cocoa

final class PresetImportController:NSWindowController,NSWindowDelegate,NSTableViewDataSource,NSTableViewDelegate,NSSearchFieldDelegate {
 private(set) var closed=false
 let localCurrent:TransferPreferences?
 private(set) var selection:PresetImportSelection
 let table=NSTableView(),search=NSSearchField(),details=NSTextView(),summary=NSTextField(labelWithString:""),result=NSTextField(wrappingLabelWithString:"")
 let defaults=NSButton(checkboxWithTitle:"导入默认配置与自动匹配开关",target:nil,action:nil),current=NSButton(checkboxWithTitle:"同时恢复文件中的当前传输设置",target:nil,action:nil),applyButton=NSButton(title:"写入设置草稿",target:nil,action:nil)
 private(set) var visible=[PresetImportCandidate]()
 var onApply:((PresetImportResult)throws->Void)?,onClosed:(()->Void)?
 init(plan:PresetImportPlan,library:TransferPresetLibrary,current currentSettings:TransferPreferences?=nil){localCurrent=currentSettings;selection=PresetImportSelection(plan:plan,library:library)
  let window=NSWindow(contentRect:NSRect(x:0,y:0,width:820,height:720),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false);window.title="导入传输预设 · "+plan.format;window.minSize=NSSize(width:720,height:700);window.isReleasedWhenClosed=false;window.appearance=NSAppearance(named:.aqua);super.init(window:window);window.delegate=self
  let root=NSStackView();root.orientation = .vertical;root.alignment = .leading;root.spacing=9;root.edgeInsets=NSEdgeInsets(top:14,left:14,bottom:14,right:14);root.translatesAutoresizingMaskIntoConstraints=false;window.contentView!.addSubview(root);NSLayoutConstraint.activate([root.leadingAnchor.constraint(equalTo:window.contentView!.leadingAnchor),root.trailingAnchor.constraint(equalTo:window.contentView!.trailingAnchor),root.topAnchor.constraint(equalTo:window.contentView!.topAnchor),root.bottomAnchor.constraint(equalTo:window.contentView!.bottomAnchor)])
  let help=NSTextField(wrappingLabelWithString:"勾选要导入的项。同名项会替换本机内容并保留本机顺序；可改为另存副本。新项追加在末尾。这里只写入主设置草稿，主窗口“应用并保存”后才生效；导入不会登录服务器。")
  help.font = .systemFont(ofSize:12);root.addArrangedSubview(help);help.widthAnchor.constraint(equalTo:root.widthAnchor,constant:-28).isActive=true
  search.placeholderString="筛选名称、兼容性或迁移提示…";search.delegate=self;search.sendsSearchStringImmediately=true;search.target=self;search.action = #selector(reload)
  let all=NSButton(title:"全选兼容项",target:self,action:#selector(selectAllCompatible)),none=NSButton(title:"取消全选",target:self,action:#selector(selectNone));all.bezelStyle = .rounded;none.bezelStyle = .rounded
  let filter=NSStackView(views:[search,all,none]);filter.spacing=8;root.addArrangedSubview(filter);filter.widthAnchor.constraint(equalTo:root.widthAnchor,constant:-28).isActive=true
  for (id,title,width) in [("check","导入",44.0),("name","预设",180.0),("action","操作",125.0),("mode","传输模式",95.0),("status","兼容情况",260.0)]{let column=NSTableColumn(identifier:.init(id));column.headerCell=CommanderHeaderCell(textCell:title);column.width=width;table.addTableColumn(column)}
  table.dataSource=self;table.delegate=self;table.rowHeight=27;table.usesAlternatingRowBackgroundColors=true;let rows=NSScrollView();rows.hasVerticalScroller=true;rows.hasHorizontalScroller=true;rows.documentView=table;rows.borderType = .bezelBorder;root.addArrangedSubview(rows);rows.widthAnchor.constraint(equalTo:root.widthAnchor,constant:-28).isActive=true;rows.heightAnchor.constraint(greaterThanOrEqualToConstant:150).isActive=true
  summary.font = .systemFont(ofSize:11);root.addArrangedSubview(summary)
  let info=TaskDetailsScrollView();info.hasVerticalScroller=true;info.borderType = .bezelBorder;details.frame=NSRect(x:0,y:0,width:0,height:180);details.isEditable=false;details.isRichText=false;details.isVerticallyResizable=true;details.isHorizontallyResizable=false;details.autoresizingMask = .width;details.textContainer?.widthTracksTextView=true;let paragraph=NSMutableParagraphStyle();paragraph.lineBreakMode = .byCharWrapping;details.defaultParagraphStyle=paragraph;details.font = .monospacedSystemFont(ofSize:11.5,weight:.regular);details.textContainerInset=NSSize(width:7,height:7);info.documentView=details;root.addArrangedSubview(info);info.widthAnchor.constraint(equalTo:root.widthAnchor,constant:-28).isActive=true;info.heightAnchor.constraint(equalToConstant:175).isActive=true
  defaults.isEnabled=plan.defaultPreferences != nil || plan.automaticSelectionEnabled != nil;current.isEnabled=plan.currentPreferences != nil
  for control in [defaults,current]{control.target=self;control.action = #selector(optionsChanged);root.addArrangedSubview(control)}
  result.font = .systemFont(ofSize:11.5);result.maximumNumberOfLines=3;result.textColor=CommanderPalette.muted;root.addArrangedSubview(result);result.widthAnchor.constraint(equalTo:root.widthAnchor,constant:-28).isActive=true
  let cancel=NSButton(title:"取消",target:self,action:#selector(cancel));cancel.bezelStyle = .rounded;cancel.keyEquivalent="\u{1b}";applyButton.bezelStyle = .rounded;applyButton.target=self;applyButton.action = #selector(apply);applyButton.keyEquivalent="\r";let footer=NSStackView(views:[NSView(),cancel,applyButton]);footer.spacing=9;root.addArrangedSubview(footer);footer.widthAnchor.constraint(equalTo:root.widthAnchor,constant:-28).isActive=true
  reload();window.center()
 }
 required init?(coder:NSCoder){fatalError()}
 func numberOfRows(in tableView:NSTableView)->Int{visible.count}
 func tableView(_ tableView:NSTableView,viewFor column:NSTableColumn?,row:Int)->NSView?{guard visible.indices.contains(row) else{return nil};let item=visible[row],key=column?.identifier.rawValue
  if key=="check"{let button=NSButton(checkboxWithTitle:"",target:self,action:#selector(checkRow));button.tag=item.id;button.state=selection.checked.contains(item.id) ? .on : .off;button.isEnabled=item.eligible;button.setAccessibilityLabel("导入 "+item.name);return button}
  if key=="action",item.eligible{let popup=NSPopUpButton();popup.addItems(withTitles:[selection.existing(item)==nil ? "新增" : "替换同名","另存副本"]);popup.selectItem(at:selection.actions[item.id] == .copy ? 1 : 0);popup.tag=item.id;popup.target=self;popup.action = #selector(changeAction);popup.isBordered=false;popup.font = .systemFont(ofSize:11.5);return popup}
  let mode=item.preset?.preferences.filePolicy.text?.mode ?? .binary,value=key=="name" ? item.name : key=="mode" ? (item.preset==nil ? "—" : mode == .binary ? "二进制" : mode == .text ? "文本" : "自动") : key=="action" ? "不可导入" : item.issue ?? (item.notes.isEmpty ? "兼容" : "需核对迁移提示")
  let label=NSTextField(labelWithString:value);label.font = .systemFont(ofSize:11.5);label.lineBreakMode = .byTruncatingMiddle;label.toolTip=value;label.textColor=item.issue==nil ? .labelColor : .systemRed;return label
 }
 @objc func checkRow(_ sender:NSButton){selection.set(sender.tag,on:sender.state == .on);reload()}
 @objc func changeAction(_ sender:NSPopUpButton){selection.actions[sender.tag]=sender.indexOfSelectedItem==1 ? .copy : .merge;reload()}
 func controlTextDidChange(_ notification:Notification){reload()}
 @objc func reload(){let id=visible.indices.contains(table.selectedRow) ? visible[table.selectedRow].id : nil,query=search.stringValue;visible=selection.plan.candidates.filter{query.isEmpty || ($0.name+" "+($0.issue ?? "")+" "+$0.notes.joined(separator:" ")).localizedCaseInsensitiveContains(query)};table.reloadData();if let id=id,let row=visible.firstIndex(where:{$0.id==id}){table.selectRowIndexes(IndexSet(integer:row),byExtendingSelection:false)}else{table.deselectAll(nil)};let hidden=selection.checked.subtracting(Set(visible.map(\.id))).count;summary.stringValue="显示 \(visible.count) / \(selection.plan.candidates.count) 项 · 已勾选 \(selection.checked.count) 项"+(hidden>0 ? "（其中 \(hidden) 项不在当前筛选中）" : "");applyButton.isEnabled = !selection.checked.isEmpty || selection.includeDefaults || selection.restoreCurrent;showDetails()}
 func tableViewSelectionDidChange(_ notification:Notification){showDetails()}
 static func describe(_ value:TransferPreferences,rule:TransferPresetRule?=nil)->String{let text=value.filePolicy.text ?? TextTransferOptions();return ["并行：\(value.concurrency)","限速：\(value.kibibytesPerSecond) KiB/s（0 为不限速）","模式："+(text.mode == .binary ? "二进制" : text.mode == .text ? "文本" : "自动"),"包含："+(value.filePolicy.include.isEmpty ? "全部" : value.filePolicy.include),"排除："+(value.filePolicy.exclude.isEmpty ? "无" : value.filePolicy.exclude),"SHA-256：\(value.filePolicy.verifyChecksum)","文本掩码："+text.mask,"换行：远程 "+text.remote.rawValue.uppercased()+" / 本机 "+text.local.rawValue.uppercased(),"上传移除 BOM / EOF：\(text.removeBOM) / \(text.removeEOF)","自动条件：\(rule?.enabled ?? false)","地址："+(rule?.host ?? ""),"用户："+(rule?.user ?? ""),"本地："+(rule?.local ?? ""),"远程："+(rule?.remote ?? "")].joined(separator:"\n")}
 var globalInfo:String{var lines=["文件中的全局配置（仅勾选相应选项才恢复）"]
  if let value=selection.plan.defaultPreferences{lines += ["本机默认配置：",selection.baseline.defaultPreferences.map{Self.describe($0)} ?? "未设定","文件默认配置：",Self.describe(value)]}
  if let flag=selection.plan.automaticSelectionEnabled{lines.append("自动匹配开关：本机 \(selection.baseline.automaticSelectionEnabled != false ? "开启" : "关闭") → 文件 \(flag ? "开启" : "关闭")")}
  if let value=selection.plan.currentPreferences{lines += ["当前主设置草稿：",localCurrent.map{Self.describe($0)} ?? "未提供","文件当前传输设置：",Self.describe(value),"文件当前预设："+(selection.plan.selectedPresetName ?? "自定义")]}else{lines.append("未包含当前设置；保留主窗口草稿。")};return lines.joined(separator:"\n")
 }
 func showDetails(){guard visible.indices.contains(table.selectedRow) else{details.string=selection.plan.notes.joined(separator:"\n")+"\n选择一行查看原设置、导入设置及差异。\n\n"+globalInfo;return};let item=visible[table.selectedRow];var text="预设："+item.name+"\n操作："+selection.label(item)
  if let issue=item.issue{text+="\n无法导入："+issue};if let before=selection.existing(item){text+="\n\n本机原设置\n"+Self.describe(before.preferences,rule:before.rule)};if let preset=item.preset{text+="\n\n导入设置\n"+Self.describe(preset.preferences,rule:preset.rule)};text+="\n\n"+(selection.plan.notes+item.notes).joined(separator:"\n");details.string=text+"\n\n"+globalInfo
 }
 @objc func selectAllCompatible(){for row in visible where row.eligible{selection.set(row.id,on:true)};reload()}
 @objc func selectNone(){selection.checked=[];reload()}
 @objc func optionsChanged(){selection.includeDefaults=defaults.isEnabled && defaults.state == .on;selection.restoreCurrent=current.isEnabled && current.state == .on;reload()}
 func setChecked(_ id:Int,_ value:Bool){selection.set(id,on:value);reload()}
 func setAction(_ id:Int,_ action:PresetImportAction){selection.actions[id]=action;reload()}
 @objc func apply(){guard !closed else{return};do{let value=try selection.apply(to:selection.baseline);try onApply?(value);close()}catch{result.stringValue=error.localizedDescription;result.toolTip=result.stringValue;result.textColor = .systemRed}}
 @objc func cancel(){close()}
 override func close(){if let window=window,let parent=window.sheetParent{parent.endSheet(window)};super.close()}
 func windowWillClose(_ notification:Notification){guard !closed else{return};closed=true;onClosed?()}
}
