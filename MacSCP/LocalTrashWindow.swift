import Cocoa
final class LocalTrashController:NSWindowController,NSWindowDelegate {
 let plan:LocalTrashPlan,trash:(URL)throws->Void
 let output=NSTextView(),message=NSTextField(labelWithString:""),startButton=CommanderChromeButton(),stopButton=CommanderChromeButton()
 let cancellation=LocalTrashCancellation();private(set) var busy=false,started=false;private(set) var report:LocalTrashReport?;private(set) var closed=false
 var onClosed:(()->Void)?,onFinished:((LocalTrashReport?)->Void)?
 init(plan:LocalTrashPlan,trash:@escaping(URL)throws->Void=LocalTrashExecutor.moveToTrash){
  self.plan=plan;self.trash=trash
  let window=NSWindow(contentRect:NSRect(x:0,y:0,width:700,height:480),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false);window.isReleasedWhenClosed=false;window.minSize=NSSize(width:560,height:400)
  super.init(window:window);window.title="移到废纸篓 · 本地文件";window.delegate=self;window.appearance=NSAppearance(named:.aqua);window.center()
  let root=NSStackView();root.orientation = .vertical;root.spacing=10;root.edgeInsets=NSEdgeInsets(top:14,left:14,bottom:12,right:14);root.translatesAutoresizingMaskIntoConstraints=false;window.contentView!.addSubview(root)
  NSLayoutConstraint.activate([root.leadingAnchor.constraint(equalTo:window.contentView!.leadingAnchor),root.trailingAnchor.constraint(equalTo:window.contentView!.trailingAnchor),root.topAnchor.constraint(equalTo:window.contentView!.topAnchor),root.bottomAnchor.constraint(equalTo:window.contentView!.bottomAnchor)])
  let heading=NSTextField(labelWithString:"将 \(plan.items.count) 项移到废纸篓");heading.font = .systemFont(ofSize:17,weight:.semibold);root.addArrangedSubview(heading)
  let description=NSTextField(wrappingLabelWithString:"请核对下方完整路径。目录及其全部内容会一起移动，目录内容不递归预览。符号链接只移动链接本身。停止或关闭窗口仅停止尚未处理的项目；已移动的项目可到 Finder 废纸篓查看。回收失败会报告错误，不会改为永久删除。");description.font = .systemFont(ofSize:12);root.addArrangedSubview(description);description.widthAnchor.constraint(equalTo:root.widthAnchor,constant:-28).isActive=true
  let scroll=NSScrollView();scroll.hasVerticalScroller=true;scroll.hasHorizontalScroller=true;scroll.borderType = .bezelBorder;output.isEditable=false;output.isRichText=false;output.font = .monospacedSystemFont(ofSize:11,weight:.regular);output.isVerticallyResizable=true;output.isHorizontallyResizable=true;output.textContainer?.widthTracksTextView=false;output.textContainer?.containerSize=NSSize(width:100000,height:CGFloat.greatestFiniteMagnitude);output.frame=NSRect(x:0,y:0,width:650,height:280);output.string=plan.preview;scroll.documentView=output;root.addArrangedSubview(scroll);scroll.widthAnchor.constraint(equalTo:root.widthAnchor,constant:-28).isActive=true;scroll.heightAnchor.constraint(greaterThanOrEqualToConstant:160).isActive=true
  startButton.title="移到废纸篓";startButton.target=self;startButton.action = #selector(start);CommanderAppearance.button(startButton,key:"delete")
  stopButton.title="停止剩余项";stopButton.target=self;stopButton.action = #selector(stop);stopButton.isEnabled=false;CommanderAppearance.button(stopButton,key:"cancel")
  let copy=CommanderChromeButton(title:"复制清单 / 结果",target:self,action:#selector(copyResult));CommanderAppearance.button(copy,key:"copyPath")
  root.addArrangedSubview(NSStackView(views:[startButton,stopButton,copy]));root.addArrangedSubview(message);message.font = .systemFont(ofSize:11);message.lineBreakMode = .byTruncatingMiddle;message.widthAnchor.constraint(equalTo:root.widthAnchor,constant:-28).isActive=true;message.stringValue="等待确认 · 尚未移动任何项目"
 }
 required init?(coder:NSCoder){fatalError()}
 @objc func start(){
  guard !started,!closed else{return};started=true;busy=true;startButton.isEnabled=false;stopButton.isEnabled=true;message.stringValue="正在移到废纸篓…"
  DispatchQueue.global(qos:.userInitiated).async{
   do{let report=try LocalTrashExecutor.execute(self.plan,cancellation:self.cancellation,trash:self.trash,progress:{done,total,path in DispatchQueue.main.async{guard !self.closed else{return};self.message.stringValue="正在处理 \(done)/\(total)："+path}})
    DispatchQueue.main.async{self.report=report;self.finish();if !self.closed{self.message.stringValue=report.summary;self.output.string=report.details+(report.cancelled ? "\n未处理的项目保留在原目录。" : "")};self.onFinished?(report)}
   }catch{DispatchQueue.main.async{self.finish();if !self.closed{self.message.stringValue="未开始移动："+error.localizedDescription;self.output.string+="\n\n"+error.localizedDescription};self.onFinished?(nil)}}
  }
 }
 private func finish(){busy=false;stopButton.isEnabled=false}
 @objc func stop(){cancellation.cancel();stopButton.isEnabled=false;if busy{message.stringValue="等待当前项结束，停止剩余项目…"}}
 @objc func copyResult(){NSPasteboard.general.clearContents();NSPasteboard.general.setString(message.stringValue+"\n\n"+output.string,forType:.string)}
 func windowWillClose(_ notification:Notification){closed=true;cancellation.cancel();onClosed?()}
}
