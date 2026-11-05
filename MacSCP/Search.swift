import Foundation
final class SearchCancellation {
 private let lock=NSLock();private var cancelled=false;private var interrupt:(()->Void)?
 func cancel(){lock.lock();cancelled=true;let action=interrupt;lock.unlock();action?()}
 func setInterrupt(_ action:(()->Void)?){lock.lock();interrupt=action;let invoke=cancelled;lock.unlock();if invoke{action?()}}
 func check()throws{lock.lock();let value=cancelled;lock.unlock();if value{throw SFTPError.message("查找已取消")}}
}
struct SearchHit {let path:String;let directory:Bool;let size:UInt64}
struct SearchResults {let hits:[SearchHit];let warnings:[String];let scanned:Int;let truncated:Bool}
enum RemoteSearch {
 static func pattern(_ query:String)throws->NSRegularExpression{guard !query.isEmpty,query.count<=1024 else{throw SFTPError.message("请输入 1–1024 字符的名称或通配符")};let value=query.contains("*") || query.contains("?") ? query : "*"+query+"*";let expression="^"+value.map{c in c=="*" ? ".*" : c=="?" ? "." : NSRegularExpression.escapedPattern(for:String(c))}.joined()+"$";return try NSRegularExpression(pattern:expression,options:[.caseInsensitive,.dotMatchesLineSeparators])}
 static func find(root:String,query:String,client:RemoteFileClient,cancellation:SearchCancellation,maximumResults:Int=10000,maximumEntries:Int=250000,progress:((Int,String)->Void)?=nil)throws->SearchResults{guard maximumResults>0,maximumEntries>0 else{throw SFTPError.message("无效的查找限制")};try cancellation.check();let regex=try pattern(query);let canonical=try client.canonical(root);var pending=[canonical],index=0,hits=[SearchHit](),warnings=[String](),scanned=0,truncated=false
 while index<pending.count{try cancellation.check();let directory=pending[index];index+=1;let entries:[RemoteFile];do{entries=try client.list(directory)}catch{try cancellation.check();if directory==canonical{throw error};warnings.append(directory+"："+error.localizedDescription);continue};for entry in entries{try cancellation.check();if scanned>=maximumEntries || hits.count>=maximumResults{truncated=true;break};scanned+=1;let path=(directory=="/" ? "/" : directory+"/")+entry.name;if regex.firstMatch(in:entry.name,range:NSRange(entry.name.startIndex...,in:entry.name)) != nil{hits.append(SearchHit(path:path,directory:entry.directory,size:entry.size))};if entry.directory{pending.append(path)}};progress?(scanned,directory);if truncated{break}}
 return SearchResults(hits:hits,warnings:warnings,scanned:scanned,truncated:truncated)}
}
struct DirectoryBookmark:Codable,Equatable {let id:UUID;var name:String;let path:String;let scope:String}
final class BookmarkStore {
 let url:URL;private(set) var bookmarks=[DirectoryBookmark]()
 init(url:URL)throws{self.url=url;if FileManager.default.fileExists(atPath:url.path){bookmarks=try JSONDecoder().decode([DirectoryBookmark].self,from:Data(contentsOf:url))}}
 func save(name:String,path:String,scope:String)throws{guard !name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,path.hasPrefix("/"),!path.contains("\0"),!scope.isEmpty else{throw SFTPError.message("请输入有效的书签名称和绝对路径")};var list=bookmarks;if let i=list.firstIndex(where:{$0.path==path && $0.scope==scope}){list[i].name=name}else{list.append(DirectoryBookmark(id:UUID(),name:name,path:path,scope:scope))};try persist(list);bookmarks=list}
 func remove(id:UUID)throws{let list=bookmarks.filter{$0.id != id};try persist(list);bookmarks=list}
 func inScope(_ scope:String)->[DirectoryBookmark]{bookmarks.filter{$0.scope==scope}.sorted{$0.name.localizedStandardCompare($1.name) == .orderedAscending}}
 private func persist(_ list:[DirectoryBookmark])throws{try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true,attributes:[.posixPermissions:0o700]);try JSONEncoder().encode(list).write(to:url,options:.atomic);try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:url.path)}
}
