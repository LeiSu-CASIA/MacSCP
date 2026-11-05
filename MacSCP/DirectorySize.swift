import Foundation

final class DirectorySizeCancellation {
 private let lock=NSLock();private var stopped=false;private var interrupt:(()->Void)?
 var cancelled:Bool{lock.lock();defer{lock.unlock()};return stopped}
 func cancel(){lock.lock();stopped=true;let action=interrupt;lock.unlock();action?()}
 func setInterrupt(_ action:(()->Void)?){lock.lock();interrupt=action;let invoke=stopped;lock.unlock();if invoke{action?()}}
 func check()throws{if cancelled{throw SFTPError.message("统计已取消")}}
}
struct DirectorySizeNode:Equatable {
 enum Kind{case file,directory,link,other}
 let kind:Kind;let bytes:UInt64;let signature:String
}
struct DirectorySizeResult {
 var bytes:UInt64=0,files=0,directories=0,links=0,other=0,scanned=0,warningCount=0
 var warnings=[String]();var limited=false
 var complete:Bool{!limited && warningCount==0}
 var summary:String{"\(files) 个文件 · \(directories) 个目录 · \(links) 个符号链接"+(other>0 ? " · \(other) 个特殊项" : "")}
 var sizeText:String{ByteCountFormatter.string(fromByteCount:Int64(clamping:bytes),countStyle:.file)+"（\(bytes) 字节）"}
}
enum DirectorySizeScanner {
 struct Limits{var entries=250000;var depth=256}
 static func path(_ value:String)throws->String{
  guard value.hasPrefix("/"),!value.contains("\0"),!value.split(separator:"/").contains("..") else{throw SFTPError.message("统计需要绝对路径，不能包含 .. 或空字符")}
  let components=value.split(separator:"/").filter{$0 != "."};return "/"+components.joined(separator:"/")
 }
 static func scan(paths:[String],cancellation:DirectorySizeCancellation,limits:Limits=Limits(),metadata:(String)throws->DirectorySizeNode,list:(String)throws->[String],progress:((DirectorySizeResult,String)->Void)?=nil)throws->DirectorySizeResult{
  guard limits.entries>0,limits.depth>=0 else{throw SFTPError.message("无效的统计限制")}
  var pending=try paths.map{(try path($0),0)},seen=Set<String>(),result=DirectorySizeResult(),lastProgress=Date.distantPast
  func warn(_ message:String){result.warningCount+=1;if result.warnings.count<100{result.warnings.append(message)}}
  while let (item,depth)=pending.popLast(){
   try cancellation.check();guard !seen.contains(item) else{continue}
   guard result.scanned<limits.entries else{result.limited=true;break};seen.insert(item);result.scanned+=1
   do{
    let node=try metadata(item)
    switch node.kind{
    case .file:let sum=result.bytes.addingReportingOverflow(node.bytes);guard !sum.overflow else{throw SFTPError.message("文件总大小超出计数范围")};result.bytes=sum.partialValue;result.files+=1
    case .link:result.links+=1
    case .other:result.other+=1
    case .directory:
     result.directories+=1
     guard depth<limits.depth else{result.limited=true;warn(item+"：达到目录深度上限");continue}
     let names=try list(item);try cancellation.check()
     guard try metadata(item)==node else{warn(item+"：扫描期间目录属性变化，请重新统计");continue}
     let available=max(0,limits.entries-result.scanned-pending.count)
     if names.count>available{result.limited=true}
     for name in names.prefix(available){
      guard !name.isEmpty,name != ".",name != "..",!name.contains("/"),!name.contains("\0") else{warn(item+"：忽略无效的目录条目");continue}
      pending.append(((item=="/" ? "/" : item+"/")+name,depth+1))
     }
    }
   }catch{try cancellation.check();warn(item+"："+error.localizedDescription)}
   if Date().timeIntervalSince(lastProgress)>=0.1{lastProgress=Date();progress?(result,item)}
  }
  try cancellation.check();progress?(result,"");return result
 }
 static func local(paths:[String],cancellation:DirectorySizeCancellation,limits:Limits=Limits(),progress:((DirectorySizeResult,String)->Void)?=nil)throws->DirectorySizeResult{
  try scan(paths:paths,cancellation:cancellation,limits:limits,metadata:{path in
   let a=try FileManager.default.attributesOfItem(atPath:path),type=a[.type] as? FileAttributeType
   let kind:DirectorySizeNode.Kind=type == .typeRegular ? .file : type == .typeDirectory ? .directory : type == .typeSymbolicLink ? .link : .other
   return DirectorySizeNode(kind:kind,bytes:(a[.size] as? NSNumber)?.uint64Value ?? 0,signature:"\(a[.systemNumber] ?? ""):\(a[.systemFileNumber] ?? ""):\(a[.modificationDate] ?? ""):\(type?.rawValue ?? "")")
  },list:{try FileManager.default.contentsOfDirectory(atPath:$0)},progress:progress)
 }
 static func remote(paths:[String],client:RemoteFileClient,cancellation:DirectorySizeCancellation,limits:Limits=Limits(),progress:((DirectorySizeResult,String)->Void)?=nil)throws->DirectorySizeResult{
  try scan(paths:paths,cancellation:cancellation,limits:limits,metadata:{path in
   try cancellation.check();guard let a=try client.attributes(path) else{throw SFTPError.message("项目已不存在")}
   let type=a.mode&0o170000,kind:DirectorySizeNode.Kind=type==0o100000 ? .file : type==0o040000 ? .directory : type==0o120000 ? .link : .other
   return DirectorySizeNode(kind:kind,bytes:a.size,signature:"\(a.mode):\(a.modified)")
  },list:{try client.list($0,maximumEntries:limits.entries).map{$0.name}},progress:progress)
 }
}
