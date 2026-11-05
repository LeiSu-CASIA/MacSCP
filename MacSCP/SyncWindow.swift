import Cocoa
final class SyncPreviewController:NSWindowController,NSWindowDelegate,NSTableViewDataSource,NSTableViewDelegate {
 var contentsProvider:((SyncCandidate)throws->SyncContents)?;var contentsWindows=[SyncContentsController]();let contentsButton=NSButton(title:"选择目录内容…",target:nil,action:nil)
 var confirmDeletion:(([SyncCandidate])->Bool)?
 let context:String
 var candidates:[SyncCandidate];var onApply:(([SyncCandidate])->Void)?;var onClosed:(()->Void)?;let table=NSTableView();let summary=NSTextField(labelWithString:"")
 init(candidates:[SyncCandidate],context:String=""){self.candidates=candidates;self.context=context;let window=NSWindow(contentRect:NSRect(x:0,y:0,width:1040,height:620),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false);window.isReleasedWhenClosed=false;super.init(window:window);window.title="同步预览 · 确认后执行";window.delegate=self;window.center();window.minSize=NSSize(width:800,height:450)
 let root=NSStackView();root.orientation = .vertical;root.spacing=8;root.edgeInsets=NSEdgeInsets(top:10,left:10,bottom:10,right:10);root.translatesAutoresizingMaskIntoConstraints=false;window.contentView!.addSubview(root);NSLayoutConstraint.activate([root.leadingAnchor.constraint(equalTo:window.contentView!.leadingAnchor),root.trailingAnchor.constraint(equalTo:window.contentView!.trailingAnchor),root.topAnchor.constraint(equalTo:window.contentView!.topAnchor),root.bottomAnchor.constraint(equalTo:window.contentView!.bottomAnchor)])
 let guidance=candidates.isEmpty ? "当前没有可执行项目，请阅读比较说明；必要时重新选择同步范围。" : candidates.allSatisfy{$0.timestampOnly} ? "勾选要调整修改时间的文件。不传输内容、不删除或新建文件；类型冲突需先处理。" : "勾选要执行的项目。目录传输可选择具体文件和空目录；目录清理也可选择内容，并会按实际清理范围再次确认。本地移到废纸篓，远程永久删除。";let explanation=NSTextField(wrappingLabelWithString:(context.isEmpty ? "" : context+"\n")+guidance);explanation.font = .systemFont(ofSize:12);root.addArrangedSubview(explanation);explanation.widthAnchor.constraint(equalTo:root.widthAnchor,constant:-20).isActive=true;let bar=NSStackView();for(title,action) in [("全选可执行项",#selector(selectExecutable)),("全不选",#selector(selectNone)),("选中行使用本地版本",#selector(useLocal)),("选中行使用远程版本",#selector(useRemote)),("执行勾选项",#selector(apply))]{let timestamp=candidates.allSatisfy{$0.timestampOnly};let caption=timestamp && action == #selector(useLocal) ? "选中行使用本地时间" : timestamp && action == #selector(useRemote) ? "选中行使用远程时间" : title;let button=NSButton(title:caption,target:self,action:action);if action == #selector(useLocal) || action == #selector(useRemote){button.toolTip=timestamp ? "为所选文件明确选择时间来源（SFTP v3 有效范围 1970–2106）" : "明确使用所选行的本地或远程版本"};bar.addArrangedSubview(button)};contentsButton.target=self;contentsButton.action = #selector(editContents);contentsButton.bezelStyle = .rounded;contentsButton.isEnabled=false;bar.addArrangedSubview(contentsButton);let toolbar=QueueToolbar(bar:bar,minimumHeight:30);root.addArrangedSubview(toolbar);toolbar.widthAnchor.constraint(equalTo:root.widthAnchor,constant:-20).isActive=true
 for(id,title,width) in [("selected","执行",45.0),("path","相对路径",300.0),("action","动作 / 冲突",270.0),("local","本地",180.0),("remote","远程",180.0)]{let col=NSTableColumn(identifier:.init(id));col.headerCell=CommanderHeaderCell(textCell:title);col.width=width;table.addTableColumn(col)};table.delegate=self;table.dataSource=self;table.allowsMultipleSelection=true;table.rowHeight=27;table.style = .plain;table.intercellSpacing=NSSize(width:3,height:1);table.usesAlternatingRowBackgroundColors=true;table.gridStyleMask = .solidVerticalGridLineMask;table.gridColor=CommanderPalette.line.withAlphaComponent(0.4);table.backgroundColor = .white;let scroll=NSScrollView();scroll.documentView=table;scroll.hasVerticalScroller=true;scroll.hasHorizontalScroller=true;root.addArrangedSubview(scroll);scroll.widthAnchor.constraint(equalTo:root.widthAnchor,constant:-20).isActive=true;scroll.heightAnchor.constraint(greaterThanOrEqualToConstant:240).isActive=true;root.addArrangedSubview(summary);summary.font = .systemFont(ofSize:11.5);summary.textColor=CommanderPalette.ink;updateSummary()
 }
 required init?(coder:NSCoder){fatalError()}
 func numberOfRows(in tableView:NSTableView)->Int{candidates.count}
 func tableView(_ tableView:NSTableView,viewFor column:NSTableColumn?,row:Int)->NSView?{let item=candidates[row];if column?.identifier.rawValue=="selected"{let button=NSButton(checkboxWithTitle:"",target:self,action:#selector(toggle));button.tag=row;button.state=item.selected ? .on : .off;button.isEnabled=item.executable;return button};let value:String;func info(_ node:SyncNode?)->String{guard let node=node else{return "不存在"};if item.timestampOnly{return SyncComparison.timeDescription(node.modified)};return (node.directory ? "目录" : ByteCountFormatter.string(fromByteCount:Int64(clamping:node.size),countStyle:.file))+" · "+Date(timeIntervalSince1970:node.modified).formatted(date:.numeric,time:.shortened)};switch column?.identifier.rawValue{case "path":value=item.relative+(item.directory ? "/" : "");case "action":value=item.label;case "local":value=info(item.local);default:value=info(item.remote)};let label=NSTextField(labelWithString:value);label.lineBreakMode = .byTruncatingMiddle;label.toolTip=value;if item.timestampOnly,["local","remote"].contains(column?.identifier.rawValue ?? ""),let node=column?.identifier.rawValue=="local" ? item.local : item.remote{label.toolTip="修改时间："+value+"\n大小：\(node.size) 字节"};if item.upload==nil || item.deletion{label.textColor = .systemRed};label.font = .systemFont(ofSize:12);let cell=NSTableCellView();cell.textField=label;label.translatesAutoresizingMaskIntoConstraints=false;cell.addSubview(label);NSLayoutConstraint.activate([label.leadingAnchor.constraint(equalTo:cell.leadingAnchor,constant:4),label.trailingAnchor.constraint(equalTo:cell.trailingAnchor,constant:-4),label.centerYAnchor.constraint(equalTo:cell.centerYAnchor)]);label.setContentCompressionResistancePriority(.defaultLow,for:.horizontal);return cell}
 @objc func toggle(_ sender:NSButton){guard candidates.indices.contains(sender.tag) else{return};candidates[sender.tag].selected=sender.state == .on;if candidates[sender.tag].selected,candidates[sender.tag].contents?.selected.isEmpty==true{candidates[sender.tag].contents?.setAll(true)};updateSummary()}
 @objc func selectExecutable(){for i in candidates.indices{candidates[i].selected=candidates[i].executable;if candidates[i].contents?.selected.isEmpty==true{candidates[i].contents?.setAll(true)}};reload()}
 @objc func selectNone(){for i in candidates.indices{candidates[i].selected=false};reload()}
 @objc func useLocal(){resolve(true)};@objc func useRemote(){resolve(false)}
 private func resolve(_ upload:Bool){var refused=0;for index in table.selectedRowIndexes{if !SyncComparison.resolve(&candidates[index],upload:upload){refused+=1}};reload();if refused>0{summary.stringValue+=" · \(refused) 项未改向（类型或时间范围限制）"}}
 private func reload(){let selected=table.selectedRowIndexes;table.reloadData();table.selectRowIndexes(selected.intersection(IndexSet(integersIn:0..<candidates.count)),byExtendingSelection:false);updateSummary()}
 private func updateSummary(){summary.stringValue="\(candidates.filter{$0.selected}.count) 项已勾选 / \(candidates.count) 项 · \(candidates.filter{$0.upload==nil}.count) 项冲突未处理 · \(candidates.filter{$0.selected && $0.deletion}.count) 项清理"+(candidates.contains{$0.timestampOnly} ? " · \(candidates.filter{$0.selected && $0.timestampOnly}.count) 项仅时间戳" : "")}
 func deletionLines(_ removals:[SyncCandidate])->[String]{removals.flatMap{item in (item.contents?.selectedRoots ?? [item.relative]).map{(item.upload==true ? "远程永久删除：" : "本地移到废纸篓：")+$0.debugDescription}}}
 func deletionAlert(_ removals:[SyncCandidate])->NSAlert{
  let lines=deletionLines(removals),alert=NSAlert();alert.alertStyle = .warning;alert.messageText="确认清理所列项目？";alert.informativeText=(context.isEmpty ? "" : context+"\n\n")+"共 \(lines.count) 个项目或完整子树。本地移到废纸篓，远程永久删除。完整子树连同目录清理；半选目录保留。执行前会再次核对文件变化。"
  let scroll=NSScrollView(frame:NSRect(x:0,y:0,width:520,height:220));scroll.hasVerticalScroller=true;scroll.borderType = .bezelBorder
  let text=NSTextView(frame:NSRect(origin:.zero,size:scroll.contentSize));text.isEditable=false;text.isRichText=false;text.font = .monospacedSystemFont(ofSize:11,weight:.regular);text.isVerticallyResizable=true;text.isHorizontallyResizable=false;text.autoresizingMask = .width;text.minSize=scroll.contentSize;text.maxSize=NSSize(width:CGFloat.greatestFiniteMagnitude,height:CGFloat.greatestFiniteMagnitude);text.textContainer?.widthTracksTextView=true;text.textContainer?.containerSize=NSSize(width:scroll.contentSize.width,height:CGFloat.greatestFiniteMagnitude);text.string=lines.joined(separator:"\n");scroll.documentView=text;alert.accessoryView=scroll
  alert.addButton(withTitle:"确认清理并执行");alert.addButton(withTitle:"取消");return alert
 }
 @objc func apply(){guard contentsWindows.isEmpty else{summary.stringValue="请先确认或关闭内容选择窗口，再执行同步预览";if window?.isVisible==true{contentsWindows.first?.showWindow(nil)};return};let selected=candidates.filter{$0.selected && $0.executable};guard !selected.isEmpty else{return};let removals=selected.filter{$0.deletion};if !removals.isEmpty{let accepted:Bool;if let confirm=confirmDeletion{accepted=confirm(removals)}else{accepted=deletionAlert(removals).runModal() == .alertFirstButtonReturn};guard accepted else{return}};onApply?(selected);close()}

 func tableViewSelectionDidChange(_ notification:Notification){let rows=table.selectedRowIndexes;contentsButton.isEnabled=rows.count==1 && rows.first.map{canEditContents($0)}==true;contentsButton.title=rows.first.flatMap{candidates.indices.contains($0) ? candidates[$0].deletion : nil}==true ? "选择清理内容…" : "选择目录内容…"}
 private func canEditContents(_ row:Int)->Bool{candidates.indices.contains(row) && candidates[row].directory && candidates[row].executable && !candidates[row].timestampOnly && contentsProvider != nil}
 @objc func editContents(){if let row=table.selectedRowIndexes.first{_ = showContents(row:row)}}
 @discardableResult func showContents(row:Int)->SyncContentsController?{
  guard canEditContents(row),let provider=contentsProvider else{summary.stringValue="请选择一个可执行的目录传输；目录传输和目录清理均可选择内容";return nil}
  let candidate=candidates[row]
  if let existing=contentsWindows.first(where:{$0.contents.root==candidate.relative}){if window?.isVisible==true{existing.showWindow(nil)};return existing}
  do{let contents=try candidate.contents ?? provider(candidate),controller=SyncContentsController(contents:contents,deletion:candidate.deletion)
   controller.onApply={[weak self] chosen in guard let self=self,self.candidates.indices.contains(row),self.candidates[row].relative==chosen.root else{return};self.candidates[row].contents=chosen;self.candidates[row].selected = !chosen.selected.isEmpty;self.reload()}
   controller.onClosed={[weak self,weak controller] in self?.contentsWindows.removeAll{$0 === controller}}
   contentsWindows.append(controller);if window?.isVisible==true{controller.showWindow(nil);controller.window?.makeKeyAndOrderFront(nil)};return controller
  }catch{summary.stringValue=error.localizedDescription;return nil}
 }
 func windowWillClose(_ notification:Notification){for controller in contentsWindows{controller.close()};onClosed?()}
}

final class SyncOptionsView:NSView {
 let direction=NSPopUpButton(),operation=NSPopUpButton()
 let modificationTime=NSButton(checkboxWithTitle:"修改时间",target:nil,action:nil),size=NSButton(checkboxWithTitle:"文件大小",target:nil,action:nil)
 let checksum=NSButton(checkboxWithTitle:"SHA-256 内容（读取范围内的普通文件）",target:nil,action:nil)
 let cleanup=NSButton(checkboxWithTitle:"清理目标端多余文件和目录（单向同步）",target:nil,action:nil)
 let existingOnly=NSButton(checkboxWithTitle:"仅更新已有文件（不复制源端独有项）",target:nil,action:nil)
 let remember=NSButton(checkboxWithTitle:"下次使用相同选项",target:nil,action:nil)
 let tolerance=NSTextField(string:"2"),explanation=NSTextField(wrappingLabelWithString:"")
 let sameSizeOnly=NSButton(checkboxWithTitle:"仅处理大小相同的对应文件",target:nil,action:nil)
 let permitsUpload:Bool,permitsTimestamps:Bool
 var mode:SyncDirection{!permitsUpload ? .download : direction.indexOfSelectedItem==0 ? .upload : direction.indexOfSelectedItem==1 ? .download : .both}
 var fileMode:SyncFileMode{if permitsTimestamps,operation.indexOfSelectedItem==2{return .timestamps};return mode == .both || operation.indexOfSelectedItem != 1 ? .synchronize : .mirror}
 var deleteExtraneous:Bool{mode != .both && fileMode != .timestamps && cleanup.state == .on}
 init(permitsUpload:Bool,settings:SyncSettings?=nil,initialDirection:SyncDirection = .upload,permitsTimestamps:Bool=true){
  self.permitsUpload=permitsUpload;self.permitsTimestamps=permitsTimestamps;super.init(frame:NSRect(x:0,y:0,width:500,height:330))
  direction.frame=NSRect(x:0,y:298,width:490,height:28);direction.addItems(withTitles:permitsUpload ? ["本地 → 远程","远程 → 本地","双向同步"] : ["远程 → 本地（FTP 仅下载）"]);direction.target=self;direction.action = #selector(changedDirection);addSubview(direction)
  operation.frame=NSRect(x:0,y:264,width:490,height:28);operation.addItems(withTitles:["同步文件（按比较条件更新）","镜像文件（源端为准，允许覆盖较新目标）"]);if permitsTimestamps{operation.addItem(withTitle:"仅同步修改时间（SFTP，不传输内容）")};operation.menu?.autoenablesItems=false;operation.target=self;operation.action = #selector(changedOptions);addSubview(operation)
  modificationTime.frame=NSRect(x:0,y:230,width:110,height:26);modificationTime.state = .on;modificationTime.target=self;modificationTime.action = #selector(changedOptions);addSubview(modificationTime)
  size.frame=NSRect(x:125,y:230,width:110,height:26);addSubview(size)
  let toleranceLabel=NSTextField(labelWithString:"时间容差");toleranceLabel.frame=NSRect(x:248,y:233,width:64,height:20);addSubview(toleranceLabel)
  tolerance.frame=NSRect(x:314,y:232,width:58,height:23);let number=NumberFormatter();number.minimum=0;number.maximum=300;number.maximumFractionDigits=3;tolerance.formatter=number;addSubview(tolerance)
  let seconds=NSTextField(labelWithString:"秒（0–300）");seconds.frame=NSRect(x:380,y:233,width:108,height:20);seconds.font = .systemFont(ofSize:11);addSubview(seconds)
  checksum.frame=NSRect(x:0,y:200,width:490,height:26);addSubview(checksum)
  existingOnly.frame=NSRect(x:0,y:168,width:490,height:26);addSubview(existingOnly);sameSizeOnly.frame=existingOnly.frame;sameSizeOnly.isHidden=true;addSubview(sameSizeOnly)
  cleanup.frame=NSRect(x:0,y:136,width:490,height:26);cleanup.toolTip="默认关闭。预览中的远程清理为永久删除；本地清理移到废纸篓。双向同步不提供清理。";addSubview(cleanup)
  explanation.frame=NSRect(x:0,y:58,width:490,height:72);explanation.font = .systemFont(ofSize:11);explanation.textColor = .secondaryLabelColor;addSubview(explanation)
  remember.frame=NSRect(x:0,y:21,width:490,height:26);addSubview(remember)
  let saved=settings ?? SyncSettings(direction:initialDirection)
  if permitsUpload{direction.selectItem(at:saved.direction == .upload ? 0 : saved.direction == .download ? 1 : 2)}
  operation.selectItem(at:saved.comparison.fileMode == .timestamps && permitsTimestamps ? 2 : saved.comparison.fileMode == .mirror ? 1 : 0);sameSizeOnly.state=saved.comparison.timestampSameSizeOnly ? .on : .off
  modificationTime.state=saved.comparison.modificationTime ? .on : .off;size.state=saved.comparison.size ? .on : .off;checksum.state=saved.comparison.checksum ? .on : .off
  tolerance.doubleValue=saved.comparison.timeTolerance;existingOnly.state=saved.comparison.existingOnly ? .on : .off;cleanup.state=saved.cleanup ? .on : .off
  changedDirection()
 }
 required init?(coder:NSCoder){fatalError()}
 func settings()throws->SyncSettings {
  let text=tolerance.stringValue.trimmingCharacters(in:.whitespacesAndNewlines)
  guard let value=Double(text),value.isFinite else{throw SFTPError.message("请输入有效的时间容差（0–300 秒）")}
  let stamp=fileMode == .timestamps
  let comparison=SyncComparisonOptions(fileMode:fileMode,modificationTime:stamp || mode == .both || modificationTime.state == .on,size:!stamp && mode != .both && size.state == .on,checksum:!stamp && mode != .both && checksum.state == .on,existingOnly:!stamp && existingOnly.state == .on,timeTolerance:value,timestampSameSizeOnly:stamp && sameSizeOnly.state == .on)
  return try SyncSettings(direction:mode,comparison:comparison,cleanup:deleteExtraneous).validated()
 }
 @objc func changedDirection(){
  let both=mode == .both;operation.isEnabled = !both || permitsTimestamps;operation.item(at:1)?.isEnabled = !both
  if both,operation.indexOfSelectedItem==1{operation.selectItem(at:0)}
  changedOptions()
 }
 @objc func changedOptions(){
  let both=mode == .both,stamp=fileMode == .timestamps
  modificationTime.isEnabled = !both && !stamp;size.isEnabled = !both && !stamp;checksum.isEnabled = !both && !stamp;cleanup.isEnabled = !both && !stamp
  if both || stamp{cleanup.state = .off;modificationTime.state = .on;size.state = .off;checksum.state = .off}
  existingOnly.isHidden=stamp;sameSizeOnly.isHidden = !stamp
  tolerance.isEnabled=both || stamp || modificationTime.state == .on
  if stamp{explanation.stringValue="只调整同名普通文件的修改时间，不传输内容、不删除。单向以源时间为准；双向更新较旧的一侧。可限制仅同大小，但不核对内容是否相同。\n包含 / 排除规则同样应用。预览后变化会停止该项；时间戳按整秒处理。";return}
  explanation.stringValue=(both ? "双向同步按较新的修改时间决定方向；同时间但大小不同会列为冲突。" : fileMode == .mirror ? "镜像会用源端不同的文件替换目标，目标较新也可被覆盖；清理多余文件需另外勾选。" : "启用时间比较时，较新的目标不会被普通同步覆盖；时间相同才继续比较大小或内容。")+"\n未勾选任何比较条件时只处理缺失项。包含 / 排除规则同样应用；始终先预览，再执行。时间同步上传会保留时间；FTP 需要服务器支持 MFMT。"
 }
}
