import Foundation

enum BrowserSide {case local,remote;var opposite:BrowserSide{self == .local ? .remote : .local}}
struct BrowseIntent {let id:UUID;let side:BrowserSide;let from:String;let counterpart:String}
struct LinkedBrowseRequest {let id:UUID;let side:BrowserSide;let path:String}
enum BrowseNavigationOrigin {case user,passive,linked(LinkedBrowseRequest),history(DirectoryHistory.Request)
 var isUser:Bool{switch self{case .user,.history:return true;default:return false}}}
struct DirectoryBrowseRequest {
 let target:String;let origin:BrowseNavigationOrigin;let intent:BrowseIntent?
 func obsolete(in link:LinkedBrowsing?)->Bool{if case .linked(let request)=origin{return link?.isCurrent(request.id) != true};if let intent=intent,link?.enabled==true{return !link!.isCurrent(intent.id)};return false}
}

// A navigation which follows another navigation carries its original ticket,
// rather than becoming a new user navigation and bouncing back to the source.
final class LinkedBrowsing {
 private(set) var enabled=false
 private var latest:UUID?
 private var projection:(id:UUID,source:BrowserSide,from:String,target:String)?
 init(enabled:Bool=false){self.enabled=enabled}
 func setEnabled(_ value:Bool){enabled=value;latest=nil;projection=nil}
 func invalidate(){latest=nil;projection=nil}
 func begin(side:BrowserSide,from:String,counterpart:String)->BrowseIntent?{
  guard enabled,(try? Self.components(from)) != nil,(try? Self.components(counterpart)) != nil else{return nil}
  let base:String
  if let pending=projection,pending.source==side,(try? Self.components(pending.from)) == (try? Self.components(from)){base=pending.target}else{base=counterpart}
  projection=nil;let id=UUID();latest=id;return BrowseIntent(id:id,side:side,from:from,counterpart:base)
 }
 func isCurrent(_ id:UUID)->Bool{enabled && latest==id}
 func followedPath(_ intent:BrowseIntent,arrived:String)throws->LinkedBrowseRequest?{
  guard isCurrent(intent.id) else{return nil}
  let old=try Self.components(intent.from),new=try Self.components(arrived)
  guard old != new else{return nil}
  var shared=0;while shared<min(old.count,new.count) && old[shared]==new[shared]{shared+=1}
  let up=old.count-shared,other=try Self.components(intent.counterpart)
  guard up<=other.count else{throw SFTPError.message("另一侧已到根目录，无法继续同步浏览")}
  let path=Array(other.dropLast(up))+new.dropFirst(shared)
  let target="/"+path.joined(separator:"/");projection=(intent.id,intent.side,arrived,target)
  return LinkedBrowseRequest(id:intent.id,side:intent.side.opposite,path:target)
 }
 func accepted(_ request:LinkedBrowseRequest){if projection?.id==request.id,projection?.source.opposite==request.side{projection=nil}}
 static func components(_ path:String)throws->[String]{
  guard path.hasPrefix("/"),!path.contains("\0") else{throw SFTPError.message("同步浏览需要有效的绝对路径")}
  var result=[String]();for piece in path.split(separator:"/",omittingEmptySubsequences:true){if piece=="."{continue};if piece==".."{guard !result.isEmpty else{throw SFTPError.message("目录超出根路径")};result.removeLast()}else{result.append(String(piece))}};return result
 }
}

struct RemoteDirectoryRead {
 let path:String;let entries:[RemoteFile]
 static func read(_ target:String,client:RemoteFileClient)throws->RemoteDirectoryRead{let path=try client.canonical(target);return RemoteDirectoryRead(path:path,entries:try client.list(path,resolveLinks:true))}
 static func missing(_ target:String,client:RemoteFileClient)->Bool{do{var path="";for part in try LinkedBrowsing.components(target){path+="/"+part;guard let a=try client.attributes(path) else{return true};guard a.mode&0o170000 == 0o040000 else{return false}};return false}catch{return false}}
}

enum LinkedDirectoryCreator {
 static func localComponents(_ path:String)throws->[String]{
  let parts=try LinkedBrowsing.components(path)
  // Foundation can display macOS's system aliases even after resolving a URL.
  // Accept only these known root aliases; user-created links remain refused.
  if let first=parts.first,["var","tmp","etc"].contains(first),let target=try? FileManager.default.destinationOfSymbolicLink(atPath:"/"+first),["private/"+first,"/private/"+first].contains(target){return ["private",first]+parts.dropFirst()}
  return parts
 }
 static func localMissing(_ path:String)->Bool{
  guard let parts=try? localComponents(path) else{return false};var current=""
  for part in parts{current+="/"+part;do{let a=try FileManager.default.attributesOfItem(atPath:current);guard a[.type] as? FileAttributeType == .typeDirectory else{return false}}catch let error as NSError{if let underlying=error.userInfo[NSUnderlyingErrorKey] as? NSError,underlying.domain==NSPOSIXErrorDomain{return underlying.code==2};return error.domain==NSCocoaErrorDomain && error.code==NSFileReadNoSuchFileError || error.domain==NSPOSIXErrorDomain && error.code==2}}
  return false
 }
 static func local(_ path:String)throws{
  let fm=FileManager.default;var current=""
  for component in try localComponents(path){current+="/"+component
   do{let a=try fm.attributesOfItem(atPath:current);guard a[.type] as? FileAttributeType == .typeDirectory else{throw SFTPError.message("对应路径含文件或符号链接："+current)}}catch{
    guard localMissing(current) else{throw error}
    do{try fm.createDirectory(atPath:current,withIntermediateDirectories:false)}catch{let a=try fm.attributesOfItem(atPath:current);guard a[.type] as? FileAttributeType == .typeDirectory else{throw error}}
   }
  }
 }
 static func remote(_ path:String,client:RemoteFileClient)throws{
  var current=""
  for component in try LinkedBrowsing.components(path){current+="/"+component
   if let a=try client.attributes(current){guard a.mode&0o170000 == 0o040000 else{throw SFTPError.message("对应路径含文件或符号链接："+current)}}else{
    do{try client.mkdir(current)}catch{guard let a=try client.attributes(current),a.mode&0o170000 == 0o040000 else{throw error}}
   }
  }
 }
}
