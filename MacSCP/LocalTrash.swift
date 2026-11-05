import Foundation
import Darwin

struct LocalTrashSignature:Equatable {
 let type:String,device:UInt64,inode:UInt64,size:UInt64,modified:Date?,created:Date?,permissions:UInt32,link:String?
 static func read(_ path:String)throws->LocalTrashSignature{
  let a=try FileManager.default.attributesOfItem(atPath:path)
  guard let type=a[.type] as? FileAttributeType,let device=a[.systemNumber] as? NSNumber,let inode=a[.systemFileNumber] as? NSNumber else{throw SFTPError.message("无法确认本地项目身份："+path)}
  return LocalTrashSignature(type:type.rawValue,device:device.uint64Value,inode:inode.uint64Value,size:(a[.size] as? NSNumber)?.uint64Value ?? 0,modified:a[.modificationDate] as? Date,created:a[.creationDate] as? Date,permissions:(a[.posixPermissions] as? NSNumber)?.uint32Value ?? 0,link:type == .typeSymbolicLink ? try FileManager.default.destinationOfSymbolicLink(atPath:path) : nil)
 }
 func sameDirectory(_ other:LocalTrashSignature)->Bool{type==FileAttributeType.typeDirectory.rawValue && other.type==type && device==other.device && inode==other.inode}
}
struct LocalTrashItem {let path:String;let signature:LocalTrashSignature}
struct LocalTrashPlan {
 let directory:String,ancestors:[LocalTrashItem],items:[LocalTrashItem]
 static func canonicalDirectory(_ path:String)throws->String{guard let resolved=realpath(path,nil) else{throw NSError(domain:NSPOSIXErrorDomain,code:Int(errno))};defer{free(resolved)};return String(cString:resolved)}
 static func prepare(directory:String,names:[String])throws->LocalTrashPlan{
  guard directory.hasPrefix("/"),!directory.contains("\0"),!directory.split(separator:"/").contains(".."),!names.isEmpty,names.count<=10000 else{throw SFTPError.message("请选择有效目录中的 1–10000 项，不包含上级目录")}
  // Resolve the browsing root once; selected links themselves are never resolved.
  let base=try canonicalDirectory(directory)
  var ancestors=[LocalTrashItem](),cursor=""
  for part in [""]+base.split(separator:"/").map(String.init){cursor=part.isEmpty ? "/" : (cursor=="/" ? "/" : cursor+"/")+part;let signature=try LocalTrashSignature.read(cursor);guard signature.type==FileAttributeType.typeDirectory.rawValue else{throw SFTPError.message("目录路径包含非目录项目")};ancestors.append(.init(path:cursor,signature:signature))}
  var seen=Set<String>(),items=[LocalTrashItem]()
  for name in names{
   guard !name.isEmpty,name != ".",name != "..",!name.contains("/"),!name.contains("\0") else{throw SFTPError.message("拒绝处理无效的项目名称")}
   guard seen.insert(name).inserted else{continue};let path=(base=="/" ? "/" : base+"/")+name
   items.append(LocalTrashItem(path:path,signature:try LocalTrashSignature.read(path)))
  }
  return LocalTrashPlan(directory:base,ancestors:ancestors,items:items)
 }
 func validateAncestors()throws{for ancestor in ancestors{guard try ancestor.signature.sameDirectory(LocalTrashSignature.read(ancestor.path)) else{throw SFTPError.message("预览后所在目录被替换，请重新选择："+ancestor.path)}}}
 func validate(_ item:LocalTrashItem)throws{guard try LocalTrashSignature.read(item.path)==item.signature else{throw SFTPError.message("预览后项目发生变化，请重新选择："+item.path)}}
 var preview:String{items.map{$0.path.debugDescription}.joined(separator:"\n")}
}
final class LocalTrashCancellation {
 private let lock=NSLock();private var stopped=false
 var cancelled:Bool{lock.lock();defer{lock.unlock()};return stopped}
 func cancel(){lock.lock();stopped=true;lock.unlock()}
}
struct LocalTrashFailure {let path:String,message:String}
struct LocalTrashReport {
 var moved=[String](),failures=[LocalTrashFailure](),cancelled=false
 var summary:String{"已移到废纸篓 \(moved.count) 项 · 失败 \(failures.count) 项"+(cancelled ? " · 已停止剩余项" : "")}
 var details:String{(moved.map{"已移到废纸篓："+$0.debugDescription}+failures.map{"失败："+$0.path.debugDescription+"\n"+$0.message}).joined(separator:"\n")}
}
enum LocalTrashExecutor {
 static func moveToTrash(_ url:URL)throws{try FileManager.default.trashItem(at:url,resultingItemURL:nil)}
 static func execute(_ plan:LocalTrashPlan,cancellation:LocalTrashCancellation,trash:(URL)throws->Void=moveToTrash,progress:((Int,Int,String)->Void)?=nil)throws->LocalTrashReport{
  var report=LocalTrashReport();if cancellation.cancelled{report.cancelled=true;return report}
  // Check the full selection before the first move, then check each item again.
  try plan.validateAncestors();for item in plan.items{if cancellation.cancelled{report.cancelled=true;return report};try plan.validate(item)}
  var last=Date.distantPast
  for (index,item) in plan.items.enumerated(){
   if cancellation.cancelled{report.cancelled=true;break}
   do{try plan.validateAncestors();try plan.validate(item);try trash(URL(fileURLWithPath:item.path));report.moved.append(item.path)}catch{report.failures.append(.init(path:item.path,message:error.localizedDescription))}
   if Date().timeIntervalSince(last)>=0.1{last=Date();progress?(index+1,plan.items.count,item.path)}
  };return report
 }
}
