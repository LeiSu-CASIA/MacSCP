import Cocoa
@main struct NativeQueueControlsTests {
 static func main(){
  NSApplication.shared.setActivationPolicy(.prohibited)
  let bar=NSStackView();bar.spacing=8;bar.edgeInsets=NSEdgeInsets(top:7,left:12,bottom:7,right:12)
  let names=["传输队列 并行任务数","暂停 / 继续","取消选中","重试 / 续传","清除已结束","恢复任务…","↑","↓","优先"]
  var buttons=[NSButton]()
  for name in names{let button=NSButton(title:name,target:nil,action:nil);bar.addArrangedSubview(button);buttons.append(button)}
  let strip=QueueToolbar(bar:bar);strip.frame=NSRect(x:0,y:0,width:420,height:44);strip.layoutSubtreeIfNeeded()
  precondition(strip.intrinsicContentSize.height>=38 && strip.bar.frame.width>strip.contentSize.width)
  precondition(buttons.allSatisfy{$0.frame.width>0 && $0.frame.height>0})
  strip.contentView.scroll(to:NSPoint(x:strip.bar.frame.width-strip.contentSize.width,y:0));strip.reflectScrolledClipView(strip.contentView)
  precondition(strip.contentView.bounds.minX>0)
  strip.frame.size.width=1500;strip.needsLayout=true;strip.layoutSubtreeIfNeeded()
  precondition(strip.bar.frame.width>=strip.contentSize.width && strip.bar.frame.height>=38)
  print("PASS: hidden queue toolbar has visible button frames, narrow width scrolls to last controls, wide width expands content, no user window shown")
 }
}
