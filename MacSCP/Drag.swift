import Cocoa
struct DragFile:Codable {let path:String;let directory:Bool;let size:UInt64;let connection:String?}
let scpPasteboard=NSPasteboard.PasteboardType("local.macscp.files")
enum FileReferenceValidation {
 static let maximumItems=10000,maximumBytes=8*1024*1024
 static func validated(_ files:[DragFile])throws->[DragFile]{
  guard !files.isEmpty,files.count<=maximumItems else{throw SFTPError.message("文件清单数量应为 1–10000")}
  var found=Set<String>()
  return try files.filter{file in
   guard file.path.hasPrefix("/"),file.path.utf8.count<=32768,!file.path.contains("\0"),!["/",".","..",""] .contains((file.path as NSString).lastPathComponent),file.path != "/",file.path.split(separator:"/",omittingEmptySubsequences:false).dropFirst().allSatisfy({!$0.isEmpty && $0 != "." && $0 != ".."}),file.connection?.isEmpty != true else{throw SFTPError.message("文件清单包含无效路径")}
   return found.insert((file.connection ?? "local")+"\0"+file.path).inserted
  }
 }
}
struct FileDragRepresentation {let file:Data?,url:String?}
enum FileDragPayload {
 static func decode(_ items:[FileDragRepresentation])throws->[DragFile]{
  guard items.count<=FileReferenceValidation.maximumItems else{throw SFTPError.message("拖放项目过多")};var bytes=0,files=[DragFile]()
  for item in items{bytes+=(item.file?.count ?? 0)+(item.url?.utf8.count ?? 0);guard bytes<=FileReferenceValidation.maximumBytes else{throw SFTPError.message("拖放文件清单超过8 MiB")}
   if let data=item.file{files.append(try JSONDecoder().decode(DragFile.self,from:data))}
   else if let string=item.url{guard let url=URL(string:string),url.isFileURL,url.host==nil || url.host=="" || url.host=="localhost" else{throw SFTPError.message("拖放来源不是本机文件URL")};let values=try url.resourceValues(forKeys:[.isDirectoryKey,.fileSizeKey,.isSymbolicLinkKey]);guard values.isSymbolicLink != true else{throw SFTPError.message("暂不拖放符号链接，请进入实际目录")};files.append(DragFile(path:url.standardizedFileURL.path,directory:values.isDirectory ?? false,size:UInt64(max(0,values.fileSize ?? 0)),connection:nil))}
  };return try FileReferenceValidation.validated(files)
 }
 static func canRead(_ board:NSPasteboard)->Bool{board.types?.contains(where:{$0==scpPasteboard || $0 == .fileURL})==true}
 static func read(_ board:NSPasteboard)throws->[DragFile]{let revision=board.changeCount,items=board.pasteboardItems ?? [];guard items.count<=FileReferenceValidation.maximumItems else{throw SFTPError.message("拖放项目过多")};var rows=[FileDragRepresentation](),bytes=0
  for item in items{let data=item.data(forType:scpPasteboard),url=data==nil ? item.string(forType:.fileURL) : nil;bytes+=(data?.count ?? 0)+(url?.utf8.count ?? 0);guard bytes<=FileReferenceValidation.maximumBytes else{throw SFTPError.message("拖放清单过大")};rows.append(FileDragRepresentation(file:data,url:url))}
  guard board.changeCount==revision else{throw SFTPError.message("拖放来源在读取时变化")};return try decode(rows)
 }
}
final class SessionTabCell:NSButtonCell {
 override func titleRect(forBounds rect:NSRect)->NSRect{var title=super.titleRect(forBounds:rect);title.size.width=max(0,title.width-24);return title}
}
final class SessionTabButton:NSButton {
 let closeButton=NSButton();var close:(()->Void)?;var contextMenu:(()->NSMenu)?
 override func layout(){super.layout();closeButton.frame=NSRect(x:bounds.width-24,y:(bounds.height-20)/2,width:20,height:20)}
 @objc private func closePressed(){close?()}
 override func menu(for event:NSEvent)->NSMenu?{contextMenu?() ?? super.menu(for:event)}
 private var hovered=false;private var tracking:NSTrackingArea?
 override init(frame:NSRect){super.init(frame:frame);cell=SessionTabCell(textCell:"");closeButton.title="";closeButton.image=NSImage(systemSymbolName:"xmark",accessibilityDescription:"关闭会话");closeButton.imageScaling = .scaleProportionallyDown;closeButton.isBordered=false;closeButton.contentTintColor=CommanderPalette.muted;closeButton.target=self;closeButton.action = #selector(closePressed);closeButton.toolTip="关闭此服务器会话";closeButton.setAccessibilityLabel("关闭此服务器会话");addSubview(closeButton);isBordered=false;font = .systemFont(ofSize:12,weight:.medium);cell?.lineBreakMode = .byTruncatingMiddle}
 required init?(coder:NSCoder){fatalError()}
 override var intrinsicContentSize:NSSize{NSSize(width:min(220,max(115,super.intrinsicContentSize.width+38)),height:32)}
 override func updateTrackingAreas(){super.updateTrackingAreas();if let tracking=tracking{removeTrackingArea(tracking)};let area=NSTrackingArea(rect:.zero,options:[.mouseEnteredAndExited,.activeInActiveApp,.inVisibleRect],owner:self,userInfo:nil);tracking=area;addTrackingArea(area)}
 override func mouseEntered(with event:NSEvent){hovered=true;needsDisplay=true}
 override func mouseExited(with event:NSEvent){hovered=false;needsDisplay=true}
 override func draw(_ dirtyRect:NSRect){let path=NSBezierPath(roundedRect:bounds.insetBy(dx:1,dy:1),xRadius:5,yRadius:5);if state == .on{NSColor.white.setFill();path.fill();CommanderPalette.line.setStroke();path.stroke();CommanderPalette.blue.setFill();NSRect(x:7,y:bounds.maxY-3,width:bounds.width-14,height:2).fill()}else if hovered{NSColor.white.withAlphaComponent(0.5).setFill();path.fill()};if dropHighlighted{CommanderPalette.blue.withAlphaComponent(0.14).setFill();path.fill();CommanderPalette.blue.setStroke();path.lineWidth=2;path.stroke()};super.draw(dirtyRect)}
 var hover:(()->Void)?;var acceptsDrop:(()->Bool)?;var receiveDrop:(([DragFile])->Bool)?;var dropFailure:((String)->Void)?
 private var dropToken:(sequence:Int,revision:Int)?
 private var dropHighlighted=false{didSet{needsDisplay=true}}
 private func accepts(_ sender:NSDraggingInfo)->Bool{sender.draggingSourceOperationMask.contains(.copy) && FileDragPayload.canRead(sender.draggingPasteboard) && acceptsDrop?()==true && receiveDrop != nil}
 override func draggingEntered(_ sender:NSDraggingInfo)->NSDragOperation{dropHighlighted=accepts(sender);dropToken=dropHighlighted ? (sender.draggingSequenceNumber,sender.draggingPasteboard.changeCount) : nil;return dropHighlighted ? .copy : []}
 override func draggingUpdated(_ sender:NSDraggingInfo)->NSDragOperation{dropHighlighted=accepts(sender);dropToken=dropHighlighted ? (sender.draggingSequenceNumber,sender.draggingPasteboard.changeCount) : nil;return dropHighlighted ? .copy : []}
 override func draggingExited(_ sender:NSDraggingInfo?){dropHighlighted=false;dropToken=nil}
 private func tokenMatches(_ sender:NSDraggingInfo)->Bool{dropToken?.sequence==sender.draggingSequenceNumber && dropToken?.revision==sender.draggingPasteboard.changeCount}
 override func prepareForDragOperation(_ sender:NSDraggingInfo)->Bool{accepts(sender) && tokenMatches(sender)}
 override func performDragOperation(_ sender:NSDraggingInfo)->Bool{defer{dropHighlighted=false;dropToken=nil};guard accepts(sender),tokenMatches(sender) else{return false};do{return receiveDrop?(try FileDragPayload.read(sender.draggingPasteboard)) ?? false}catch{dropFailure?(error.localizedDescription);return false}}
 override func concludeDragOperation(_ sender:NSDraggingInfo?){dropHighlighted=false;dropToken=nil}
 override func draggingEnded(_ sender:NSDraggingInfo){dropHighlighted=false;dropToken=nil}
}
final class FileTableView:NSTableView {
 var onFocus:(()->Void)?
 override func becomeFirstResponder()->Bool{let result=super.becomeFirstResponder();if result{onFocus?()};return result}
 var keyCommand:((String)->Void)?
 @objc func copy(_ sender:Any?){keyCommand?("copyFiles")}
 @objc func paste(_ sender:Any?){keyCommand?("pasteFiles")}
 override func selectAll(_ sender:Any?){if let command=keyCommand{command("selectAllFiles")}else{super.selectAll(sender)}}
 private func command(for event:NSEvent)->String?{FileKeyAction.resolve(code:event.keyCode,command:event.modifierFlags.contains(.command),shift:event.modifierFlags.contains(.shift),option:event.modifierFlags.contains(.option),control:event.modifierFlags.contains(.control))}
 override func performKeyEquivalent(with event:NSEvent)->Bool{
  guard window?.firstResponder === self,let handler=keyCommand,let key=command(for:event) else{return super.performKeyEquivalent(with:event)}
  handler(key);return true
 }
 override func keyDown(with event:NSEvent){if let handler=keyCommand,let key=command(for:event){handler(key)}else{super.keyDown(with:event)}}

 override func menu(for event:NSEvent)->NSMenu?{let point=convert(event.locationInWindow,from:nil);let clicked=row(at:point);if clicked>=0 && !selectedRowIndexes.contains(clicked){selectRowIndexes(IndexSet(integer:clicked),byExtendingSelection:false)}else if clicked<0{deselectAll(nil)};return super.menu(for:event)}
}
