import Cocoa

final class TransferQueueTable:NSTableView {
 var openDetails:(()->Void)?
 override func menu(for event:NSEvent)->NSMenu?{let clicked=row(at:convert(event.locationInWindow,from:nil));if clicked>=0 && !selectedRowIndexes.contains(clicked){selectRowIndexes(IndexSet(integer:clicked),byExtendingSelection:false)}else if clicked<0{deselectAll(nil)};return super.menu(for:event)}
 override func keyDown(with event:NSEvent){if [36,76].contains(event.keyCode),event.modifierFlags.intersection([.command,.control,.option,.shift]).isEmpty,selectedRow>=0{openDetails?()}else{super.keyDown(with:event)}}
}

final class TaskDetailsScrollView:NSScrollView {
 override func layout(){super.layout();guard let text=documentView as? NSTextView,contentSize.width>0 else{return};let width=contentSize.width
  if text.maxSize.width != width{text.maxSize=NSSize(width:width,height:CGFloat.greatestFiniteMagnitude)}
  if text.minSize.height != contentSize.height{text.minSize=NSSize(width:0,height:contentSize.height)}
  if abs(text.frame.width-width)>0.1{text.setFrameSize(NSSize(width:width,height:max(text.frame.height,contentSize.height)))}
 }
}

struct TaskDetailsPresentation {
 let job:TransferJob,progress:TransferProgressSnapshot,notes:String,available:Bool
 static func bytes(_ value:UInt64)->String{value==0 ? "0 B" : ByteCountFormatter.string(fromByteCount:Int64(clamping:value),countStyle:.file)}
 static func duration(_ value:TimeInterval)->String{let seconds=Int(min(Double(Int.max).nextDown,max(0,value)));return seconds>=3600 ? String(format:"%d:%02d:%02d",seconds/3600,seconds/60%60,seconds%60) : String(format:"%02d:%02d",seconds/60,seconds%60)}
 var endpoint:String{job.endpointDescription ?? job.recoverySite.map{$0.fileProtocol.title+" · "+$0.identity} ?? "未记录端点（以任务源和目标为准）"}
 var metadataOnly:Bool{["远程时间","本地时间","删除远程","移到废纸篓"].contains(job.customAction ?? "")}
 var mode:String{if metadataOnly{return "元数据／清理 · 不传输文件内容"};switch job.policy.text?.mode ?? .binary{case .binary:return "二进制 · 保持原字节";case .text:return "文本 · 转换换行";case .automatic:return "自动 · 按文本文件掩码"}}
 var report:String{
  let t=job.policy.text ?? TextTransferOptions(),stages=job.detailResumeRecords(limit:200)
  var rows=["任务 ID："+job.id.uuidString,"操作："+job.column("direction"),"状态："+progress.status,"连接："+endpoint,"源："+job.source,"目标："+job.destination]
  if let display=job.displaySource,display != job.source{rows.append("显示来源："+display)};if let display=job.displayDestination,display != job.destination{rows.append("显示目标："+display)}
  if let file=progress.currentFile{rows.append("当前／最后文件："+file)}
  rows += ["", "已传输："+Self.bytes(progress.bytes)+"（\(progress.bytes) 字节）","总量："+(progress.estimated ? "约 " : "")+Self.bytes(progress.total)+"（\(progress.total) 字节）","复用已传数据："+Self.bytes(progress.reused),"耗时："+Self.duration(progress.elapsed),"限速："+(progress.speedLimit==0 ? "不限速" : Self.bytes(progress.speedLimit)+"/s"),"限速来源："+(job.overrideSpeedLimit==nil ? "跟随全局设置" : "本批次独立设置"),job.customAction != nil && progress.totalFiles==0 ? "文件统计：专用操作未提供逐文件统计" : progress.totalFiles==0 && !progress.finished ? "文件清单：等待扫描" : "已完成文件：\(progress.completedFiles) / \(progress.totalFiles)","", "此任务保存的传输设置", "模式："+mode,"包含："+(job.policy.include.isEmpty ? "全部" : job.policy.include),"排除："+(job.policy.exclude.isEmpty ? "无" : job.policy.exclude),"完成前 SHA-256："+(metadataOnly ? "由已确认计划决定；不执行文件传输校验" : job.policy.verifyChecksum ? "开启" : "关闭")]
  if !metadataOnly,t.mode != .binary{rows += ["文本文件掩码："+t.mask,"服务器换行："+(t.remote == .lf ? "LF" : "CRLF"),"本机换行："+(t.local == .lf ? "LF" : "CRLF"),"上传移除 UTF-8 BOM："+(t.removeBOM ? "是" : "否"),"上传移除末尾 Ctrl-Z："+(t.removeEOF ? "是" : "否"),"自动模式对检测到的 NUL / UTF-16/32 BOM 保留原字节；不转换字符编码。"]}
  rows.append("覆盖许可："+(job.overwrite ? "已允许" : "未允许"))
  if let paths=job.restrictedPaths{rows.append("已确认的范围：\(paths.count) 条文件／必要父目录，不随当前全局规则改变")}
  if job.excludePrivateStages{rows.append("同步私有暂存排除：开启")}
  if let notice=job.retryNotice{rows.append("重试说明："+notice)}
  if !notes.isEmpty{rows += ["","队列说明："+notes]}
  rows += ["","暂存／发布记录（不代表路径仍然存在）"]
  if stages.records.isEmpty{rows.append("尚无记录")}
  for state in stages.records{rows.append("目标："+state.destination);rows.append("暂存："+state.temporaryPath);if let digest=state.sourceDigest{rows.append("上传内容 SHA-256："+digest)};if let publication=state.ftpPublication{rows.append("FTP 发布阶段："+publication.phase.rawValue);if let backup=try? FTPFilePublisher.backup(destination:state.destination,temporary:state.temporaryPath){rows.append("备份："+backup)}}}
  if stages.count>stages.records.count{rows.append("另有 \(stages.count-stages.records.count) 条记录未展开。")}
  if !available{rows += ["","任务已从队列移除，此窗口保留最后信息。"]}
  return rows.joined(separator:"\n")
 }
}

final class TaskDetailsController:NSWindowController,NSWindowDelegate {
 let job:TransferJob
 let heading=NSTextField(labelWithString:""),endpoint=NSTextField(labelWithString:""),status=NSTextField(wrappingLabelWithString:""),progress=NSProgressIndicator(),output=NSTextView()
 let copyButton=NSButton(title:"复制显示信息",target:nil,action:nil),locateButton=NSButton(title:"在队列中定位",target:nil,action:nil)
 let transferred=NSTextField(labelWithString:""),total=NSTextField(labelWithString:""),speed=NSTextField(labelWithString:""),remaining=NSTextField(labelWithString:""),reused=NSTextField(labelWithString:"")
 var notes:(()->String)?,isAvailable:(()->Bool)?,onLocate:(()->Void)?,onClosed:(()->Void)?,copyText:((String)->Void)?
 private var timer:Timer?,closed=false;private(set) var report=""
 var timerActive:Bool{timer?.isValid==true}
 init(job:TransferJob,automaticRefresh:Bool=true){self.job=job
  let window=NSWindow(contentRect:NSRect(x:0,y:0,width:780,height:590),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false);window.title="任务详情 · "+(job.source as NSString).lastPathComponent;window.isReleasedWhenClosed=false;window.minSize=NSSize(width:680,height:480);window.appearance=NSAppearance(named:.aqua);super.init(window:window);window.delegate=self
  let root=NSStackView();root.orientation = .vertical;root.alignment = .leading;root.spacing=9;root.edgeInsets=NSEdgeInsets(top:16,left:16,bottom:14,right:16);root.translatesAutoresizingMaskIntoConstraints=false;window.contentView!.addSubview(root)
  NSLayoutConstraint.activate([root.leadingAnchor.constraint(equalTo:window.contentView!.leadingAnchor),root.trailingAnchor.constraint(equalTo:window.contentView!.trailingAnchor),root.topAnchor.constraint(equalTo:window.contentView!.topAnchor),root.bottomAnchor.constraint(equalTo:window.contentView!.bottomAnchor)])
  heading.font = .systemFont(ofSize:15,weight:.semibold);endpoint.font = .systemFont(ofSize:11.5);endpoint.textColor=CommanderPalette.muted;endpoint.lineBreakMode = .byTruncatingMiddle
  for label in [heading,endpoint,status]{root.addArrangedSubview(label);label.widthAnchor.constraint(equalTo:root.widthAnchor,constant:-32).isActive=true};status.font = .systemFont(ofSize:12);status.maximumNumberOfLines=3
  progress.style = .bar;progress.minValue=0;progress.maxValue=100;root.addArrangedSubview(progress);progress.widthAnchor.constraint(equalTo:root.widthAnchor,constant:-32).isActive=true;progress.heightAnchor.constraint(equalToConstant:14).isActive=true
  let stats=NSStackView();stats.spacing=12;stats.distribution = .fillEqually
  for (name,value) in [("已传输",transferred),("传输总量",total),("平均速度",speed),("预计剩余",remaining),("复用数据",reused)]{let label=NSTextField(labelWithString:name);label.font = .systemFont(ofSize:10.5);label.textColor=CommanderPalette.muted;value.font = .monospacedDigitSystemFont(ofSize:12,weight:.medium);value.lineBreakMode = .byTruncatingMiddle;let pair=NSStackView(views:[label,value]);pair.orientation = .vertical;pair.alignment = .leading;pair.spacing=4;stats.addArrangedSubview(pair)}
  root.addArrangedSubview(stats);stats.widthAnchor.constraint(equalTo:root.widthAnchor,constant:-32).isActive=true
  let scroll=TaskDetailsScrollView();output.frame=NSRect(x:0,y:0,width:720,height:300);scroll.hasVerticalScroller=true;scroll.borderType = .bezelBorder;let paragraph=NSMutableParagraphStyle();paragraph.lineBreakMode = .byCharWrapping;output.defaultParagraphStyle=paragraph;output.isEditable=false;output.isRichText=false;output.isSelectable=true;output.font = .monospacedSystemFont(ofSize:11.5,weight:.regular);output.textContainerInset=NSSize(width:8,height:8);output.isVerticallyResizable=true;output.isHorizontallyResizable=false;output.autoresizingMask = .width;output.textContainer?.widthTracksTextView=true;scroll.documentView=output;root.addArrangedSubview(scroll);scroll.widthAnchor.constraint(equalTo:root.widthAnchor,constant:-32).isActive=true;scroll.heightAnchor.constraint(greaterThanOrEqualToConstant:190).isActive=true
  let close=NSButton(title:"关闭",target:self,action:#selector(closePanel));close.bezelStyle = .rounded;close.keyEquivalent="\u{1b}";for (button,action) in [(copyButton,#selector(copyReport)),(locateButton,#selector(locate))]{button.bezelStyle = .rounded;button.target=self;button.action=action}
  let buttons=NSStackView(views:[copyButton,locateButton,NSView(),close]);buttons.spacing=9;root.addArrangedSubview(buttons);buttons.widthAnchor.constraint(equalTo:root.widthAnchor,constant:-32).isActive=true
  refresh();if automaticRefresh{startRefreshing()};window.center()
 }
 required init?(coder:NSCoder){fatalError()}
 deinit{timer?.invalidate()}
 func startRefreshing(){guard !closed,timer==nil else{return};let value=Timer(timeInterval:0.3,repeats:true){[weak self] _ in self?.refresh()};timer=value;RunLoop.main.add(value,forMode:.common)}
 func refresh(){guard !closed else{return};let value=job.progressSnapshot(),presentation=TaskDetailsPresentation(job:job,progress:value,notes:notes?() ?? "",available:isAvailable?() ?? true)
  heading.stringValue=job.column("direction")+" · "+(job.source as NSString).lastPathComponent;endpoint.stringValue=presentation.endpoint;endpoint.toolTip=endpoint.stringValue
  status.stringValue=value.status;status.toolTip=value.status;status.textColor=value.failed ? .systemRed : value.finished && !value.cancelled ? .systemGreen : CommanderPalette.ink
  if let fraction=value.fraction{progress.stopAnimation(nil);progress.isIndeterminate=false;progress.doubleValue=fraction*100}else{progress.isIndeterminate=true;if window?.isVisible==true && value.executing && !value.paused{progress.startAnimation(nil)}else{progress.stopAnimation(nil)}}
  transferred.stringValue=TaskDetailsPresentation.bytes(value.bytes);total.stringValue=presentation.metadataOnly ? "不传输内容" : (value.estimated ? "约 " : "")+TaskDetailsPresentation.bytes(value.total);speed.stringValue=job.column("speed");remaining.stringValue=value.remaining.map{TaskDetailsPresentation.duration($0)} ?? "—";reused.stringValue=TaskDetailsPresentation.bytes(value.reused);locateButton.isEnabled=presentation.available
  let text=presentation.report;if text != report{let selection=output.selectedRange(),visible=output.enclosingScrollView?.contentView.bounds.origin;report=text;output.string=text;let length=(text as NSString).length;output.setSelectedRange(NSRange(location:min(selection.location,length),length:min(selection.length,max(0,length-min(selection.location,length)))));if let visible=visible{output.enclosingScrollView?.contentView.scroll(to:visible)}}
 }
 @objc func copyReport(){refresh();if let copy=copyText{copy(report)}else{NSPasteboard.general.clearContents();NSPasteboard.general.setString(report,forType:.string)}}
 @objc func locate(){if isAvailable?() != false{onLocate?()}}
 @objc func closePanel(){close()}
 func windowWillClose(_ notification:Notification){guard !closed else{return};closed=true;timer?.invalidate();timer=nil;progress.stopAnimation(nil);onClosed?()}
}
