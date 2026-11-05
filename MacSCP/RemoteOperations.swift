import Foundation
struct RemoteDeleteItem {let path:String;let mode:UInt32;let size:UInt64;let modified:UInt32;var directory:Bool{mode&0o170000 == 0o040000}}
struct RemoteDeletePlan {let items:[RemoteDeleteItem];var fileCount:Int{items.filter{!$0.directory}.count};var directoryCount:Int{items.filter{$0.directory}.count}}
enum RemoteOperations {
 static func deletionPlan(_ paths:[String],client:RemoteFileClient)throws->RemoteDeletePlan{var items=[RemoteDeleteItem](),seen=Set<String>()
 func visit(_ path:String,_ depth:Int)throws{guard depth<512,items.count<100000 else{throw SFTPError.message("目录层级或条目数超过限制")};guard path.hasPrefix("/"),path != "/",!path.split(separator:"/").contains(".."),!path.split(separator:"/").contains("."),!path.contains("\0") else{throw SFTPError.message("拒绝删除无效路径或根目录")};if seen.contains(path){return};seen.insert(path);guard let attrs=try client.attributes(path) else{throw SFTPError.message("目标已不存在：\(path)")};if attrs.mode&0o170000 == 0o040000{for child in try client.list(path){try visit(path+"/"+child.name,depth+1)}};items.append(RemoteDeleteItem(path:path,mode:attrs.mode,size:attrs.size,modified:attrs.modified))}
 for path in paths{try visit(path,0)};return RemoteDeletePlan(items:items)}
 static func delete(_ plan:RemoteDeletePlan,client:RemoteFileClient)throws{
 // Revalidate the entire preview before making any changes. Do not follow symbolic links.
 for item in plan.items{guard let current=try client.attributes(item.path),current.mode==item.mode,current.size==item.size,current.modified==item.modified else{throw SFTPError.message("预览后目标发生变化，请重新预览：\(item.path)")}}
 for item in plan.items{try client.remove(item.path,directory:item.directory)}
 }
 static func permissions(_ text:String)throws->UInt32{guard (3...4).contains(text.count),text.allSatisfy({("0"..."7").contains(String($0))}),let mode=UInt32(text,radix:8),mode<=0o7777 else{throw SFTPError.message("请输入 3 或 4 位八进制权限，例如 644、755、0644")};return mode}
}
