import Foundation

enum SiteImportFormat:String {case macSCPJSON="MacSCP JSON",winSCPINI="WinSCP INI"}
struct SiteImportCandidate:Identifiable {
 let id:Int;let name:String;let protocolName:String;let session:Session?;let notes:[String];let issue:String?;var sourceAddress:String?=nil
 var address:String{session?.identity ?? sourceAddress ?? "—"}
 var eligible:Bool{session != nil && issue==nil}
 var detail:String {
  var lines=["站点："+name,"来源协议："+protocolName]
  if let s=session {lines += ["服务器："+s.identity,"本地目录："+(s.localPath ?? "使用当前本地目录"),"远程目录："+(s.remotePath ?? "使用服务器默认目录"),"私钥："+(s.key.isEmpty ? "使用连接时选择的认证方式" : s.key),"连接超时：\(s.sshOptions.connectTimeout) 秒","保活间隔：\(s.sshOptions.keepAliveInterval) 秒","SSH 压缩："+(s.sshOptions.compression ? "开启" : "关闭")]}
  if let s=session,s.fileProtocol != .sftp{lines=["站点："+name,"协议："+s.fileProtocol.title,"服务器："+s.identity,"本地目录："+(s.localPath ?? "使用当前本地目录"),"远程目录："+(s.remotePath ?? "服务器默认目录"),"FTP 写入："+(s.ftpSettings.allowNonAtomicWrites ? "已许可非原子操作" : "只读"),"保留时间："+String(s.ftpSettings.preserveTime),"保留权限："+String(s.ftpSettings.preservePermissions),"目录列表："+s.ftpSettings.listingMode.title,"连接/响应超时：\(s.ftpSettings.connectTimeout) 秒","显式认证优先："+(s.ftpSettings.prefersSSLAuth ? "AUTH SSL" : "AUTH TLS")]}
  if session==nil,let address=sourceAddress{lines.append("服务器："+address)}
  if let issue=issue{lines.append("无法导入："+issue)}
  if !notes.isEmpty{lines.append("迁移提示：\n"+notes.joined(separator:"\n"))}
  return lines.joined(separator:"\n")
 }
}
struct SiteImportPlan {
 static let maximumBytes=4*1024*1024
 let format:SiteImportFormat;let candidates:[SiteImportCandidate]
 static func read(_ data:Data,fileExtension:String="")throws->SiteImportPlan {
  guard data.count<=maximumBytes else{throw SFTPError.message("站点配置超过 4 MiB")}
  let ext=fileExtension.lowercased()
  if ext=="ini"{return try WinSCPSiteINI.read(data)}
  if ext != "json",let text=try? WinSCPSiteINI.text(data),let first=text.split(whereSeparator:\.isNewline).map({$0.trimmingCharacters(in:.whitespaces)}).first(where:{!$0.isEmpty && !$0.hasPrefix(";") && !$0.hasPrefix("#")}),first.hasPrefix("["),first.hasSuffix("]"),first != "[]",!first.contains("{"),!first.contains("\"") {return try WinSCPSiteINI.read(data)}
  let sessions=try JSONDecoder().decode([Session].self,from:data)
  guard !sessions.isEmpty,sessions.count<=10000 else{throw SFTPError.message("配置中需包含 1–10000 个站点")}
  let rows=sessions.enumerated().map{index,site->SiteImportCandidate in
   do{let valid=try site.validated();return SiteImportCandidate(id:index,name:valid.name,protocolName:valid.fileProtocol.title,session:valid,notes:[],issue:nil)}catch{return SiteImportCandidate(id:index,name:site.name,protocolName:site.fileProtocol.title,session:nil,notes:[],issue:error.localizedDescription,sourceAddress:site.identity)}
  }
  return SiteImportPlan(format:.macSCPJSON,candidates:rows)
 }
}

// WinSCP stores session strings with PuTTY-style percent escaping; UTF-8
// non-ASCII strings carry an escaped BOM. Never interpret command settings.
enum WinSCPSiteINI {
 private struct Section {let name:String;let line:Int;var values=[String:String]();var duplicates=false}
 private static let keys:Set<String>=["hostname","username","portnumber","fsprotocol","publickeyfile","localdirectory","remotedirectory","compression","timeout","pingtype","pinginterval","pingintervalsecs","pingintervalsec","proxymethod","tunnel","sftpserver","ftps","sshhostkey","ftpsecure","ftppasvmode","ftpusemlsd","ftpaccount","ftpproxylogontype","tlscertificatefile","postlogincommands","utf","sftputfbug","mintlsversion","maxtlsversion","sslsessionreuse","ftpforcepasvip2","ftplistall","ftppingtype","ftppinginterval"]
 static func text(_ data:Data)throws->String {
  let bytes=[UInt8](data.prefix(3));var value:String?
  if bytes.starts(with:[0xFF,0xFE]){value=String(data:data.dropFirst(2),encoding:.utf16LittleEndian)}
  else if bytes.starts(with:[0xFE,0xFF]){value=String(data:data.dropFirst(2),encoding:.utf16BigEndian)}
  else{value=String(data:bytes==[0xEF,0xBB,0xBF] ? data.dropFirst(3) : data,encoding:.utf8)}
  guard let value=value,!value.contains("\0") else{throw SFTPError.message("配置编码无效；请使用 UTF-8 或带 BOM 的 UTF-16 INI")};return value
 }
 private static func hex(_ byte:UInt8)->UInt8?{switch byte{case 48...57:return byte-48;case 65...70:return byte-55;case 97...102:return byte-87;default:return nil}}
 static func decode(_ raw:String)throws->String {
  let source=Array(raw.utf8);var bytes=[UInt8]();var i=0
  while i<source.count {
   if source[i]==37 {guard i+2<source.count,let high=hex(source[i+1]),let low=hex(source[i+2]) else{throw SFTPError.message("包含无效的百分号编码")};bytes.append(high*16+low);i+=3}
   else{bytes.append(source[i]);i+=1}
  }
  if bytes.starts(with:[0xEF,0xBB,0xBF]){bytes.removeFirst(3)}
  guard let value=String(bytes:bytes,encoding:.utf8) else{throw SFTPError.message("旧式 ANSI 编码无法确认，请从 WinSCP 重新导出 Unicode 配置")}
  guard !value.unicodeScalars.contains(where:{CharacterSet.controlCharacters.contains($0)}) else{throw SFTPError.message("站点字段包含控制字符")};return value
 }
 private static func integer(_ values:[String:String],_ key:String,_ fallback:Int)throws->Int {
  guard let raw=values[key] else{return fallback};guard let n=Int(raw.trimmingCharacters(in:.whitespaces)) else{throw SFTPError.message("\(key) 应为整数")};return n
 }
 private static func boolean(_ values:[String:String],_ key:String,_ fallback:Bool)throws->Bool {
  guard let raw=values[key]?.lowercased() else{return fallback}
  if ["1","true","on","yes"].contains(raw){return true};if ["0","false","off","no"].contains(raw){return false}
  throw SFTPError.message("\(key) 应为布尔值")
 }
 private static func string(_ values:[String:String],_ key:String)throws->String {let value=values[key] ?? "";guard value.utf8.count<=65536 else{throw SFTPError.message("站点字段过长：\(key)")};return try decode(value)}
 // WinSCP auto-switch enums use on=0, off=1, auto=2 (unlike booleans).
 private static func autoSwitch(_ values:[String:String],_ key:String)throws->Int{guard let raw=values[key]?.lowercased() else{return 2};if let n=Int(raw),(0...2).contains(n){return n};if let n=["on":0,"off":1,"auto":2][raw]{return n};throw SFTPError.message("\(key) 应为 on、off 或 auto")}
 private static func ftp(_ values:[String:String],notes:inout[String])throws->(FileProtocol,FTPSiteOptions){
  guard values["ftpsecure"]==nil else{throw SFTPError.message("FtpSecure 不是 WinSCP INI 加密字段，请重新导出包含 Ftps 的配置")}
  let encryption=try integer(values,"ftps",0);guard (0...3).contains(encryption) else{throw SFTPError.message("无法识别 FTP 加密方式 Ftps")}
  let proto:FileProtocol=encryption==0 ? .ftp : encryption==1 ? .ftpsImplicit : .ftpsExplicit
  guard try boolean(values,"ftppasvmode",true) else{throw SFTPError.message("此 FTP 站点使用主动模式，当前只支持被动模式")}
  guard try string(values,"ftpaccount").isEmpty else{throw SFTPError.message("此 FTP 站点需要 ACCT 账户认证，当前尚未接入")}
  guard try integer(values,"ftpproxylogontype",0)==0 else{throw SFTPError.message("此站点使用 FTP 专用代理登录，需要重新配置后迁移")}
  guard (values["postlogincommands"] ?? "").isEmpty else{throw SFTPError.message("此 FTP 站点依赖登录后命令，不能自动迁移；未执行或保存命令")}
  let utf=values["utf"] ?? values["sftputfbug"] ?? "2";guard ["1","2","on","auto"].contains(utf.lowercased()) else{throw SFTPError.message("此站点禁用或使用未知 UTF-8 文件名编码，当前不能准确迁移")}
  guard try autoSwitch(values,"ftpforcepasvip2") != 1 else{throw SFTPError.message("此站点强制使用服务器 PASV 返回地址；当前仅使用控制连接主机地址")}
  guard try autoSwitch(values,"ftplistall") != 0 else{throw SFTPError.message("此站点强制使用 LIST -a，当前不能准确迁移")}
  if proto != .ftp{
   guard try string(values,"sshhostkey").isEmpty else{throw SFTPError.message("此站点指定服务器证书指纹，当前不能迁移该固定身份校验") }
   guard try string(values,"tlscertificatefile").isEmpty else{throw SFTPError.message("此 FTPS 站点使用客户端证书，当前尚未接入")}
   let minimum=try integer(values,"mintlsversion",12),maximum=try integer(values,"maxtlsversion",13)
   guard [2,3,10,11,12].contains(minimum),maximum==13 else{throw SFTPError.message("自定义 TLS 版本范围当前不能准确迁移；本机要求 TLS 1.2 或更新")}
   guard try boolean(values,"sslsessionreuse",true) else{throw SFTPError.message("此站点禁用 TLS 会话复用，当前不能准确迁移")}
   if minimum<12{notes.append("TLS 最低版本提升到 1.2，不启用旧 SSL/TLS 版本。")}
   if encryption==2{notes.append("保留 AUTH SSL 优先顺序；加密仍要求 TLS 1.2 或更新。")}
  }else{notes.append("普通 FTP 不加密密码和文件内容。")}
  let listing=try autoSwitch(values,"ftpusemlsd"),mode:FTPListingMode=listing==0 ? .machineOnly : listing==1 ? .legacy : .automatic
  let options=FTPSiteOptions(listing:mode == .automatic ? nil : mode,timeout:try integer(values,"timeout",15),sslAuthFirst:encryption==2 ? true : nil)
  if let ping=values["ftppingtype"],ping != "0"{_ = try integer(values,"ftppingtype",0);notes.append("FTP 空闲保活未迁移；目录和传输操作各自创建已认证通道。")}
  notes.append("连接或命令响应超时后终止本次操作，可手动重试；不弹出继续等待窗口。")
  notes.append("导入后默认仅浏览和下载；需要写入时在站点明确开启非原子写入。")
  return(proto,try options.validated())
 }
 private static func usableMacPath(_ path:String)->Bool{path.hasPrefix("/") && !path.hasPrefix("//") || path.hasPrefix("~/")}
 static func read(_ data:Data)throws->SiteImportPlan {
  guard data.count<=SiteImportPlan.maximumBytes else{throw SFTPError.message("站点配置超过 4 MiB")}
  let source=try text(data),lines=source.split(separator:"\n",omittingEmptySubsequences:false)
  guard lines.count<=200000 else{throw SFTPError.message("INI 行数超过限制")}
  var sections=[Section](),current:Int?,names=Set<String>()
  for (index,raw) in lines.enumerated() {
   let line=raw.trimmingCharacters(in:.whitespacesAndNewlines)
   if line.isEmpty || line.hasPrefix(";") || line.hasPrefix("#"){continue}
   if line.hasPrefix("[") {
    guard line.hasSuffix("]"),line.count>2 else{throw SFTPError.message("INI 第 \(index+1) 行的节名称无效")}
    let name=String(line.dropFirst().dropLast())
    if name.lowercased().hasPrefix("sessions\\"),!name.dropFirst(9).contains("\\") {
     guard names.insert(name.lowercased()).inserted else{throw SFTPError.message("INI 第 \(index+1) 行包含重复的站点节")}
     sections.append(Section(name:String(name.dropFirst(9)),line:index+1));current=sections.count-1
     guard sections.count<=10001 else{throw SFTPError.message("站点数量超过限制")}
    }else{current=nil}
    continue
   }
   guard let current=current else{continue}
   guard let equals=line.firstIndex(of:"=") else{throw SFTPError.message("INI 第 \(index+1) 行缺少等号")}
   let key=line[..<equals].trimmingCharacters(in:.whitespaces).lowercased()
   guard keys.contains(key) else{continue} // Passwords, trust caches and commands never enter the model.
   var value=line[line.index(after:equals)...].trimmingCharacters(in:.whitespaces)
   if value.count>=2,value.first=="\"",value.last=="\""{value=String(value.dropFirst().dropLast())}
   if sections[current].values[key] != nil{sections[current].duplicates=true}
   sections[current].values[key]=value
  }
  var defaults=[String:String](),siteSections=[Section](),hasDefaults=false
  for section in sections {
   if (try? decode(section.name))?.lowercased()=="default settings" {
    guard !section.duplicates,!hasDefaults else{throw SFTPError.message("默认站点设置重复或包含重复字段")};hasDefaults=true;defaults=section.values
   }else{siteSections.append(section)}
  }
  guard siteSections.count<=10000 else{throw SFTPError.message("站点数量超过限制")}
  guard !siteSections.isEmpty else{throw SFTPError.message("未找到 WinSCP 站点节")}
  let rows=siteSections.enumerated().map{index,section->SiteImportCandidate in
   var name="第 \(section.line) 行的站点",protocolName="未知",notes=[String](),sourceAddress:String?
   do {
    name=try decode(section.name);guard !name.isEmpty,name.count<=512 else{throw SFTPError.message("站点名称为空或过长")}
    guard !section.duplicates else{throw SFTPError.message("站点包含重复字段，请先消除歧义")}
    let values=defaults.merging(section.values){_,new in new}
    sourceAddress=try? string(values,"hostname")
    let proto=try integer(values,"fsprotocol",1)
    protocolName=[0:"SCP",1:"SFTP（允许 SCP 回退）",2:"SFTP",5:"FTP / FTPS",6:"WebDAV",7:"S3"][proto] ?? "协议 \(proto)"
    guard proto==1 || proto==2 || proto==5 else{throw SFTPError.message("当前版本尚不支持导入此协议")}
    if proto==1{notes.append("导入后使用 SFTP，不自动回退 SCP。")}
    if let proxy=values["proxymethod"],!["0","none"].contains(proxy.lowercased()){throw SFTPError.message("此站点使用代理，需要在 Mac 上重新配置后迁移")}
    guard try !boolean(values,"tunnel",false) else{throw SFTPError.message("此站点使用 SSH 隧道，需要在 Mac 上重新配置后迁移")}
    if proto != 5{guard try string(values,"sftpserver").isEmpty else{throw SFTPError.message("自定义 SFTP 服务命令尚不能迁移")}}
    var host=try string(values,"hostname"),user=try string(values,"username")
    if let at=host.lastIndex(of:"@") {
     let embedded=String(host[..<at]);guard user.isEmpty || user==embedded else{throw SFTPError.message("HostName 和 UserName 的用户名不一致")}
     user=embedded;host=String(host[host.index(after:at)...])
    }
    guard !host.contains("/"),!host.contains("\\") else{throw SFTPError.message("主机地址格式无效")}
    var key=proto==5 ? "" : try string(values,"publickeyfile"),local=try string(values,"localdirectory")
    if !key.isEmpty && (!usableMacPath(key) || key.lowercased().hasSuffix(".ppk")){notes.append("请在 Mac 重新选择 OpenSSH 私钥（原路径：\(key)）。");key=""}
    if !local.isEmpty && !usableMacPath(local){notes.append("Windows 本地目录未映射：\(local)，将使用当前本地目录。");local=""}
    if local.hasPrefix("~/"){local=(local as NSString).expandingTildeInPath}
    let remote=try string(values,"remotedirectory")
    if proto==5{let (kind,settings)=try ftp(values,notes:&notes);protocolName=kind.title+(settings.prefersSSLAuth ? " · AUTH SSL 优先" : "");let session=try Session(name:name,host:host,user:user,port:integer(values,"portnumber",kind.defaultPort),key:"",localPath:local.isEmpty ? nil : local,remotePath:remote.isEmpty ? nil : remote,protocolKind:kind,ftpOptions:settings).validated();return SiteImportCandidate(id:index,name:name,protocolName:protocolName,session:session,notes:notes,issue:nil)}
    var options=SSHOptions();options.compression=try boolean(values,"compression",false);options.connectTimeout=try integer(values,"timeout",15)
    let ping=try integer(values,"pingtype",0);guard (0...2).contains(ping) else{throw SFTPError.message("保活类型无效")}
    if ping==0{options.keepAliveInterval=0}else{
     let minutes=try integer(values,"pinginterval",0),seconds=try integer(values,"pingintervalsecs",-1)
     let remainder=seconds<0 ? try integer(values,"pingintervalsec",30) : seconds
     guard (0...60).contains(minutes),(0...3600).contains(remainder) else{throw SFTPError.message("保活间隔超出支持范围")}
     let combined=minutes*60+remainder;options.keepAliveInterval=combined==0 ? 30 : combined
     notes.append("按原间隔使用 OpenSSH 保活探测。")
    }
    let session=try Session(name:name,host:host,user:user,port:integer(values,"portnumber",22),key:key,localPath:local.isEmpty ? nil : local,remotePath:remote.isEmpty ? nil : remote,options:options).validated()
    return SiteImportCandidate(id:index,name:name,protocolName:protocolName,session:session,notes:notes,issue:nil)
   }catch{return SiteImportCandidate(id:index,name:name,protocolName:protocolName,session:nil,notes:notes,issue:error.localizedDescription,sourceAddress:sourceAddress)}
  }
  return SiteImportPlan(format:.winSCPINI,candidates:rows)
 }
}

final class SiteImportSelection {
 let plan:SiteImportPlan;private(set) var checked=Set<Int>();private(set) var existing:[Session]
 private let byID:[Int:SiteImportCandidate];private let endpointIDs:[String:[Int]];private var existingByIdentity:[String:Session]
 init(plan:SiteImportPlan,existing:[Session]){self.plan=plan;self.existing=existing;byID=Dictionary(uniqueKeysWithValues:plan.candidates.map{($0.id,$0)});var groups=[String:[Int]]();for row in plan.candidates{if let site=row.session{groups[site.identity,default:[]].append(row.id)}};endpointIDs=groups;existingByIdentity=Dictionary(existing.map{($0.identity,$0)},uniquingKeysWith:{first,_ in first})}
 func setChecked(_ id:Int,_ value:Bool){guard let row=byID[id],row.eligible,let site=row.session else{return};if value{for other in endpointIDs[site.identity] ?? []{checked.remove(other)};checked.insert(id)}else{checked.remove(id)}}
 func selectAllEligible(){checked=[];var endpoints=Set<String>();for row in plan.candidates{if row.eligible,let site=row.session,endpoints.insert(site.identity).inserted{checked.insert(row.id)}}}
 func selectNone(){checked=[]}
 func refreshExisting(_ values:[Session]){existing=values;existingByIdentity=Dictionary(values.map{($0.identity,$0)},uniquingKeysWith:{first,_ in first})}
 func action(_ row:SiteImportCandidate)->String{guard row.eligible,let site=row.session else{return "不能导入"};return existingByIdentity[site.identity] != nil ? "更新已有" : "新增"}
 func changes(_ row:SiteImportCandidate)->[(String,String,String)] {
  guard let next=row.session,let old=existingByIdentity[next.identity] else{return []}
  var fields:[(String,String,String)]=[("协议",old.fileProtocol.title,next.fileProtocol.title),("名称",old.name,next.name),("本地目录",old.localPath ?? "",next.localPath ?? ""),("远程目录",old.remotePath ?? "",next.remotePath ?? "")]
  if next.fileProtocol == .sftp{
   let a=old.sshOptions,b=next.sshOptions
   fields += [("私钥路径",old.key,next.key),("跳板机",a.jumpHost,b.jumpHost),("连接超时",String(a.connectTimeout),String(b.connectTimeout)),("保活间隔",String(a.keepAliveInterval),String(b.keepAliveInterval)),("保活失败次数",String(a.keepAliveCount),String(b.keepAliveCount)),("压缩",a.compression ? "开启" : "关闭",b.compression ? "开启" : "关闭")]
  }else{
   let a=old.ftpSettings,b=next.ftpSettings
   fields += [("FTP 非原子写入",String(a.allowNonAtomicWrites),String(b.allowNonAtomicWrites)),("FTP 目录列表",a.listingMode.title,b.listingMode.title),("FTP 连接超时",String(a.connectTimeout),String(b.connectTimeout))]
   fields += [("FTP 认证优先",a.prefersSSLAuth ? "SSL" : "TLS",b.prefersSSLAuth ? "SSL" : "TLS"),("FTP 保留时间",String(a.preserveTime),String(b.preserveTime)),("FTP 保留权限",String(a.preservePermissions),String(b.preservePermissions))]
  }
  return fields.filter{$0.1 != $0.2}
 }
 func duplicate(_ row:SiteImportCandidate)->Bool{guard let site=row.session else{return false};return (endpointIDs[site.identity]?.count ?? 0)>1}
 func apply(to store:SiteStore)throws->Int {
  let selected=plan.candidates.filter{checked.contains($0.id)}
  guard !selected.isEmpty,selected.allSatisfy({$0.eligible}) else{throw SFTPError.message("请勾选要导入的站点")}
  let sessions=selected.compactMap(\.session)
  let previous=Dictionary(existing.map{($0.identity,$0)},uniquingKeysWith:{first,_ in first}),current=Dictionary(store.sites.map{($0.identity,$0)},uniquingKeysWith:{first,_ in first})
  for site in sessions {
   guard current[site.identity] == previous[site.identity] else{throw SFTPError.message("现有站点已改变，请刷新预览后重试")}
  }
  return try store.importSessions(sessions)
 }
}
