import Cocoa

struct TransferBatchOptions {
 let directory:String,preferences:TransferPreferences,speedLimit:UInt64?,suppress:Bool
 static func directory(_ raw:String)throws->String{let value=raw.trimmingCharacters(in:.whitespacesAndNewlines);guard value.hasPrefix("/"),value.utf8.count<=32768,!value.unicodeScalars.contains(where:{CharacterSet.controlCharacters.contains($0)}) else{throw SFTPError.message("请输入不含控制字符的绝对目标目录")};return value}
}

final class TransferOptionsController:NSWindowController,NSWindowDelegate,NSTableViewDataSource,NSTextFieldDelegate {
 let destination=NSTextField(),preset=NSPopUpButton(),table=NSTableView(),form:TransferSettingsView
 let independent=NSButton(checkboxWithTitle:"本批次独立限速（不改变全局）",target:nil,action:nil),suppress=NSButton(checkboxWithTitle:"以后直接使用当前目录与设置，不再显示确认窗口",target:nil,action:nil)
 let notice=NSTextField(wrappingLabelWithString:""),applyButton=NSButton(title:"加入传输队列",target:nil,action:nil),cancelButton=NSButton(title:"取消",target:nil,action:nil)
 let files:[DragFile],base:TransferPreferences,presets:[TransferPreset],localOnly:Bool;let sourceLabels:[String:String]
 private(set) var closed=false,busy=false
 var onConfirm:((TransferBatchOptions)->Void)?,onClosed:(()->Void)?,cancelValidation:(()->Void)?
 init(files:[DragFile],directory:String,toRemote:Bool,endpoint:String,preferences:TransferPreferences,presets:[TransferPreset],sourceLabels:[String:String]=[:]){
  self.files=files;self.sourceLabels=sourceLabels;self.base=preferences;self.presets=presets;localOnly = !toRemote && files.allSatisfy{$0.connection==nil};form=TransferSettingsView(preferences:preferences,includesConcurrency:false)
  let window=NSWindow(contentRect:NSRect(x:0,y:0,width:700,height:720),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false);window.minSize=NSSize(width:660,height:700);window.appearance=NSAppearance(named:.aqua);window.title=localOnly ? "复制到本地目录" : toRemote ? "上传／中转到服务器" : "下载到本地目录";window.isReleasedWhenClosed=false
  super.init(window:window);window.delegate=self
  let root=NSStackView();root.orientation = .vertical;root.alignment = .leading;root.spacing=6;root.translatesAutoresizingMaskIntoConstraints=false;window.contentView!.addSubview(root)
  NSLayoutConstraint.activate([root.leadingAnchor.constraint(equalTo:window.contentView!.leadingAnchor,constant:18),root.trailingAnchor.constraint(equalTo:window.contentView!.trailingAnchor,constant:-18),root.topAnchor.constraint(equalTo:window.contentView!.topAnchor,constant:12),root.bottomAnchor.constraint(equalTo:window.contentView!.bottomAnchor,constant:-12)])
  let heading=NSTextField(labelWithString:"核对 \(files.count) 个项目与目标目录");heading.font = .systemFont(ofSize:16,weight:.semibold);root.addArrangedSubview(heading)
  let target=NSTextField(labelWithString:"目标："+endpoint);target.font = .systemFont(ofSize:12);target.textColor=CommanderPalette.muted;target.lineBreakMode = .byTruncatingMiddle;root.addArrangedSubview(target);target.widthAnchor.constraint(equalTo:root.widthAnchor).isActive=true
  for (key,title,width) in [("name","项目",180.0),("size","大小",80.0),("source","来源路径",360.0)]{let column=NSTableColumn(identifier:.init(key));column.headerCell=CommanderHeaderCell(textCell:title);column.width=width;table.addTableColumn(column)}
  table.dataSource=self;table.rowHeight=25;table.usesAlternatingRowBackgroundColors=true;let scroll=NSScrollView();scroll.documentView=table;scroll.hasVerticalScroller=true;scroll.hasHorizontalScroller=true;scroll.borderType = .bezelBorder;root.addArrangedSubview(scroll);scroll.widthAnchor.constraint(equalTo:root.widthAnchor).isActive=true;scroll.heightAnchor.constraint(greaterThanOrEqualToConstant:75).isActive=true
  let addressLabel=NSTextField(labelWithString:"目标目录（需已存在；保留原文件名）");addressLabel.font = .systemFont(ofSize:12,weight:.medium);root.addArrangedSubview(addressLabel)
  destination.stringValue=directory;destination.toolTip=directory;destination.delegate=self;destination.cell?.lineBreakMode = .byTruncatingMiddle;window.initialFirstResponder=destination;destination.font = .systemFont(ofSize:13);destination.setAccessibilityLabel("目标目录");destination.cell?.isScrollable=true;root.addArrangedSubview(destination);destination.widthAnchor.constraint(equalTo:root.widthAnchor).isActive=true
  preset.addItem(withTitle:"当前设置（本批次草稿）");preset.addItems(withTitles:presets.map{$0.name});preset.target=self;preset.action = #selector(pickPreset);preset.setAccessibilityLabel("本批次传输预设");preset.toolTip="载入预设的文件规则和限速；不改变全局预设或并行任务数"
  let presetRow=NSStackView(views:[NSTextField(labelWithString:"传输设置"),preset,NSView()]);presetRow.spacing=10;root.addArrangedSubview(presetRow);presetRow.widthAnchor.constraint(equalTo:root.widthAnchor).isActive=true
  form.translatesAutoresizingMaskIntoConstraints=false;root.addArrangedSubview(form);form.heightAnchor.constraint(equalToConstant:185).isActive=true;form.widthAnchor.constraint(equalTo:root.widthAnchor).isActive=true
  independent.target=self;independent.action = #selector(changeIndependent);root.addArrangedSubview(independent);changeIndependent()
  if localOnly{form.load(TransferPreferences(concurrency:preferences.concurrency,kibibytesPerSecond:preferences.kibibytesPerSecond,policy:TransferPolicy(verifyChecksum:preferences.filePolicy.verifyChecksum)));form.include.isEnabled=false;form.exclude.isEnabled=false;form.modeButton.isEnabled=false;form.textOptions=TextTransferOptions();form.include.stringValue="";form.exclude.stringValue="";preset.isEnabled=false}
  let explanation=NSTextField(wrappingLabelWithString:localOnly ? "本地复制保持原始字节，不转换文本、不筛选目录内容。确认后在队列执行；同名目标仍需另行确认。" : "设置仅用于本批次文件。并行数沿用全局；未勾选独立限速时继续跟随全局限速。同名目标仍需确认；此处不创建目标目录。")
  explanation.font = .systemFont(ofSize:11);explanation.textColor=CommanderPalette.muted;root.addArrangedSubview(explanation);explanation.widthAnchor.constraint(equalTo:root.widthAnchor).isActive=true
  root.addArrangedSubview(suppress);suppress.font = .systemFont(ofSize:11)
  notice.font = .systemFont(ofSize:11);notice.maximumNumberOfLines=2;root.addArrangedSubview(notice);notice.widthAnchor.constraint(equalTo:root.widthAnchor).isActive=true;notice.heightAnchor.constraint(greaterThanOrEqualToConstant:26).isActive=true
  applyButton.target=self;applyButton.action = #selector(apply);applyButton.bezelStyle = .rounded;applyButton.keyEquivalent="\r";cancelButton.target=self;cancelButton.action = #selector(cancel);cancelButton.bezelStyle = .rounded;cancelButton.keyEquivalent="\u{1b}"
  let footer=NSStackView(views:[NSView(),cancelButton,applyButton]);footer.spacing=9;root.addArrangedSubview(footer);footer.widthAnchor.constraint(equalTo:root.widthAnchor).isActive=true
 }
 required init?(coder:NSCoder){fatalError()}
 func controlTextDidChange(_ notification:Notification){if notification.object as? NSTextField === destination{destination.toolTip=destination.stringValue}}
 func numberOfRows(in tableView:NSTableView)->Int{files.count}
 func tableView(_ tableView:NSTableView,objectValueFor tableColumn:NSTableColumn?,row:Int)->Any?{guard files.indices.contains(row) else{return nil};let file=files[row];switch tableColumn?.identifier.rawValue{case "name":return(file.path as NSString).lastPathComponent;case "size":return file.directory ? "目录" : ByteCountFormatter.string(fromByteCount:Int64(clamping:file.size),countStyle:.file);default:return file.connection.flatMap{sourceLabels[$0]}.map{$0+":"+file.path} ?? (file.connection==nil ? "本机：" : "服务器：")+file.path}}
 @objc func pickPreset(){guard !busy,!closed else{return};let index=preset.indexOfSelectedItem-1;form.load(presets.indices.contains(index) ? presets[index].preferences : base);independent.state=presets.indices.contains(index) ? .on : .off;changeIndependent()}
 @objc func changeIndependent(){form.speed.isEnabled = !busy && independent.state == .on}
 func value()throws->TransferBatchOptions{let prefs=try form.value();return TransferBatchOptions(directory:try TransferBatchOptions.directory(destination.stringValue),preferences:prefs,speedLimit:independent.state == .on ? prefs.bytesPerSecond : nil,suppress:suppress.state == .on)}
 @objc func apply(){guard !closed,!busy else{return};do{onConfirm?(try value())}catch{showError(error.localizedDescription)}}
 func setBusy(_ busy:Bool){self.busy=busy;suppress.isEnabled = !busy;applyButton.isEnabled = !busy;destination.isEnabled = !busy;preset.isEnabled = !busy && !localOnly;independent.isEnabled = !busy;for control in [form.include,form.exclude,form.modeButton,form.verify] as [NSControl]{control.isEnabled = !busy && (!localOnly || control === form.verify)};changeIndependent();notice.textColor=CommanderPalette.muted;notice.stringValue=busy ? "正在核对目标目录，不会自动登录…" : ""}
 func showError(_ message:String){setBusy(false);notice.textColor = .systemRed;notice.stringValue=message;notice.toolTip=message}
 @objc func cancel(){close()}
 override func close(){guard !closed else{return};closed=true;cancelValidation?();cancelValidation=nil;if let window=window,let parent=window.sheetParent{parent.endSheet(window)};super.close();onClosed?();onClosed=nil}
 func windowWillClose(_ notification:Notification){if !closed{closed=true;cancelValidation?();cancelValidation=nil;onClosed?();onClosed=nil}}
}

final class TransferDestinationProbe {
 private let lock=NSLock();private var client:RemoteFileClient?,cancelled=false
 func cancel(){lock.lock();cancelled=true;let value=client;lock.unlock();value?.interrupt()}
 func read(_ path:String,factory:()throws->RemoteFileClient)throws->(String,Set<String>){let c=try factory();defer{c.close();lock.lock();client=nil;lock.unlock()};lock.lock();let stopped=cancelled;if !stopped{client=c};lock.unlock();guard !stopped else{throw SFTPError.message("目标核对已取消")};let canonical=try c.canonical(path);guard let info=try c.followedAttributes(canonical),info.mode&0o170000==0o040000 else{throw SFTPError.message("目标不是已存在的目录")};let entries=try c.list(canonical);return(canonical,Set(entries.map{$0.name}))}
}
