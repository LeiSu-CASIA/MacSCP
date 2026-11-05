import Cocoa

enum CommanderPalette {
 static let ink=NSColor(calibratedRed:0.12,green:0.17,blue:0.24,alpha:1)
 static let muted=NSColor(calibratedRed:0.34,green:0.40,blue:0.48,alpha:1)
 static let line=NSColor(calibratedRed:0.83,green:0.86,blue:0.90,alpha:1)
 static let blue=NSColor(calibratedRed:0.18,green:0.37,blue:0.62,alpha:1)
 static let surface=NSColor(calibratedRed:0.97,green:0.975,blue:0.985,alpha:1)
 static let selected=NSColor(calibratedRed:0.18,green:0.43,blue:0.75,alpha:1)
 static func separator()->NSView{let line=NSBox();line.boxType = .separator;line.widthAnchor.constraint(equalToConstant:1).isActive=true;line.heightAnchor.constraint(equalToConstant:20).isActive=true;return line}
}

class CommanderChromeButton:NSButton {
 enum Role{case normal,primary,transfer}
 var role:Role = .normal{didSet{needsDisplay=true}}
 private var hover=false;private var tracking:NSTrackingArea?
 override init(frame:NSRect){super.init(frame:frame);isBordered=false;font = .systemFont(ofSize:12,weight:.medium);focusRingType = .exterior}
 required init?(coder:NSCoder){fatalError()}
 override var intrinsicContentSize:NSSize{let base=super.intrinsicContentSize;return NSSize(width:imagePosition == .imageOnly ? 27 : max(38,base.width+14),height:28)}
 override func updateTrackingAreas(){super.updateTrackingAreas();if let tracking=tracking{removeTrackingArea(tracking)};let area=NSTrackingArea(rect:.zero,options:[.mouseEnteredAndExited,.activeInActiveApp,.inVisibleRect],owner:self,userInfo:nil);tracking=area;addTrackingArea(area)}
 override func mouseEntered(with event:NSEvent){hover=true;needsDisplay=true}
 override func mouseExited(with event:NSEvent){hover=false;needsDisplay=true}
 override func draw(_ dirtyRect:NSRect){
  let rect=bounds.insetBy(dx:1,dy:2),path=NSBezierPath(roundedRect:rect,xRadius:4,yRadius:4),pressed=cell?.isHighlighted==true
  if role == .primary {
   let top=isEnabled ? CommanderPalette.blue.blended(withFraction:pressed ? 0 : 0.13,of:.white)! : NSColor.disabledControlTextColor
   NSGradient(starting:top,ending:CommanderPalette.blue)?.draw(in:path,angle:90)
  }else if role == .transfer && isEnabled {
   NSColor(calibratedRed:0.88,green:0.93,blue:0.99,alpha:1).setFill();path.fill();NSColor(calibratedRed:0.63,green:0.75,blue:0.90,alpha:1).setStroke();path.lineWidth=0.6;path.stroke()
  }else if (hover || state == .on || pressed) && isEnabled {
   (pressed ? NSColor(calibratedWhite:0.84,alpha:1) : NSColor(calibratedRed:0.86,green:0.91,blue:0.98,alpha:1)).setFill();path.fill()
  }
  super.draw(dirtyRect)
 }
 override var focusRingMaskBounds:NSRect{bounds.insetBy(dx:1,dy:2)}
 override func drawFocusRingMask(){NSBezierPath(roundedRect:focusRingMaskBounds,xRadius:4,yRadius:4).fill()}
}

final class CommanderBand:NSView {
 enum Kind{case toolbar,tabs,subtle,footer}
 let kind:Kind
 init(_ content:NSView,height:CGFloat,kind:Kind = .subtle,insets:NSEdgeInsets=NSEdgeInsets(top:2,left:6,bottom:2,right:6)){
  self.kind=kind;super.init(frame:.zero);content.translatesAutoresizingMaskIntoConstraints=false;addSubview(content)
  NSLayoutConstraint.activate([heightAnchor.constraint(equalToConstant:height),content.leadingAnchor.constraint(equalTo:leadingAnchor,constant:insets.left),content.trailingAnchor.constraint(equalTo:trailingAnchor,constant:-insets.right),content.topAnchor.constraint(equalTo:topAnchor,constant:insets.top),content.bottomAnchor.constraint(equalTo:bottomAnchor,constant:-insets.bottom)])
 }
 required init?(coder:NSCoder){fatalError()}
 override func draw(_ dirtyRect:NSRect){
  let color:NSColor=kind == .tabs ? NSColor(calibratedRed:0.91,green:0.93,blue:0.96,alpha:1) : kind == .toolbar ? .white : CommanderPalette.surface
  color.setFill();bounds.fill()
  CommanderPalette.line.setFill();NSRect(x:0,y:isFlipped ? bounds.maxY-1 : bounds.minY,width:bounds.width,height:1).fill()
 }
}

final class CommanderBadge:NSView {
 enum Tone{case blue,green,muted,warning}
 let label=NSTextField(labelWithString:"");var tone:Tone = .blue{didSet{update()}}
 var stringValue:String{get{label.stringValue}set{label.stringValue=newValue;setAccessibilityLabel(newValue);invalidateIntrinsicContentSize();needsDisplay=true}}
 init(_ text:String){super.init(frame:.zero);label.font = .systemFont(ofSize:10.5,weight:.semibold);label.lineBreakMode = .byTruncatingMiddle;label.setContentCompressionResistancePriority(.defaultLow,for:.horizontal);label.translatesAutoresizingMaskIntoConstraints=false;addSubview(label);NSLayoutConstraint.activate([label.leadingAnchor.constraint(equalTo:leadingAnchor,constant:7),label.trailingAnchor.constraint(equalTo:trailingAnchor,constant:-7),label.centerYAnchor.constraint(equalTo:centerYAnchor)]);stringValue=text;update()}
 required init?(coder:NSCoder){fatalError()}
 override var intrinsicContentSize:NSSize{NSSize(width:min(220,label.intrinsicContentSize.width+14),height:21)}
 private func update(){label.textColor=tone == .green ? NSColor(calibratedRed:0.17,green:0.48,blue:0.30,alpha:1) : tone == .muted ? CommanderPalette.muted : tone == .warning ? .systemOrange : CommanderPalette.blue;needsDisplay=true}
 override func draw(_ dirtyRect:NSRect){let color=tone == .green ? NSColor(calibratedRed:0.88,green:0.95,blue:0.91,alpha:1) : tone == .muted ? NSColor(calibratedWhite:0.92,alpha:1) : NSColor(calibratedRed:0.88,green:0.93,blue:0.99,alpha:1);color.setFill();NSBezierPath(roundedRect:bounds.insetBy(dx:0,dy:1),xRadius:4,yRadius:4).fill()}
}

final class CommanderPaneHeader:NSView {
 private let image=NSImageView(),label=NSTextField(labelWithString:"")
 let badge:CommanderBadge;let local:Bool;var active=false{didSet{needsDisplay=true}}
 init(title:String,local:Bool){self.local=local;badge=CommanderBadge(local ? "本机" : "未连接");super.init(frame:.zero)
  image.image=NSImage(systemSymbolName:local ? "laptopcomputer" : "server.rack",accessibilityDescription:nil);image.contentTintColor = .white
  label.stringValue=title.components(separatedBy:"·")[0].trimmingCharacters(in:.whitespaces);label.font = .systemFont(ofSize:13,weight:.semibold);label.textColor = .white
  let bar=NSStackView(views:[image,label,NSView(),badge]);bar.spacing=7;bar.translatesAutoresizingMaskIntoConstraints=false;addSubview(bar);NSLayoutConstraint.activate([image.widthAnchor.constraint(equalToConstant:17),image.heightAnchor.constraint(equalToConstant:17),bar.leadingAnchor.constraint(equalTo:leadingAnchor,constant:10),bar.trailingAnchor.constraint(equalTo:trailingAnchor,constant:-9),bar.centerYAnchor.constraint(equalTo:centerYAnchor),heightAnchor.constraint(equalToConstant:34)])
 }
 required init?(coder:NSCoder){fatalError()}
 func show(_ state:RemotePaneConnectionState,protocolName:String="SFTP"){guard !local else{return};badge.stringValue=state.available ? protocolName : state.title.replacingOccurrences(of:"服务器",with:"");badge.tone=state.available ? .green : .muted}
 override func draw(_ dirtyRect:NSRect){let base=active ? CommanderPalette.blue : NSColor(calibratedRed:0.38,green:0.52,blue:0.69,alpha:1);NSGradient(starting:base.blended(withFraction:0.06,of:.white)!,ending:base)?.draw(in:bounds,angle:90);base.blended(withFraction:0.2,of:.black)!.setFill();NSRect(x:0,y:0,width:bounds.width,height:1).fill()}
}

final class CommanderHeaderCell:NSTableHeaderCell {
 override init(textCell:String){super.init(textCell:textCell);font = .systemFont(ofSize:11.5,weight:.medium);textColor=CommanderPalette.ink;lineBreakMode = .byTruncatingTail}
 required init(coder:NSCoder){fatalError()}
 override func draw(withFrame cellFrame:NSRect,in controlView:NSView){CommanderPalette.surface.setFill();cellFrame.fill();CommanderPalette.line.withAlphaComponent(0.7).setFill();NSRect(x:cellFrame.minX,y:cellFrame.maxY-1,width:cellFrame.width,height:1).fill();NSRect(x:cellFrame.maxX-1,y:cellFrame.minY+5,width:1,height:cellFrame.height-10).fill();super.drawInterior(withFrame:cellFrame.insetBy(dx:5,dy:0),in:controlView)}
}

protocol CommanderSelectionScope:AnyObject {var commanderSelectionActive:Bool{get}}

// Keep a strong selection in the active pane and a quiet selection in the other pane.
final class CommanderFileRowView:NSTableRowView {
 private var paneActive:Bool{var view: NSView?=superview;while let current=view{if let scope=current as? CommanderSelectionScope{return scope.commanderSelectionActive};view=current.superview};return isEmphasized}
 override var interiorBackgroundStyle:NSView.BackgroundStyle{isSelected && paneActive ? .emphasized : .normal}
 override func drawBackground(in dirtyRect:NSRect){
  let row=(superview as? NSTableView)?.row(for:self) ?? -1
  (row>=0 && row%2==1 ? NSColor(calibratedRed:0.98,green:0.985,blue:0.993,alpha:1) : .white).setFill();bounds.fill()
 }
 override func drawSelection(in dirtyRect:NSRect){guard selectionHighlightStyle != .none else{return};(paneActive ? CommanderPalette.selected : NSColor(calibratedRed:0.87,green:0.91,blue:0.96,alpha:1)).setFill();bounds.fill()}
}

final class CommanderAddressBar:NSStackView {
 var active=false{didSet{needsDisplay=true}}
 override func draw(_ dirtyRect:NSRect){
  NSColor.white.setFill();let path=NSBezierPath(roundedRect:bounds.insetBy(dx:0.5,dy:0.5),xRadius:4,yRadius:4);path.fill()
  (active ? CommanderPalette.blue.withAlphaComponent(0.55) : CommanderPalette.line).setStroke();path.lineWidth=1;path.stroke()
 }
}

// The hint is a passive overlay: wheel events, selection and the queue menu remain native.
final class CommanderQueueScrollView:NSScrollView {
 private let hint=NSTextField(labelWithString:"队列为空 · 选择文件后按 F5 上传或下载")
 var empty=true{didSet{hint.isHidden = !empty}}
 override init(frame:NSRect){super.init(frame:frame);hint.font = .systemFont(ofSize:12);hint.textColor=CommanderPalette.muted;hint.alignment = .center;hint.isSelectable=false;hint.lineBreakMode = .byTruncatingTail;addSubview(hint)}
 required init?(coder:NSCoder){fatalError()}
 override func layout(){super.layout();hint.frame=NSRect(x:16,y:contentView.frame.midY-10,width:max(0,bounds.width-32),height:20)}
}

// File panes resize independently. Keep their ratio when resizing the window.
final class CommanderFileSplitView:NSSplitView,NSSplitViewDelegate {
 private var positioned=false,adjusting=false;private var lastWidth:CGFloat=0
 private(set) var ratio:CGFloat=0.5
 init(){super.init(frame:.zero);isVertical=true;dividerStyle = .thin;delegate=self;setAccessibilityLabel("调整本地和远程文件栏宽度")}
 required init?(coder:NSCoder){fatalError()}
 override var dividerThickness:CGFloat{5}
 override var dividerColor:NSColor{CommanderPalette.line}
 override func layout(){
  super.layout();guard !adjusting,subviews.count==2,bounds.width>560 else{return}
  lastWidth=bounds.width;let available=bounds.width-dividerThickness,position=min(max(280,available*ratio),available-280)
  if !positioned || abs(subviews[0].frame.width-position)>0.5{adjusting=true;positioned=true;setPosition(position,ofDividerAt:0);adjusting=false}
 }
 func splitView(_ splitView:NSSplitView,constrainMinCoordinate proposedMinimumPosition:CGFloat,ofSubviewAt dividerIndex:Int)->CGFloat{max(280,proposedMinimumPosition)}
 func splitView(_ splitView:NSSplitView,constrainMaxCoordinate proposedMaximumPosition:CGFloat,ofSubviewAt dividerIndex:Int)->CGFloat{min(bounds.width-dividerThickness-280,proposedMaximumPosition)}
 func splitView(_ splitView:NSSplitView,effectiveRect proposedEffectiveRect:NSRect,forDrawnRect drawnRect:NSRect,ofDividerAt dividerIndex:Int)->NSRect{proposedEffectiveRect.insetBy(dx:-4,dy:0)}
 func splitViewDidResizeSubviews(_ notification:Notification){guard !adjusting,positioned,subviews.count==2,abs(bounds.width-lastWidth)<0.5,bounds.width>dividerThickness else{return};ratio=min(1,max(0,subviews[0].frame.width/(bounds.width-dividerThickness)))}
}

final class CommanderWorkspace:NSSplitView,NSSplitViewDelegate {
 private var positioned=false
 init(){super.init(frame:.zero);isVertical=false;dividerStyle = .thin;delegate=self}
 required init?(coder:NSCoder){fatalError()}
 override var dividerColor:NSColor{CommanderPalette.line}
 override func layout(){super.layout();if !positioned,bounds.height>440,subviews.count==2{positioned=true;setPosition(bounds.height-194,ofDividerAt:0)};if subviews.count==2,bounds.height>=485{let current=subviews[0].frame.height;let desired=min(max(350,current),bounds.height-135);if abs(current-desired)>0.5{setPosition(desired,ofDividerAt:0)}}}
 func splitView(_ splitView:NSSplitView,constrainMinCoordinate proposedMinimumPosition:CGFloat,ofSubviewAt dividerIndex:Int)->CGFloat{max(proposedMinimumPosition,350)}
 func splitView(_ splitView:NSSplitView,constrainMaxCoordinate proposedMaximumPosition:CGFloat,ofSubviewAt dividerIndex:Int)->CGFloat{min(proposedMaximumPosition,bounds.height-135)}
}

// File names stay readable while the complete destination remains available below and in the tooltip.
final class CommanderQueuePathCell:NSTableCellView {
 private let parent=NSTextField(labelWithString:"")
 override var backgroundStyle:NSView.BackgroundStyle{didSet{updateColors()}}
 override init(frame:NSRect){super.init(frame:frame)
  let name=NSTextField(labelWithString:"");name.font = .systemFont(ofSize:12,weight:.medium);name.lineBreakMode = .byTruncatingMiddle
  parent.font = .systemFont(ofSize:10.5);parent.lineBreakMode = .byTruncatingMiddle
  textField=name;for view in [name,parent]{view.translatesAutoresizingMaskIntoConstraints=false;addSubview(view)}
  NSLayoutConstraint.activate([name.leadingAnchor.constraint(equalTo:leadingAnchor,constant:7),name.trailingAnchor.constraint(equalTo:trailingAnchor,constant:-7),name.topAnchor.constraint(equalTo:topAnchor,constant:4),parent.leadingAnchor.constraint(equalTo:name.leadingAnchor),parent.trailingAnchor.constraint(equalTo:name.trailingAnchor),parent.topAnchor.constraint(equalTo:name.bottomAnchor,constant:1)])
  updateColors()
 }
 required init?(coder:NSCoder){fatalError()}
 func configure(_ path:String){let url=path as NSString;textField?.stringValue=url.lastPathComponent.isEmpty ? path : url.lastPathComponent;parent.stringValue=url.deletingLastPathComponent;toolTip=path;setAccessibilityLabel(path)}
 private func updateColors(){textField?.textColor=backgroundStyle == .emphasized ? .alternateSelectedControlTextColor : CommanderPalette.ink;parent.textColor=backgroundStyle == .emphasized ? .alternateSelectedControlTextColor : CommanderPalette.muted}
}

final class CommanderQueueProgressCell:NSTableCellView {
 private let caption=NSTextField(labelWithString:"");private var amount:Double=0
 override init(frame:NSRect){super.init(frame:frame);caption.font = .systemFont(ofSize:11);caption.lineBreakMode = .byTruncatingMiddle;caption.translatesAutoresizingMaskIntoConstraints=false;addSubview(caption);textField=caption;NSLayoutConstraint.activate([caption.leadingAnchor.constraint(equalTo:leadingAnchor,constant:80),caption.trailingAnchor.constraint(equalTo:trailingAnchor,constant:-6),caption.centerYAnchor.constraint(equalTo:centerYAnchor)])}
 required init?(coder:NSCoder){fatalError()}
 func configure(_ text:String){caption.stringValue=text;toolTip=text;amount=text.firstIndex(of:"%").flatMap{Double(text[..<$0])}.map{min(1,max(0,$0/100))} ?? (text.contains("完成") ? 1 : 0);needsDisplay=true}
 override func draw(_ dirtyRect:NSRect){super.draw(dirtyRect);let rect=NSRect(x:7,y:bounds.midY-2.5,width:62,height:5);NSColor(calibratedRed:0.85,green:0.89,blue:0.95,alpha:1).setFill();NSBezierPath(roundedRect:rect,xRadius:2.5,yRadius:2.5).fill();if amount>0{CommanderPalette.blue.setFill();NSBezierPath(roundedRect:NSRect(x:rect.minX,y:rect.minY,width:rect.width*amount,height:rect.height),xRadius:2.5,yRadius:2.5).fill()}}
}

// Keep function keys readable while retaining the native button actions and accessibility.
final class CommanderShortcutButton:CommanderChromeButton {
 override func draw(_ dirtyRect:NSRect){
  let original=title
  // This footer uses its own keycap and caption instead of the standard cell drawing.
  if cell?.isHighlighted==true{CommanderPalette.line.withAlphaComponent(0.5).setFill();bounds.fill()}
  let parts=original.components(separatedBy:"  ")
  let key=parts.count>1 ? parts[0] : "",caption=parts.count>1 ? parts.dropFirst().joined(separator:"  ") : original
  let attributes:[NSAttributedString.Key:Any]=[.font:NSFont.systemFont(ofSize:11.5),.foregroundColor:isEnabled ? CommanderPalette.ink : NSColor.disabledControlTextColor]
  let text=NSAttributedString(string:caption,attributes:attributes),size=text.size()
  let total=size.width+(key.isEmpty ? 0 : 35),start=(bounds.width-total)/2
  if !key.isEmpty {
   let rect=NSRect(x:start,y:bounds.midY-9,width:28,height:18)
   NSColor.white.setFill();let path=NSBezierPath(roundedRect:rect,xRadius:3,yRadius:3);path.fill();CommanderPalette.line.setStroke();path.lineWidth=0.7;path.stroke()
   let label=NSAttributedString(string:key,attributes:[.font:NSFont.monospacedSystemFont(ofSize:10,weight:.medium),.foregroundColor:CommanderPalette.muted]);let keySize=label.size();label.draw(at:NSPoint(x:rect.midX-keySize.width/2,y:rect.midY-keySize.height/2))
  }
  text.draw(at:NSPoint(x:start+(key.isEmpty ? 0 : 35),y:bounds.midY-size.height/2))
  CommanderPalette.line.withAlphaComponent(0.7).setFill();NSRect(x:bounds.maxX-1,y:7,width:1,height:bounds.height-14).fill()
 }
}

// In-window command menus keep the Commander actions discoverable beside the file panes.
final class CommanderMenuStrip:NSView {
 let menus:[NSPopUpButton]
 init(target:AnyObject,action:Selector){
  menus=CommanderMenus.build(target:target,action:action).map{item in
   let button=NSPopUpButton(frame:.zero,pullsDown:true)
   let menu=item.submenu!
   menu.insertItem(withTitle:item.title,action:nil,keyEquivalent:"",at:0)
   // Keyboard equivalents belong to the system menu; these are duplicate mouse access points.
   for child in menu.items{child.keyEquivalent=""}
   button.menu=menu;button.isBordered=false;button.font = .systemFont(ofSize:12)
   button.setContentHuggingPriority(.required,for:.horizontal)
   button.setAccessibilityLabel(item.title+"菜单")
   return button
  }
  super.init(frame:.zero)
  let caption=NSTextField(labelWithString:"COMMANDER");caption.font = .systemFont(ofSize:10,weight:.semibold);caption.textColor=CommanderPalette.muted
  let row=NSStackView(views:menus+[NSView(),caption]);row.spacing=6;row.alignment = .centerY
  row.translatesAutoresizingMaskIntoConstraints=false;addSubview(row)
  NSLayoutConstraint.activate([row.leadingAnchor.constraint(equalTo:leadingAnchor,constant:8),row.trailingAnchor.constraint(equalTo:trailingAnchor,constant:-12),row.topAnchor.constraint(equalTo:topAnchor),row.bottomAnchor.constraint(equalTo:bottomAnchor),heightAnchor.constraint(equalToConstant:26)])
  wantsLayer=true;layer?.backgroundColor=NSColor.white.cgColor
 }
 required init?(coder:NSCoder){fatalError()}
}
