import Cocoa

final class FilePropertiesController:NSWindowController,NSWindowDelegate {
 private var baseProperties=""
 let paths:[String],factory:(()throws->RemoteFileClient)?
 let size=NSTextField(labelWithString:"尚未计算"),counts=NSTextField(labelWithString:""),message=NSTextField(labelWithString:""),output=NSTextView(),startButton=CommanderChromeButton(),cancelButton=CommanderChromeButton(),spinner=NSProgressIndicator()
 private(set) var busy=false;private(set) var result:DirectorySizeResult?;private var token=DirectorySizeCancellation(),generation=0,closed=false
 var onClosed:(()->Void)?
 init(paths:[String],entries:[Entry],remote:Bool,factory:(()throws->RemoteFileClient)?){
  self.paths=paths;self.factory=factory
  let window=NSWindow(contentRect:NSRect(x:0,y:0,width:680,height:500),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false);window.isReleasedWhenClosed=false;window.minSize=NSSize(width:560,height:420)
  super.init(window:window);window.title="文件属性 · "+(remote ? "远程" : "本地");window.appearance=NSAppearance(named:.aqua);window.delegate=self;window.center()
  let root=NSStackView();root.orientation = .vertical;root.spacing=10;root.edgeInsets=NSEdgeInsets(top:14,left:16,bottom:12,right:16);root.translatesAutoresizingMaskIntoConstraints=false;window.contentView!.addSubview(root)
  NSLayoutConstraint.activate([root.leadingAnchor.constraint(equalTo:window.contentView!.leadingAnchor),root.trailingAnchor.constraint(equalTo:window.contentView!.trailingAnchor),root.topAnchor.constraint(equalTo:window.contentView!.topAnchor),root.bottomAnchor.constraint(equalTo:window.contentView!.bottomAnchor)])
  let heading=NSTextField(labelWithString:"已选择 \(paths.count) 项");heading.font = .systemFont(ofSize:17,weight:.semibold);size.font = .systemFont(ofSize:19,weight:.semibold);counts.font = .systemFont(ofSize:12);counts.textColor=CommanderPalette.muted
  for view in [heading,size,counts]{view.lineBreakMode = .byTruncatingTail;view.setContentCompressionResistancePriority(.defaultLow,for:.horizontal);root.addArrangedSubview(view);view.widthAnchor.constraint(equalTo:root.widthAnchor,constant:-32).isActive=true}
  counts.stringValue="计算后显示文件、目录及符号链接数量"
  let notice=NSTextField(wrappingLabelWithString:"统计逻辑文件大小，包含隐藏项目；不跟随符号链接，不计磁盘占用。扫描不是文件系统快照；权限错误、目录变化或达到上限时会标明结果不完整。");notice.font = .systemFont(ofSize:11);notice.textColor=CommanderPalette.muted;root.addArrangedSubview(notice);notice.widthAnchor.constraint(equalTo:root.widthAnchor,constant:-32).isActive=true
  let scroll=NSScrollView();scroll.hasVerticalScroller=true;scroll.hasHorizontalScroller=true;scroll.borderType = .bezelBorder;output.isEditable=false;output.isRichText=false;output.font = .monospacedSystemFont(ofSize:11,weight:.regular);output.isVerticallyResizable=true;output.isHorizontallyResizable=true;output.textContainer?.widthTracksTextView=false;output.textContainer?.containerSize=NSSize(width:100000,height:CGFloat.greatestFiniteMagnitude);output.frame=NSRect(x:0,y:0,width:640,height:280);scroll.documentView=output;root.addArrangedSubview(scroll);scroll.widthAnchor.constraint(equalTo:root.widthAnchor,constant:-32).isActive=true;scroll.heightAnchor.constraint(greaterThanOrEqualToConstant:150).isActive=true
  output.string=zip(paths,entries).map{path,entry in
   let type=entry.symbolicLink ? "符号链接" : entry.dir ? "目录" : "文件"
   let listedSize=entry.dir && !entry.symbolicLink ? "目录内容尚未统计" : String(entry.size)+" 字节（列表属性）"
   var lines=[path,"大小："+listedSize,"类型："+type,"修改时间："+entry.date,"权限："+entry.permissions]
   if entry.symbolicLink{lines.append("链接目标："+(entry.linkTarget ?? "未读取"))}
   return lines.joined(separator:"\n")
  }.joined(separator:"\n\n")
  if entries.allSatisfy({!$0.dir && !$0.symbolicLink}) {
   var total:UInt64=0,overflow=false
   for entry in entries{let sum=total.addingReportingOverflow(entry.size);overflow = overflow || sum.overflow;total=sum.partialValue}
   if !overflow{var initial=DirectorySizeResult();initial.bytes=total;size.stringValue="列表大小："+initial.sizeText;counts.stringValue="选中 \(entries.count) 个项目；计算可重新读取当前属性"}
  }
  baseProperties=output.string
  startButton.title="计算大小";startButton.target=self;startButton.action = #selector(start);CommanderAppearance.button(startButton,key:"properties")
  cancelButton.title="取消计算";cancelButton.target=self;cancelButton.action = #selector(cancel);CommanderAppearance.button(cancelButton,key:"cancel");cancelButton.isEnabled=false
  let copy=CommanderChromeButton(title:"复制属性",target:self,action:#selector(copyProperties));CommanderAppearance.button(copy,key:"copyPath")
  spinner.style = .spinning;spinner.controlSize = .small;spinner.isDisplayedWhenStopped=false
  let bar=NSStackView(views:[startButton,cancelButton,copy,NSView(),spinner]);root.addArrangedSubview(bar);bar.widthAnchor.constraint(equalTo:root.widthAnchor,constant:-32).isActive=true
  root.addArrangedSubview(message);message.font = .systemFont(ofSize:11);message.lineBreakMode = .byTruncatingMiddle;message.widthAnchor.constraint(equalTo:root.widthAnchor,constant:-32).isActive=true;message.stringValue="点击“计算大小”开始，只读取文件属性"
 }
 required init?(coder:NSCoder){fatalError()}
 @objc func start(){
  guard !busy,!closed else{return};busy=true;generation+=1;let run=generation;token=DirectorySizeCancellation();let cancellation=token;result=nil;output.string=baseProperties;display(DirectorySizeResult());startButton.isEnabled=false;cancelButton.isEnabled=true;spinner.startAnimation(nil);message.stringValue="正在统计…";size.stringValue="统计中…"
  DispatchQueue.global(qos:.utility).async{
   do{
    try cancellation.check();let client=try self.factory?();defer{cancellation.setInterrupt(nil);client?.close()}
    if let client=client{cancellation.setInterrupt{client.interrupt()};client.checkpoint={try cancellation.check()}}
    let progress:(DirectorySizeResult,String)->Void={partial,path in DispatchQueue.main.async{guard self.generation==run,!self.closed else{return};self.display(partial);self.message.stringValue=path.isEmpty ? "正在完成统计…" : "正在扫描："+path}}
    let scanned:DirectorySizeResult
    if let client=client{scanned=try DirectorySizeScanner.remote(paths:self.paths,client:client,cancellation:cancellation,progress:progress)}else{scanned=try DirectorySizeScanner.local(paths:self.paths,cancellation:cancellation,progress:progress)}
    DispatchQueue.main.async{guard self.generation==run,!self.closed else{return};self.result=scanned;self.display(scanned);self.finish();self.message.stringValue=scanned.complete ? "统计完成（读取期间的结果）" : "统计不完整 · \(scanned.warningCount) 项警告"+(scanned.limited ? " · 已达到扫描上限" : "");if !scanned.warnings.isEmpty{self.output.string+="\n\n统计警告（最多显示 100 项）：\n"+scanned.warnings.joined(separator:"\n")}}
   }catch{DispatchQueue.main.async{guard self.generation==run,!self.closed else{return};self.finish();self.message.stringValue=cancellation.cancelled ? "统计已取消；当前显示的是部分结果" : "统计失败："+error.localizedDescription}}
  }
 }
 private func display(_ result:DirectorySizeResult){size.stringValue=result.sizeText;size.toolTip=result.sizeText;counts.stringValue=result.summary;counts.toolTip=result.summary}
 private func finish(){busy=false;spinner.stopAnimation(nil);startButton.isEnabled=true;startButton.title="重新计算";cancelButton.isEnabled=false}
 @objc func cancel(){guard busy else{return};token.cancel();cancelButton.isEnabled=false;message.stringValue="正在取消统计…"}
 @objc func copyProperties(){NSPasteboard.general.clearContents();NSPasteboard.general.setString(size.stringValue+"\n"+counts.stringValue+"\n"+message.stringValue+"\n\n"+output.string,forType:.string)}
 func windowWillClose(_ notification:Notification){closed=true;generation+=1;token.cancel();onClosed?()}
}
