import Foundation
import Darwin

// OpenSSH's -E client log is separate from server banners on stderr. It contains
// client diagnostics, never the askpass answer, and is private and short-lived.
final class SSHAuthenticationLog {
 let url:URL;private let directory:URL,file:FileHandle,device:dev_t,inode:ino_t
 private var pending=Data();private(set) var passwordAuthenticated=false
 init(root:URL=FileManager.default.temporaryDirectory)throws{
  let directory=root.appendingPathComponent("macscp-sshlog-"+UUID().uuidString);try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700]);let url=directory.appendingPathComponent("client.log")
  let fd=open(url.path,O_RDWR|O_CREAT|O_EXCL|O_NOFOLLOW|O_CLOEXEC,0o600);guard fd>=0 else{try? FileManager.default.removeItem(at:directory);throw SFTPError.message("无法创建私有 SSH 客户端诊断")}
  var info=stat();guard fstat(fd,&info)==0,info.st_nlink==1,info.st_uid==geteuid() else{Darwin.close(fd);try? FileManager.default.removeItem(at:directory);throw SFTPError.message("SSH 客户端诊断文件无效")}
  self.directory=directory;self.url=url;file=FileHandle(fileDescriptor:fd,closeOnDealloc:true);device=info.st_dev;inode=info.st_ino
 }
 func drain()->String{
  var result=Data()
  do{for _ in 0..<16{guard let data=try file.read(upToCount:65536),!data.isEmpty else{break};result.append(data);pending.append(data)
   while let end=pending.firstIndex(of:10){let line=String(decoding:pending[..<end],as:UTF8.self).trimmingCharacters(in:.whitespacesAndNewlines);pending.removeSubrange(...end);if line.hasPrefix("Authenticated to "),line.contains(" using \""){passwordAuthenticated=line.hasSuffix(" using \"password\".")}}
   if pending.count>65536{pending.removeAll();passwordAuthenticated=false}
  }}catch{passwordAuthenticated=false}
  return String(decoding:result,as:UTF8.self)
 }
 func unlink(){var info=stat();if lstat(url.path,&info)==0,info.st_dev==device,info.st_ino==inode{_ = Darwin.unlink(url.path)};_ = rmdir(directory.path)}
 deinit{try? file.close();unlink()}
}
