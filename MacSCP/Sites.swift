import Foundation
enum FileProtocol:String,Codable,CaseIterable {case sftp,ftp,ftpsExplicit,ftpsImplicit
 var title:String{switch self{case .sftp:return "SFTP";case .ftp:return "FTP（不加密）";case .ftpsExplicit:return "FTPS（显式 TLS）";case .ftpsImplicit:return "FTPS（隐式 TLS）"}}
 var defaultPort:Int{self == .sftp ? 22 : self == .ftpsImplicit ? 990 : 21}
 var security:FTPConnection.Security{self == .ftp ? .plain : self == .ftpsImplicit ? .implicitTLS : .explicitTLS}
}
enum FTPListingMode:String,Codable,CaseIterable {case automatic,machineOnly,legacy
 var title:String{switch self{case .automatic:return "自动（MLSD，不支持时 LIST）";case .machineOnly:return "仅 MLSD";case .legacy:return "仅 LIST"}}
}
struct FTPSiteOptions:Codable,Equatable {
 var allowNonAtomicWrites=false;var preserveTime=false;var preservePermissions=false
 var listing:FTPListingMode?;var timeout:Int?;var sslAuthFirst:Bool?
 var listingMode:FTPListingMode{listing ?? .automatic};var connectTimeout:Int{timeout ?? 15};var prefersSSLAuth:Bool{sslAuthFirst ?? false}
 func validated()throws->FTPSiteOptions{guard (1...600).contains(connectTimeout) else{throw SFTPError.message("FTP 连接超时应为 1–600 秒")};return self}
}
struct Session:Codable,Equatable {var name:String;var host:String;var user:String;var port:Int;var key:String;var localPath:String?;var remotePath:String?;var options:SSHOptions?;var protocolKind:FileProtocol?;var ftpOptions:FTPSiteOptions?
 init(name:String,host:String,user:String,port:Int,key:String,localPath:String?=nil,remotePath:String?=nil,options:SSHOptions?=nil,protocolKind:FileProtocol?=nil,ftpOptions:FTPSiteOptions?=nil){self.name=name;self.host=host;self.user=user;self.port=port;self.key=key;self.localPath=localPath;self.remotePath=remotePath;self.options=options;self.protocolKind=protocolKind;self.ftpOptions=ftpOptions}
 var sshOptions:SSHOptions{options ?? SSHOptions()}
 var fileProtocol:FileProtocol{protocolKind ?? .sftp}
 var ftpSettings:FTPSiteOptions{ftpOptions ?? FTPSiteOptions()}
 var identity:String{let endpoint="\(user)@\(host):\(port)";return fileProtocol == .sftp ? endpoint : fileProtocol.rawValue+"://"+endpoint}
 func validated()throws->Session{var s=self;s.host=s.host.trimmingCharacters(in:.whitespacesAndNewlines);s.user=s.user.trimmingCharacters(in:.whitespacesAndNewlines);guard !s.host.isEmpty,!s.host.hasPrefix("-"),!s.host.contains(where:{$0.isWhitespace || $0.isNewline}),(1...65535).contains(s.port),!s.user.contains(where:{$0.isNewline}) else{throw SFTPError.message("请输入有效主机、用户名和端口")};if s.fileProtocol == .sftp{_ = try s.sshOptions.validated()}else{_ = try s.ftpSettings.validated();_ = try FTPConnection(host:s.host,user:s.user,password:"",port:s.port,security:s.fileProtocol.security,options:s.ftpSettings);guard s.key.isEmpty,s.options==nil else{throw SFTPError.message("FTP 站点不能包含 SSH 私钥或高级设置")}};if s.name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty{s.name=s.host};return s}
}
final class SiteStore {
 let url:URL;private(set) var sites=[Session]()
 init(url:URL,legacy:URL?=nil)throws{self.url=url;if FileManager.default.fileExists(atPath:url.path){sites=try JSONDecoder().decode([Session].self,from:Data(contentsOf:url))}else if let legacy=legacy,FileManager.default.fileExists(atPath:legacy.path){sites=[try JSONDecoder().decode(Session.self,from:Data(contentsOf:legacy))]}}
 func save(_ session:Session)throws{let s=try session.validated();var updated=sites.filter{$0.identity != s.identity};updated.insert(s,at:0);try persist(updated);sites=updated}
 func remove(_ identity:String)throws{let updated=sites.filter{$0.identity != identity};try persist(updated);sites=updated}
 func exportData()throws->Data{let encoder=JSONEncoder();encoder.outputFormatting=[.prettyPrinted,.sortedKeys];return try encoder.encode(sites)}
 func importData(_ data:Data)throws->Int{guard data.count<=4*1024*1024 else{throw SFTPError.message("站点配置超过 4 MiB")};return try importSessions(JSONDecoder().decode([Session].self,from:data))}
 func importSessions(_ imported:[Session])throws->Int{guard imported.count<=10000 else{throw SFTPError.message("站点数量超过限制")};let valid=try imported.map{try $0.validated()};let last=Dictionary(valid.enumerated().map{($0.element.identity,$0.offset)},uniquingKeysWith:{_,new in new});let updated=sites.filter{last[$0.identity]==nil}+valid.enumerated().filter{last[$0.element.identity]==$0.offset}.map(\.element);try persist(updated);sites=updated;return valid.count}
 private func persist(_ values:[Session])throws{try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true,attributes:[.posixPermissions:0o700]);let data=try JSONEncoder().encode(values);try data.write(to:url,options:.atomic);try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:url.path)}
}
