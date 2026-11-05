import Foundation

enum RecoveryKey:Hashable {
 case transfer(UUID),relay(UUID)
 var text:String{switch self{case .transfer(let id):return "transfer:"+id.uuidString;case .relay(let id):return "relay:"+id.uuidString}}
}
enum RecoveryItem {
 case transfer(TransferRecord),relay(RelayRecord)
 var key:RecoveryKey{switch self{case .transfer(let record):return .transfer(record.id);case .relay(let record):return .relay(record.id)}}
 var sites:[Session]{switch self{case .transfer(let r):return [r.site];case .relay(let r):return [r.download.site,r.upload.site]}}
 var kind:String{switch self{case .transfer(let r):return r.up ? "↑ 上传" : "↓ 下载";case .relay:return "⇄ 中转"}}
 var source:String{switch self{case .transfer(let r):return r.up ? r.source : r.site.identity+":"+r.source;case .relay(let r):return r.download.site.identity+":"+r.download.source}}
 var destination:String{switch self{case .transfer(let r):return r.up ? r.site.identity+":"+r.destination : r.destination;case .relay(let r):return r.upload.site.identity+":"+r.upload.destination}}
 func missingSites(_ connected:Set<String>)->[String]{Array(Set(sites.map{$0.identity}).subtracting(connected)).sorted()}
 func status(_ connected:Set<String>)->String{let missing=missingSites(connected);return missing.isEmpty ? "已登录，恢复前校验暂存" : "等待登录："+missing.joined(separator:"、")}
 var details:String{
  let record:TransferRecord;let policy:TransferPolicy;var extra=""
  switch self{case .transfer(let r):record=r;policy=r.policy ?? TransferPolicy();case .relay(let r):record=r.upload;policy=r.download.policy ?? TransferPolicy();extra="\n本机中转副本："+r.staging+"\n源下载与目标上传将成组恢复。"}
  return kind+"\n源："+source+"\n目标："+destination+"\n覆盖："+(record.overwrite ? "按原设置替换文件 / 合并目录" : "不覆盖已有项")+"\n类型："+(record.directory ? "目录（恢复时重新扫描）" : "文件")+"\n上次记录大小："+ByteCountFormatter.string(fromByteCount:Int64(clamping:record.size),countStyle:.file)+"\n包含："+(policy.include.isEmpty ? "全部" : policy.include)+"\n排除："+(policy.exclude.isEmpty ? "无" : policy.exclude)+extra
 }
}
struct RecoverySelection {
 private(set) var items:[RecoveryItem]
 private(set) var selected=Set<RecoveryKey>()
 private(set) var connected:Set<String>
 init(items:[RecoveryItem],connected:Set<String>){self.items=items;self.connected=connected}
 var checked:[RecoveryItem]{items.filter{selected.contains($0.key)}}
 var canRestore:Bool{!checked.isEmpty && checked.allSatisfy{$0.missingSites(connected).isEmpty}}
 mutating func refresh(items:[RecoveryItem],connected:Set<String>){self.items=items;self.connected=connected;selected.formIntersection(Set(items.map{$0.key}))}
 mutating func set(_ key:RecoveryKey,selected value:Bool){guard items.contains(where:{$0.key==key}) else{return};if value{selected.insert(key)}else{selected.remove(key)}}
 mutating func selectReady(){selected=Set(items.filter{$0.missingSites(connected).isEmpty}.map{$0.key})}
 mutating func clear(){selected=[]}
}
struct RecoveryEndpoint {let site:Session;let socket:String}
typealias RecoveryClientFactory=(Session,String)throws->RemoteFileClient
struct PreparedRecovery {
 let item:RecoveryItem
 let transfer:TransferJob?
 let relay:RelayTransfer?
 let endpoints:[String:String]
 var jobs:[TransferJob]{if let transfer=transfer{return [transfer]};if let relay=relay{return [relay.download,relay.upload]};return []}
 func sessionsStillMatch(_ live:[String:RecoveryEndpoint])->Bool{endpoints.allSatisfy{live[$0.key]?.socket==$0.value}}
 static func make(_ item:RecoveryItem,connections:[String:RecoveryEndpoint],factory:@escaping RecoveryClientFactory)throws->PreparedRecovery{
  var expected=[String:String]()
  for site in item.sites{guard let endpoint=connections[site.identity] else{throw SFTPError.message("请先登录："+site.identity)};expected[site.identity]=endpoint.socket}
  switch item{
  case .transfer(let record):
   let job=try TransferJob.restore(record),connection=connections[record.site.identity]!
   job.factory={try factory(connection.site,connection.socket)}
   return PreparedRecovery(item:item,transfer:job,relay:nil,endpoints:expected)
  case .relay(let record):
   let relay=try RelayTransfer(record:record),source=connections[record.download.site.identity]!,target=connections[record.upload.site.identity]!
   relay.download.factory={try factory(source.site,source.socket)};relay.upload.factory={try factory(target.site,target.socket)}
   return PreparedRecovery(item:item,transfer:nil,relay:relay,endpoints:expected)
  }
 }
}
