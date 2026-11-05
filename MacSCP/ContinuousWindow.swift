import Cocoa
final class ContinuousSyncController:NSWindowController,NSWindowDelegate {
 let connection:String,site:Session,defaults:UserDefaults
 let localField=NSTextField(),remoteField=NSTextField(),stateLabel=NSTextField(labelWithString:"选择目录，然后开始监控")
 let recursive=NSButton(checkboxWithTitle:"包含子目录",target:nil,action:nil),initial=NSButton(checkboxWithTitle:"开始时先同步一次",target:nil,action:nil)
 let cleanup=NSButton(checkboxWithTitle:"同时删除远程端对应项（永久删除）",target:nil,action:nil),existing=NSButton(checkboxWithTitle:"仅更新远程已存在的文件",target:nil,action:nil)
 let selected=NSButton(checkboxWithTitle:"仅监控当前选中项",target:nil,action:nil),keepGoing=NSButton(checkboxWithTitle:"单项失败后继续其余项",target:nil,action:nil)
 let preserve=NSButton(checkboxWithTitle:"保留文件修改时间",target:nil,action:nil),strict=NSButton(checkboxWithTitle:"用 SHA-256 检查远程并发改动（需读取远程内容）",target:nil,action:nil)
 let policyLabel=NSTextField(labelWithString:"传输规则：全部文件")
 let remember=NSButton(checkboxWithTitle:"记住选项（下次仍需手动开始）",target:nil,action:nil),interval=NSTextField(),settle=NSTextField()
 let startButton=NSButton(title:"开始监控",target:nil,action:nil),pauseButton=NSButton(title:"暂停监控",target:nil,action:nil),stopButton=NSButton(title:"停止",target:nil,action:nil)
 let logView=NSTextView(frame:NSRect(x:0,y:0,width:620,height:240));let originalLocal:String,originalRemote:String,selection:Set<String>
 var usesNativeEvents=true
 var engine:ContinuousSyncEngine?,onJob:((TransferJob)->Void)?,onClosed:(()->Void)?,onStop:(()->Void)?
 let factory:(ContinuousOptions)throws->RemoteFileClient
 var confirm:((ContinuousBootstrap,ContinuousOptions)->Bool)?
 private var entries=[String](),closed=false
 var running:Bool{if let engine=engine{return !engine.state.terminal};return false}
 init(site:Session,connection:String,local:String,remote:String,selected:Set<String>,defaults:UserDefaults,factory:@escaping(ContinuousOptions)throws->RemoteFileClient){
  self.site=site;self.connection=connection;self.defaults=defaults;originalLocal=local;originalRemote=remote;selection=selected;self.factory=factory
  let window=NSWindow(contentRect:NSRect(x:0,y:0,width:660,height:700),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false)
  window.appearance=NSAppearance(named:.aqua);window.title="保持远程目录更新 · "+site.name;window.isReleasedWhenClosed=false;window.minSize=NSSize(width:620,height:700)
  super.init(window:window);window.delegate=self
  let stack=NSStackView();stack.orientation = .vertical;stack.alignment = .leading;stack.spacing=10;stack.edgeInsets=NSEdgeInsets(top:18,left:18,bottom:18,right:18);stack.translatesAutoresizingMaskIntoConstraints=false;window.contentView!.addSubview(stack)
  NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo:window.contentView!.leadingAnchor),stack.trailingAnchor.constraint(equalTo:window.contentView!.trailingAnchor),stack.topAnchor.constraint(equalTo:window.contentView!.topAnchor),stack.bottomAnchor.constraint(equalTo:window.contentView!.bottomAnchor)])
  let heading=NSTextField(labelWithString:"本地变化 → 远程目录");heading.font = .systemFont(ofSize:17,weight:.semibold);stack.addArrangedSubview(heading)
  let detail=NSTextField(wrappingLabelWithString:"保存本地文件后，等待写入稳定，再加入传输队列。暂停监控时，已入队任务继续。关闭窗口或连接会停止监控，不自动重连。")
  detail.font = .systemFont(ofSize:12);detail.textColor = .secondaryLabelColor;stack.addArrangedSubview(detail);detail.widthAnchor.constraint(equalTo:stack.widthAnchor,constant:-36).isActive=true
  for (title,field,value) in [("本地目录",localField,local),("远程目录",remoteField,remote)]{field.stringValue=value;field.font = .systemFont(ofSize:12);let label=NSTextField(labelWithString:title);label.widthAnchor.constraint(equalToConstant:66).isActive=true;let row=NSStackView(views:[label,field]);row.spacing=8;stack.addArrangedSubview(row);row.widthAnchor.constraint(equalTo:stack.widthAnchor,constant:-36).isActive=true}
  for pair in [[recursive,initial],[existing,self.selected],[keepGoing,preserve]]{let row=NSStackView(views:pair);row.spacing=24;stack.addArrangedSubview(row)}
  stack.addArrangedSubview(cleanup);cleanup.contentTintColor = .systemRed;stack.addArrangedSubview(strict)
  interval.widthAnchor.constraint(equalToConstant:58).isActive=true;settle.widthAnchor.constraint(equalToConstant:58).isActive=true
  let timing=NSStackView(views:[NSTextField(labelWithString:"检查间隔（秒）"),interval,NSTextField(labelWithString:"写入稳定等待（秒）"),settle]);timing.spacing=8;stack.addArrangedSubview(timing);stack.addArrangedSubview(remember);policyLabel.font = .systemFont(ofSize:11);policyLabel.textColor = .secondaryLabelColor;policyLabel.lineBreakMode = .byTruncatingMiddle;stack.addArrangedSubview(policyLabel);policyLabel.widthAnchor.constraint(equalTo:stack.widthAnchor,constant:-36).isActive=true
  let controls=NSStackView(views:[startButton,pauseButton,stopButton]);controls.spacing=8;stack.addArrangedSubview(controls)
  for button in [startButton,pauseButton,stopButton]{button.bezelStyle = .rounded;button.target=self}
  startButton.action = #selector(start);pauseButton.action = #selector(togglePause);stopButton.action = #selector(stop)
  stateLabel.font = .systemFont(ofSize:12,weight:.semibold);stateLabel.lineBreakMode = .byTruncatingMiddle;stack.addArrangedSubview(stateLabel);stateLabel.widthAnchor.constraint(equalTo:stack.widthAnchor,constant:-36).isActive=true
  logView.isEditable=false;logView.isRichText=false;logView.isVerticallyResizable=true;logView.isHorizontallyResizable=false;logView.autoresizingMask = .width;logView.minSize=NSSize(width:0,height:240);logView.maxSize=NSSize(width:CGFloat.greatestFiniteMagnitude,height:CGFloat.greatestFiniteMagnitude);logView.textContainer?.widthTracksTextView=true;logView.textContainer?.containerSize=NSSize(width:620,height:CGFloat.greatestFiniteMagnitude);logView.font = .monospacedSystemFont(ofSize:11,weight:.regular);logView.textContainerInset=NSSize(width:8,height:8)
  let scroll=NSScrollView(frame:NSRect(x:0,y:0,width:624,height:240));scroll.hasVerticalScroller=true;scroll.hasHorizontalScroller=false;scroll.borderType = .bezelBorder;scroll.documentView=logView;logView.setFrameSize(NSSize(width:scroll.contentSize.width,height:max(240,scroll.contentSize.height)));stack.addArrangedSubview(scroll);scroll.widthAnchor.constraint(equalTo:stack.widthAnchor,constant:-36).isActive=true;scroll.heightAnchor.constraint(greaterThanOrEqualToConstant:100).isActive=true
  load(ContinuousOptions.load(defaults) ?? ContinuousOptions());refresh()
 }
 required init?(coder:NSCoder){fatalError()}
 private var toggles:[NSButton]{[recursive,initial,cleanup,existing,selected,keepGoing,preserve,strict]}
 func load(_ options:ContinuousOptions){for (control,value) in zip(toggles,[options.recursive,options.initialSync,options.cleanup,options.existingOnly,options.selectedOnly,options.continueOnError,options.preserveTime,options.strictRemote]){control.state=value ? .on : .off};interval.stringValue=String(options.interval);settle.stringValue=String(options.settle);if site.fileProtocol == .sftp{preserve.state = .on};if selection.isEmpty{selected.state = .off}}
 func options()throws->ContinuousOptions{var value=ContinuousOptions();value.recursive=recursive.state == .on;value.initialSync=initial.state == .on;value.cleanup=cleanup.state == .on;value.existingOnly=existing.state == .on;value.selectedOnly=selected.state == .on;value.continueOnError=keepGoing.state == .on;value.preserveTime=preserve.state == .on;value.strictRemote=strict.state == .on;guard let seconds=Double(interval.stringValue),let quiet=Double(settle.stringValue) else{throw SFTPError.message("请输入有效的秒数")};value.interval=seconds;value.settle=quiet;return try value.validated()}
 private func refresh(){let active=running;for control in toggles{control.isEnabled = !active};selected.isEnabled = !active && !selection.isEmpty;preserve.isEnabled = !active && site.fileProtocol != .sftp;for field in [localField,remoteField,interval,settle]{field.isEnabled = !active};remember.isEnabled = !active;startButton.isEnabled = !active;stopButton.isEnabled=active;pauseButton.isEnabled=active && engine?.state != .preparing && engine?.state != .stopping;pauseButton.title=engine?.monitoringPaused == true ? "继续监控" : "暂停监控"}
 private func log(_ message:String){entries.append(DateFormatter.localizedString(from:Date(),dateStyle:.none,timeStyle:.medium)+"  "+message);if entries.count>500{entries.removeFirst(entries.count-500)};logView.string=entries.joined(separator:"\n");logView.scrollToEndOfDocument(nil)}
 @objc func start(){guard !running else{return};do{
  let options=try options();guard localField.stringValue.hasPrefix("/"),!remoteField.stringValue.isEmpty else{throw SFTPError.message("请选择本地绝对路径和远程目录")}
  if options.selectedOnly{guard localField.stringValue==originalLocal,remoteField.stringValue==originalRemote else{throw SFTPError.message("仅监控选中项时，请保持打开窗口时的两侧目录")}}
  _ = try ContinuousScope(options:options,policy:TransferPolicy(),selected:selection)
  if remember.state == .on{try options.save(defaults)}
  let engine=ContinuousSyncEngine(local:localField.stringValue,remote:remoteField.stringValue,options:options,policy:transferPolicy,selected:selection,copyPermissions:site.fileProtocol == .sftp || site.ftpSettings.preservePermissions,useEvents:usesNativeEvents,factory:{[factory=self.factory] in try factory(options)})
  self.engine=engine;engine.onLog={[weak self] in self?.log($0)};engine.onState={[weak self] state in guard let self=self else{return};self.stateLabel.stringValue=state.title;self.stateLabel.toolTip=state.title;self.refresh();if state.terminal && self.closed{self.onClosed?()}}
  engine.onReady={[weak self,weak engine] info in guard let self=self,let engine=engine,!engine.stopped else{return};if self.approve(info,options:options){engine.approve()}else{engine.stop()}}
  engine.onJob={[weak self] job in guard let self=self,!self.closed,self.running else{job.cancel();return};if let onJob=self.onJob{onJob(job)}else{job.finishWithoutStarting("未连接传输队列",failed:true)}}
  stateLabel.stringValue="准备监控…";refresh();engine.start()
 }catch{stateLabel.stringValue=error.localizedDescription;stateLabel.toolTip=error.localizedDescription;log(error.localizedDescription)}}
 var transferPolicy=TransferPolicy(){didSet{let text="传输规则：包含 \(transferPolicy.include.isEmpty ? "全部" : transferPolicy.include)；排除 \(transferPolicy.exclude.isEmpty ? "无" : transferPolicy.exclude)";policyLabel.stringValue=text;policyLabel.toolTip=text}}
 private func approve(_ info:ContinuousBootstrap,options:ContinuousOptions)->Bool{
  if let confirm=confirm{return confirm(info,options)}
  guard options.cleanup || info.directories>500 else{return true}
  let alert=NSAlert();alert.messageText=options.cleanup ? "允许监控期间永久删除远程对应项？" : "监控目录较多，仍要开始？"
  alert.informativeText="本地：\(info.local)\n远程：\(info.remote)\n共 \(info.directories) 个本地目录。"+(options.cleanup ? "\n之后本地删除的对应项目会从服务器永久删除。"+(options.initialSync ? "开始同步还会删除范围内远程独有项目。" : "") : "大量目录可能增加扫描和网络开销。")
  if !info.initialCleanup.isEmpty{let text=NSTextView(frame:NSRect(x:0,y:0,width:480,height:140));text.isEditable=false;text.string=info.initialCleanup.map{$0.debugDescription}.joined(separator:"\n");let scroll=NSScrollView(frame:text.frame);scroll.documentView=text;scroll.hasVerticalScroller=true;alert.accessoryView=scroll}
  alert.addButton(withTitle:"取消");alert.addButton(withTitle:options.cleanup ? "允许删除并开始监控" : "开始监控");return alert.runModal() == .alertSecondButtonReturn
 }
 @objc func togglePause(){guard let engine=engine else{return};engine.pause(!engine.monitoringPaused);refresh()}
 @objc func stop(){engine?.stop();onStop?();refresh()}
 func windowWillClose(_ notification:Notification){closed=true;stop();if !running{onClosed?()}}
 func windowShouldClose(_ sender:NSWindow)->Bool{closed=true;stop();if !running{onClosed?()};return true}
}
