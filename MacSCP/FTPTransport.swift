import Foundation
import Darwin

private typealias FTPWriteCallback=@convention(c)(UnsafePointer<UInt8>?,Int,UnsafeMutableRawPointer?)->Int
private typealias FTPProgressCallback=@convention(c)(Int64,Int64,Int64,Int64,UnsafeMutableRawPointer?)->Int32
@_silgen_name("macscp_ftp_new") private func ftpNew()->UnsafeMutableRawPointer?
@_silgen_name("macscp_ftp_free") private func ftpFree(_ handle:UnsafeMutableRawPointer)
@_silgen_name("macscp_ftp_error") private func ftpError(_ code:Int32)->UnsafePointer<CChar>?
@_silgen_name("macscp_ftp_request") private func ftpRequest(_ handle:UnsafeMutableRawPointer,_ url:UnsafePointer<CChar>,_ user:UnsafePointer<CChar>,_ password:UnsafePointer<CChar>,_ tls:Int32,_ timeout:Int32,_ sslAuthFirst:Int32,_ operation:Int32,_ offset:Int64,_ sourceFD:Int32,_ upload:UnsafePointer<CChar>,_ commands:UnsafePointer<CChar>,_ ca:UnsafePointer<CChar>,_ opaque:UnsafeMutableRawPointer,_ write:FTPWriteCallback,_ progress:FTPProgressCallback,_ reply:UnsafeMutablePointer<Int64>,_ entry:UnsafeMutablePointer<UnsafePointer<CChar>?>,_ length:UnsafeMutablePointer<Int64>,_ modified:UnsafeMutablePointer<Int64>)->Int32

struct FTPConnection:CustomStringConvertible,CustomDebugStringConvertible {
 enum Security:String{case plain,explicitTLS,implicitTLS}
 let host:String,user:String,port:Int,security:Security,caCertificate:URL?,options:FTPSiteOptions
 fileprivate let password:String
 init(host:String,user:String,password:String,port:Int?=nil,security:Security = .explicitTLS,caCertificate:URL?=nil,options:FTPSiteOptions=FTPSiteOptions())throws{
  _ = try options.validated()
  var host=host.trimmingCharacters(in:.whitespacesAndNewlines);if host.hasPrefix("["),host.hasSuffix("]"){host=String(host.dropFirst().dropLast())}
  guard !host.isEmpty,!host.contains(where:{$0.isWhitespace || "/\\?#@%\"".contains($0)}),!host.unicodeScalars.contains(where:{CharacterSet.controlCharacters.contains($0)}),![user,password].contains(where:{$0.unicodeScalars.contains(where:{[0,10,13].contains($0.value)})}) else{throw SFTPError.message("无效的 FTP 主机或认证字段")}
  if host.contains(":"){var address=in6_addr();guard host.withCString({inet_pton(AF_INET6,$0,&address)})==1 else{throw SFTPError.message("无效的 IPv6 主机")}}
  let port=port ?? (security == .implicitTLS ? 990 : 21);guard (1...65535).contains(port) else{throw SFTPError.message("无效的 FTP 端口")}
  if let ca=caCertificate{guard ca.isFileURL,ca.path.hasPrefix("/"),!ca.path.contains("\0") else{throw SFTPError.message("证书路径无效")}}
  self.host=host;self.user=user;self.password=password;self.port=port;self.security=security;self.caCertificate=caCertificate;self.options=options
 }
 var description:String{"\(security.rawValue)://\(host):\(port)（FTP 凭据已隐藏）"}
 var debugDescription:String{description}
 func url(path:String,directory:Bool)throws->String{
  let path=try FTPPath.absolute(path)
  let safe=Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~/".utf8)
  let encoded=path.dropFirst().utf8.map{safe.contains($0) ? String(UnicodeScalar($0)) : String(format:"%%%02X",$0)}.joined()
  let host=self.host.contains(":") ? "[\(self.host)]" : self.host
  return (security == .implicitTLS ? "ftps" : "ftp")+"://\(host):\(port)/%2F"+encoded+(directory && !encoded.hasSuffix("/") ? "/" : "")
 }
 fileprivate var loginURL:String{(security == .implicitTLS ? "ftps" : "ftp")+"://"+(host.contains(":") ? "[\(host)]" : host)+":\(port)/"}
}
enum FTPPath {
 static func absolute(_ value:String)throws->String{
  guard value.hasPrefix("/"),!value.unicodeScalars.contains(where:{[0,10,13].contains($0.value)}) else{throw SFTPError.message("FTP 需要不含换行或空字符的绝对路径")}
  var parts=[String]();for part in value.split(separator:"/"){if part=="."{continue};if part==".."{guard !parts.isEmpty else{throw SFTPError.message("FTP 路径超出根目录")};parts.removeLast()}else{parts.append(String(part))}};return "/"+parts.joined(separator:"/")
 }
}
enum FTPCommand {
 case makeDirectory(String),removeFile(String),removeDirectory(String),rename(String,String),setModified(String,UInt32),setPermissions(String,UInt32)
 func lines()throws->[String]{switch self{case .setModified(let p,let seconds):let formatter=DateFormatter();formatter.locale=Locale(identifier:"en_US_POSIX");formatter.timeZone=TimeZone(secondsFromGMT:0);formatter.dateFormat="yyyyMMddHHmmss";return ["MFMT "+formatter.string(from:Date(timeIntervalSince1970:Double(seconds)))+" "+(try FTPPath.absolute(p))];case .setPermissions(let p,let mode):guard mode<=0o7777 else{throw SFTPError.message("FTP 权限参数无效")};return ["SITE CHMOD "+String(mode,radix:8)+" "+(try FTPPath.absolute(p))];case .makeDirectory(let p):return ["MKD "+(try FTPPath.absolute(p))];case .removeFile(let p):return ["DELE "+(try FTPPath.absolute(p))];case .removeDirectory(let p):return ["RMD "+(try FTPPath.absolute(p))];case .rename(let a,let b):return ["RNFR "+(try FTPPath.absolute(a)),"RNTO "+(try FTPPath.absolute(b))]}}
}
enum FTPRequest {case entryDirectory,machineList(String),legacyList(String),retrieve(String),retrieveRange(String,Int64),metadata(String),storeTemporary(String,URL),storeResumable(String,URL,Int64,Int32),commands([FTPCommand])}
struct FTPReply {let data:Data,code:Int,entryDirectory:String?,length:Int64?,modified:Int64?}
struct FTPCurlFailure:LocalizedError {
 let code:Int32,reply:Int
 var errorDescription:String?{let reason=ftpError(code).map{String(cString:$0)} ?? "FTP 传输失败";return "FTP 错误 \(code) / 响应 \(reply)："+reason}
 var unsupportedListing:Bool{[500,501,502,504].contains(reply)}
}
private final class FTPRequestContext {
 let owner:FTPCurlTransport,maximum:UInt64,sink:((Data)throws->Void)?
 var data=Data(),received:UInt64=0,error:Error?
 init(owner:FTPCurlTransport,maximum:UInt64,sink:((Data)throws->Void)?){self.owner=owner;self.maximum=maximum;self.sink=sink}
 func write(_ pointer:UnsafePointer<UInt8>?,_ count:Int)->Int{
  guard error==nil,count>=0,let pointer=pointer else{return count==0 ? 0 : 0}
  do{try owner.check();let sum=received.addingReportingOverflow(UInt64(count));guard !sum.overflow,sum.partialValue<=maximum else{throw SFTPError.message("FTP 返回内容超过读取上限")};let chunk=Data(bytes:pointer,count:count);if let sink=sink{try sink(chunk)}else{data.append(chunk)};received=sum.partialValue;return count}catch{self.error=error;return 0}
 }
 func progress(_ dt:Int64,_ dn:Int64,_ ut:Int64,_ un:Int64)->Int32{do{try owner.check();owner.progress?(UInt64(max(0,dn)),UInt64(max(0,un)));return 0}catch{self.error=error;return 1}}
}
final class FTPCurlTransport {
 let connection:FTPConnection;private let handle:UnsafeMutableRawPointer,lock=NSLock();private var closed=false,busy=false
 var checkpoint:(()throws->Void)?,progress:((UInt64,UInt64)->Void)?
 init(_ connection:FTPConnection)throws{self.connection=connection;guard let handle=ftpNew() else{throw SFTPError.message("无法初始化 FTP 引擎")};self.handle=handle}
 deinit{ftpFree(handle)}
 func interrupt(){lock.lock();closed=true;lock.unlock()}
 func close(){interrupt()}
 fileprivate func check()throws{lock.lock();let stopped=closed;lock.unlock();guard !stopped else{throw SFTPError.message("FTP 操作已取消")};try checkpoint?()}
 func perform(_ request:FTPRequest,maximumBytes:UInt64=16*1024*1024,sink:((Data)throws->Void)?=nil)throws->FTPReply{
  try check();lock.lock();guard !busy,!closed else{lock.unlock();throw SFTPError.message("FTP 客户端已关闭或正在执行其他操作")};busy=true;lock.unlock();defer{lock.lock();busy=false;lock.unlock()}
  let url:String,operation:Int32,upload:String,commands:String;var offset:Int64=0;var sourceFD:Int32 = -1
  switch request{
  case .entryDirectory:url=connection.loginURL;operation=3;upload="";commands=""
  case .machineList(let p):url=try connection.url(path:p,directory:true);operation=1;upload="";commands=""
  case .legacyList(let p):url=try connection.url(path:p,directory:true);operation=2;upload="";commands=""
  case .retrieve(let p):url=try connection.url(path:p,directory:false);operation=0;upload="";commands=""
  case .retrieveRange(let p,let start):guard start>=0 else{throw SFTPError.message("FTP 续传偏移无效")};url=try connection.url(path:p,directory:false);operation=7;offset=start;upload="";commands=""
  case .metadata(let p):url=try connection.url(path:p,directory:false);operation=6;upload="";commands=""
  case .storeTemporary(let p,let source):guard source.isFileURL,source.path.hasPrefix("/"),!source.path.contains("\0") else{throw SFTPError.message("上传源必须为本地普通文件")};url=try connection.url(path:p,directory:false);operation=4;upload=source.path;commands=""
  case .storeResumable(let p,let source,let start,let fd):guard start>=0,fd>=0 else{throw SFTPError.message("FTP 上传续传参数无效")};url=try connection.url(path:p,directory:false);operation=8;upload=source.path;offset=start;sourceFD=fd;commands=""
  case .commands(let values):guard !values.isEmpty else{throw SFTPError.message("缺少 FTP 文件操作")};url=connection.loginURL;operation=5;upload="";commands=try values.flatMap{try $0.lines()}.joined(separator:"\n")
  }
  let strings=[url,connection.user,connection.password,upload,commands,connection.caCertificate?.path ?? ""].map{strdup($0)};defer{for string in strings{free(string)}}
  guard strings.allSatisfy({$0 != nil}) else{throw SFTPError.message("FTP 内存分配失败")}
  let opaque=Unmanaged.passRetained(FTPRequestContext(owner:self,maximum:maximumBytes,sink:sink))
  // A single retained context backs both callbacks, including callback errors.
  let used=opaque.takeUnretainedValue();defer{opaque.release()}
  var reply:Int64=0,length:Int64 = -1,modified:Int64 = -1;var entry:UnsafePointer<CChar>?
  let code=ftpRequest(handle,strings[0]!,strings[1]!,strings[2]!,connection.security == .plain ? 0 : 1,Int32(connection.options.connectTimeout),connection.options.prefersSSLAuth ? 1 : 0,operation,offset,sourceFD,strings[3]!,strings[4]!,strings[5]!,opaque.toOpaque(),{bytes,count,raw in guard let raw=raw else{return 0};return Unmanaged<FTPRequestContext>.fromOpaque(raw).takeUnretainedValue().write(bytes,count)},{dt,dn,ut,un,raw in guard let raw=raw else{return 1};return Unmanaged<FTPRequestContext>.fromOpaque(raw).takeUnretainedValue().progress(dt,dn,ut,un)},&reply,&entry,&length,&modified)
  if let error=used.error{throw error};try check();guard code==0 else{throw FTPCurlFailure(code:code,reply:Int(reply))}
  return FTPReply(data:used.data,code:Int(reply),entryDirectory:entry.flatMap{String(validatingUTF8:$0)},length:length>=0 ? length : nil,modified:modified>=0 ? modified : nil)
 }
}
