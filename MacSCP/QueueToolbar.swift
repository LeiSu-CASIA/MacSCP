import Cocoa

// The queue controls remain reachable at the window's minimum width.
final class QueueToolbar:NSScrollView {
 let bar:NSStackView;let minimumHeight:CGFloat
 init(bar:NSStackView,minimumHeight:CGFloat=38){self.minimumHeight=minimumHeight;
  self.bar=bar;super.init(frame:.zero)
  borderType = .noBorder;drawsBackground=false
  hasHorizontalScroller=true;hasVerticalScroller=false;autohidesScrollers=true;scrollerStyle = .overlay
  horizontalScrollElasticity = .automatic;verticalScrollElasticity = .none
  documentView=bar;bar.autoresizingMask=[]
 }
 required init?(coder:NSCoder){fatalError()}
 override var intrinsicContentSize:NSSize{NSSize(width:NSView.noIntrinsicMetric,height:max(minimumHeight,bar.fittingSize.height))}
 override func layout(){
  super.layout()
  let fitting=bar.fittingSize
  bar.frame=NSRect(x:0,y:0,width:max(fitting.width,contentSize.width),height:max(fitting.height,contentSize.height))
 }
}
