import Foundation
import Darwin

@_silgen_name("proc_pidpath") private func credentialProcessPath(_ pid:Int32,_ buffer:UnsafeMutableRawPointer,_ size:UInt32)->Int32

private enum CredentialChannelError:Error {case invalid,io}
private struct CredentialChannelRequest:Codable {let token:String,action:String,prompt:String;let hint:String?;let value:String?}
struct SSHCredentialReply:Codable {let eligible:Bool;let answer:String?;let rejectedSavedPassword:Bool}
private enum CredentialWire {
 static let limit=65536
 static func prepare(_ fd:Int32){let flags=fcntl(fd,F_GETFL);if flags>=0{_ = fcntl(fd,F_SETFL,flags & ~O_NONBLOCK)};var flag:Int32=1;_ = setsockopt(fd,SOL_SOCKET,SO_NOSIGPIPE,&flag,socklen_t(MemoryLayout.size(ofValue:flag)));var timeout=timeval(tv_sec:2,tv_usec:0);_ = setsockopt(fd,SOL_SOCKET,SO_RCVTIMEO,&timeout,socklen_t(MemoryLayout.size(ofValue:timeout)));_ = setsockopt(fd,SOL_SOCKET,SO_SNDTIMEO,&timeout,socklen_t(MemoryLayout.size(ofValue:timeout)));_ = fcntl(fd,F_SETFD,FD_CLOEXEC)}
 static func address(_ path:String)throws->sockaddr_un{var address=sockaddr_un();address.sun_family=sa_family_t(AF_UNIX);address.sun_len=UInt8(MemoryLayout<sockaddr_un>.size);let bytes=Array(path.utf8);guard !bytes.contains(0),bytes.count<MemoryLayout.size(ofValue:address.sun_path) else{throw CredentialChannelError.invalid};withUnsafeMutableBytes(of:&address.sun_path){raw in raw.copyBytes(from:bytes);raw[bytes.count]=0};return address}
 static func peerPID(_ fd:Int32)->pid_t?{var pid:pid_t=0,size=socklen_t(MemoryLayout<pid_t>.size);guard getsockopt(fd,SOL_LOCAL,LOCAL_PEERPID,&pid,&size)==0,pid>0 else{return nil};return pid}
 static func parentPID(_ pid:pid_t)->pid_t?{var process=kinfo_proc(),size=MemoryLayout<kinfo_proc>.size;var mib:[Int32]=[CTL_KERN,KERN_PROC,KERN_PROC_PID,pid];let result=mib.withUnsafeMutableBufferPointer{sysctl($0.baseAddress,u_int($0.count),&process,&size,nil,0)};return result==0 && size>0 ? process.kp_eproc.e_ppid : nil}
 static func executable(_ pid:pid_t)->String?{var bytes=[CChar](repeating:0,count:4096);let count=bytes.withUnsafeMutableBytes{credentialProcessPath(pid,$0.baseAddress!,UInt32($0.count))};guard count>0,count<4096 else{return nil};return URL(fileURLWithPath:String(cString:bytes)).resolvingSymlinksInPath().path}
 static func peerIsOwner(_ fd:Int32)->Bool{var uid:uid_t=0,gid:gid_t=0;return getpeereid(fd,&uid,&gid)==0 && uid==geteuid()}
 static func write(_ data:Data,to fd:Int32)throws{try data.withUnsafeBytes{(raw:UnsafeRawBufferPointer) in var offset=0;while offset<data.count{let n=Darwin.send(fd,raw.baseAddress!.advanced(by:offset),data.count-offset,0);if n<0 && errno==EINTR{continue};guard n>0 else{throw CredentialChannelError.io};offset+=n}}}
 static func read(_ count:Int,from fd:Int32)throws->Data{guard count>0,count<=limit else{throw CredentialChannelError.invalid};var data=Data(count:count);try data.withUnsafeMutableBytes{(raw:UnsafeMutableRawBufferPointer) in var offset=0;while offset<count{let n=Darwin.recv(fd,raw.baseAddress!.advanced(by:offset),count-offset,0);if n<0 && errno==EINTR{continue};guard n>0 else{throw CredentialChannelError.io};offset+=n}};return data}
 static func send<T:Encodable>(_ value:T,to fd:Int32)throws{let data=try JSONEncoder().encode(value);guard !data.isEmpty,data.count<=limit else{throw CredentialChannelError.invalid};var size=UInt32(data.count).bigEndian;try write(Data(bytes:&size,count:4),to:fd);try write(data,to:fd)}
 static func receive<T:Decodable>(_ type:T.Type,from fd:Int32)throws->T{let header=try read(4,from:fd);let count=header.reduce(UInt32(0)){($0<<8)|UInt32($1)};guard count>0,count<=limit else{throw CredentialChannelError.invalid};return try JSONDecoder().decode(type,from:read(Int(count),from:fd))}
 static func secretIsValid(_ value:String)->Bool{value.utf8.count<=4096 && !value.unicodeScalars.contains{[0,10,13].contains($0.value)}}
}

struct SSHValidatedPassword:CustomStringConvertible,CustomDebugStringConvertible {let value:String;let wasSaved:Bool;var description:String{"<validated SSH password>"};var debugDescription:String{description}}

// Only memory crosses this private, bounded, per-login channel. The authentication
// helper never reads the keychain and the password never enters argv or env.
final class SSHPasswordBroker {
 let path:String,token:String;let ownerPID:pid_t=getpid();private let directory:URL,source:DispatchSourceRead,fd:Int32
 private let user:String,host:String,lock=NSCondition();private var expectedParent:pid_t?,expectedExecutable:String?;private var stopped=false,servedSaved=false,awaitingSubmission=false
 private var saved:String?,candidate:String?;private var candidateWasSaved=false
 init(user:String,host:String,password:String?)throws{
  guard !user.isEmpty,!user.unicodeScalars.contains(where:{CharacterSet.controlCharacters.contains($0)}),!host.isEmpty,!host.unicodeScalars.contains(where:{CharacterSet.controlCharacters.contains($0)}),password.map(CredentialWire.secretIsValid) ?? true else{throw CredentialChannelError.invalid}
  let directory=URL(fileURLWithPath:"/tmp").appendingPathComponent("macscp-pass-"+UUID().uuidString);try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
  let path=directory.appendingPathComponent("s").path,fd=socket(AF_UNIX,SOCK_STREAM,0);guard fd>=0 else{try? FileManager.default.removeItem(at:directory);throw CredentialChannelError.io}
  do{var address=try CredentialWire.address(path);let result=withUnsafePointer(to:&address){$0.withMemoryRebound(to:sockaddr.self,capacity:1){Darwin.bind(fd,$0,socklen_t(MemoryLayout<sockaddr_un>.size))}};guard result==0,listen(fd,8)==0,chmod(path,0o600)==0 else{throw CredentialChannelError.io};CredentialWire.prepare(fd);guard fcntl(fd,F_SETFL,O_NONBLOCK)==0 else{throw CredentialChannelError.io}}
  catch{Darwin.close(fd);try? FileManager.default.removeItem(at:directory);throw error}
  self.directory=directory;self.path=path;self.fd=fd;token=UUID().uuidString+UUID().uuidString;self.user=user;self.host=host;self.saved=password
  source=DispatchSource.makeReadSource(fileDescriptor:fd,queue:DispatchQueue(label:"MacSCP.password-channel."+UUID().uuidString));source.setEventHandler{[weak self] in self?.acceptRequests()};source.setCancelHandler{Darwin.close(fd)};source.resume()
 }
 static func matches(prompt:String,hint:String?,user:String,host:String)->Bool{
  guard hint==nil || hint=="",!AskpassPrompt(text:prompt,hint:hint).confirmation else{return false}
  let text=prompt.trimmingCharacters(in:.whitespacesAndNewlines),prefix=user+"@",suffix="'s password:"
  guard text.hasPrefix(prefix),text.hasSuffix(suffix) else{return false};let destination=String(text.dropFirst(prefix.count).dropLast(suffix.count));let plain=host.hasPrefix("[") && host.hasSuffix("]") ? String(host.dropFirst().dropLast()) : host
  return destination.caseInsensitiveCompare(host) == .orderedSame || destination.caseInsensitiveCompare(plain) == .orderedSame
 }
 func authorize(parent:pid_t,executable:String){lock.lock();expectedParent=parent;expectedExecutable=URL(fileURLWithPath:executable).resolvingSymlinksInPath().path;lock.broadcast();lock.unlock()}
 private func authorized(_ client:Int32)->Bool{lock.lock();let deadline=Date().addingTimeInterval(1);while !stopped,expectedParent==nil,Date()<deadline{_ = lock.wait(until:deadline)};let parent=expectedParent,executable=expectedExecutable,active = !stopped;lock.unlock();guard active,let parent=parent,let executable=executable,let pid=CredentialWire.peerPID(client) else{return false};let actualParent=CredentialWire.parentPID(pid),actualExecutable=CredentialWire.executable(pid);return actualParent==parent && actualExecutable==executable}
 private func response(_ request:CredentialChannelRequest)->SSHCredentialReply{
  lock.lock();defer{lock.unlock()};guard !stopped,request.token==token,Self.matches(prompt:request.prompt,hint:request.hint,user:user,host:host) else{return SSHCredentialReply(eligible:false,answer:nil,rejectedSavedPassword:false)}
  if request.action=="lookup"{candidate=nil;candidateWasSaved=false;awaitingSubmission=true;if let value=saved,!servedSaved{saved=nil;servedSaved=true;awaitingSubmission=false;candidate=value;candidateWasSaved=true;return SSHCredentialReply(eligible:true,answer:value,rejectedSavedPassword:false)};return SSHCredentialReply(eligible:true,answer:nil,rejectedSavedPassword:servedSaved)}
  if request.action=="submit",awaitingSubmission,let value=request.value,CredentialWire.secretIsValid(value){candidate=value;candidateWasSaved=false;awaitingSubmission=false;return SSHCredentialReply(eligible:true,answer:nil,rejectedSavedPassword:servedSaved)}
  return SSHCredentialReply(eligible:false,answer:nil,rejectedSavedPassword:false)
 }
 private func acceptRequests(){for _ in 0..<32{let client=accept(fd,nil,nil);guard client>=0 else{return};CredentialWire.prepare(client);defer{Darwin.close(client)};guard CredentialWire.peerIsOwner(client),authorized(client) else{continue};do{let request=try CredentialWire.receive(CredentialChannelRequest.self,from:client);try CredentialWire.send(response(request),to:client)}catch{continue}}}
 func takeValidatedPassword()->SSHValidatedPassword?{lock.lock();defer{lock.unlock()};guard !stopped,let value=candidate else{return nil};let result=SSHValidatedPassword(value:value,wasSaved:candidateWasSaved);candidate=nil;saved=nil;awaitingSubmission=false;candidateWasSaved=false;return result}
 func forget(){lock.lock();saved=nil;candidate=nil;awaitingSubmission=false;lock.unlock()}
 func stop(){lock.lock();guard !stopped else{lock.unlock();return};stopped=true;lock.broadcast();saved=nil;candidate=nil;awaitingSubmission=false;lock.unlock();source.cancel();try? FileManager.default.removeItem(at:directory)}
 deinit{stop()}
}

enum SSHCredentialClient {
 private static func request(_ action:String,prompt:String,hint:String?,value:String?,environment:[String:String])->SSHCredentialReply?{
  guard let path=environment["MACSCP_AUTH_SOCKET"],let token=environment["MACSCP_AUTH_TOKEN"],let ownerText=environment["MACSCP_AUTH_OWNER_PID"],let owner=Int32(ownerText),owner>0,prompt.utf8.count<=32768 else{return nil};let fd=socket(AF_UNIX,SOCK_STREAM,0);guard fd>=0 else{return nil};defer{Darwin.close(fd)};CredentialWire.prepare(fd)
  do{var address=try CredentialWire.address(path);let result=withUnsafePointer(to:&address){$0.withMemoryRebound(to:sockaddr.self,capacity:1){Darwin.connect(fd,$0,socklen_t(MemoryLayout<sockaddr_un>.size))}};guard result==0,CredentialWire.peerIsOwner(fd),CredentialWire.peerPID(fd)==owner else{return nil};try CredentialWire.send(CredentialChannelRequest(token:token,action:action,prompt:prompt,hint:hint,value:value),to:fd);return try CredentialWire.receive(SSHCredentialReply.self,from:fd)}catch{return nil}
 }
 static func lookup(prompt:String,hint:String?,environment:[String:String])->SSHCredentialReply?{request("lookup",prompt:prompt,hint:hint,value:nil,environment:environment)}
 static func submitted(_ value:String,prompt:String,hint:String?,environment:[String:String]){guard CredentialWire.secretIsValid(value) else{return};_ = request("submit",prompt:prompt,hint:hint,value:value,environment:environment)}
}
