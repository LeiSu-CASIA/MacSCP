import Cocoa

struct FileClipboardSnapshot {var payload:Data?;var urls=[URL]();var text:String?}
protocol FileClipboardAccess:AnyObject {func read()throws->FileClipboardSnapshot;func write(_ value:FileClipboardSnapshot)throws}
struct FileClipboardEnvelope:Codable {
 let version:Int,owner:UUID,files:[DragFile]
 static let type=NSPasteboard.PasteboardType("local.macscp.clipboard-files.v1")
 static let maximumBytes=FileReferenceValidation.maximumBytes,maximumItems=FileReferenceValidation.maximumItems
 static func validated(_ files:[DragFile])throws->[DragFile]{try FileReferenceValidation.validated(files)}
 static func encode(owner:UUID,files:[DragFile])throws->FileClipboardSnapshot{let files=try validated(files),data=try JSONEncoder().encode(Self(version:1,owner:owner,files:files));guard data.count<=maximumBytes else{throw SFTPError.message("剪贴板文件清单超过 8 MiB")};return FileClipboardSnapshot(payload:data,urls:files.allSatisfy{$0.connection==nil} ? files.map{URL(fileURLWithPath:$0.path)} : [],text:files.map{$0.path}.joined(separator:"\n"))}
 static func files(_ snapshot:FileClipboardSnapshot,owner:UUID)throws->[DragFile]?{
  if let data=snapshot.payload{guard data.count<=maximumBytes else{throw SFTPError.message("剪贴板清单过大")};let value=try JSONDecoder().decode(Self.self,from:data);guard value.version==1 else{throw SFTPError.message("不支持的剪贴板版本")};if value.owner==owner{return try validated(value.files)};if snapshot.urls.isEmpty{throw SFTPError.message("来源属于另一实例，请在本窗口重新复制服务器文件")}}
  guard !snapshot.urls.isEmpty else{return nil};guard snapshot.urls.count<=maximumItems else{throw SFTPError.message("剪贴板文件过多")}
  let reader=LocalReadClient();defer{reader.close()}
  return try validated(snapshot.urls.map{url in guard url.isFileURL,url.host==nil || url.host=="" || url.host=="localhost",let info=try reader.attributes(url.path) else{throw SFTPError.message("剪贴板本地文件不存在或不是本机文件 URL")};return DragFile(path:url.standardizedFileURL.path,directory:info.mode&0o170000==0o040000,size:info.size,connection:nil)})
 }
 static func directoryText(_ text:String?)throws->String?{guard let text=text?.trimmingCharacters(in:.whitespacesAndNewlines),!text.isEmpty else{return nil};guard text.utf8.count<=32768,!text.contains("\0"),!text.contains("\n"),!text.contains("\r") else{throw SFTPError.message("请粘贴单个绝对目录路径，或复制文件后粘贴")};guard text.hasPrefix("/") else{return nil};return text}
}
final class SystemFileClipboard:FileClipboardAccess {
 private let suppliedBoard:NSPasteboard?
 private var board:NSPasteboard{suppliedBoard ?? .general}
 init(_ board:NSPasteboard?=nil){suppliedBoard=board}
 func read()throws->FileClipboardSnapshot{let revision=board.changeCount,items=board.pasteboardItems ?? [];guard items.count<=FileClipboardEnvelope.maximumItems else{throw SFTPError.message("剪贴板项目过多")};let result=FileClipboardSnapshot(payload:board.data(forType:FileClipboardEnvelope.type),urls:items.compactMap{$0.string(forType:.fileURL).flatMap(URL.init(string:))},text:board.string(forType:.string));guard board.changeCount==revision else{throw SFTPError.message("剪贴板已变化，请重试")};return result}
 func write(_ value:FileClipboardSnapshot)throws{
  var items=[NSPasteboardItem]()
  for url in value.urls{let item=NSPasteboardItem();item.setString(url.absoluteString,forType:.fileURL);items.append(item)}
  if items.isEmpty{items.append(NSPasteboardItem())};if let data=value.payload{items[0].setData(data,forType:FileClipboardEnvelope.type)};if let text=value.text{items[0].setString(text,forType:.string)}
  board.clearContents();guard board.writeObjects(items) else{throw SFTPError.message("无法写入剪贴板")}
 }
}
