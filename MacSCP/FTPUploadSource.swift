import Foundation
import CryptoKit
import Darwin
final class FTPUploadSource {
 let url:URL,descriptor:Int32,size:UInt64,modified:UInt32,permissions:UInt32
 let file:FileHandle;private let original:Fingerprint
 private struct Fingerprint:Equatable {
  let device:UInt64,inode:UInt64,size:Int64,modified:Int,nanoseconds:Int,changed:Int,changeNanos:Int
  init(_ s:stat){device=UInt64(bitPattern:Int64(s.st_dev));inode=UInt64(s.st_ino);size=s.st_size;modified=s.st_mtimespec.tv_sec;nanoseconds=s.st_mtimespec.tv_nsec;changed=s.st_ctimespec.tv_sec;changeNanos=s.st_ctimespec.tv_nsec}
 }
 init(_ url:URL)throws{
  guard url.isFileURL,url.path.hasPrefix("/"),!url.path.contains("\0") else{throw SFTPError.message("FTP 上传源路径无效")}
  let fd=open(url.path,O_RDONLY|O_NOFOLLOW|O_NONBLOCK|O_CLOEXEC);guard fd>=0 else{throw SFTPError.message("无法安全打开 FTP 上传源")}
  var s=stat();guard fstat(fd,&s)==0,UInt32(s.st_mode)&UInt32(S_IFMT)==UInt32(S_IFREG),s.st_size>=0 else{Darwin.close(fd);throw SFTPError.message("FTP 上传源必须是普通文件")}
  self.url=url;descriptor=fd;file=FileHandle(fileDescriptor:fd,closeOnDealloc:false);size=UInt64(s.st_size);modified=UInt32(clamping:s.st_mtimespec.tv_sec);permissions=UInt32(s.st_mode)&0o777;original=Fingerprint(s)
 }
 deinit{Darwin.close(descriptor)}
 func check()throws{var current=stat(),path=stat();guard fstat(descriptor,&current)==0,lstat(url.path,&path)==0,UInt32(path.st_mode)&UInt32(S_IFMT)==UInt32(S_IFREG),Fingerprint(current)==original,Fingerprint(path)==original else{throw SFTPError.message("FTP 本地源在上传期间发生变化")}}
 func digest(checkpoint:(()throws->Void)?)throws->String{try check();try file.seek(toOffset:0);var hash=SHA256();while let data=try file.read(upToCount:1024*1024),!data.isEmpty{try checkpoint?();hash.update(data:data)};try check();return hash.finalize().map{String(format:"%02x",$0)}.joined()}
}
