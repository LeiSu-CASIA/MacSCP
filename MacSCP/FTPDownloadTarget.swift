import Foundation
import Darwin

private struct FTPDestinationIdentity:Equatable {
 let device:UInt64,inode:UInt64,size:Int64,mode:UInt32,seconds:Int,nanoseconds:Int
 init(_ value:stat){device=UInt64(bitPattern:Int64(value.st_dev));inode=UInt64(value.st_ino);size=value.st_size;mode=UInt32(value.st_mode);seconds=value.st_mtimespec.tv_sec;nanoseconds=value.st_mtimespec.tv_nsec}
}
final class FTPDownloadTarget {
 let file:FileHandle;let size:UInt64
 private let directoryFD:Int32,fileFD:Int32,parent:String,originalParent:String,destination:String,temporary:String,retainPartial:Bool,startingTarget:FTPDestinationIdentity?
 private var published=false
 private static func canonicalDirectory(_ path:String)throws->String{guard let resolved=realpath(path,nil) else{throw NSError(domain:NSPOSIXErrorDomain,code:Int(errno))};defer{free(resolved)};return String(cString:resolved)}
 private static func error(_ text:String)->NSError{let code=errno;return NSError(domain:NSPOSIXErrorDomain,code:Int(code),userInfo:[NSLocalizedDescriptionKey:text+"："+String(cString:strerror(code))])}
 private static func entry(_ fd:Int32,_ name:String)throws->FTPDestinationIdentity?{var value=stat();if fstatat(fd,name,&value,AT_SYMLINK_NOFOLLOW)==0{return FTPDestinationIdentity(value)};if errno==ENOENT{return nil};throw error("无法读取下载目标")}
 init(destination:URL,temporary:URL,overwrite:Bool,resume:Bool,retainPartial:Bool)throws{
  guard destination.isFileURL,temporary.isFileURL,!destination.path.contains("\0"),!temporary.path.contains("\0"),!["/",".","..",""] .contains(destination.lastPathComponent),temporary.lastPathComponent.hasPrefix(".macscp-resume-"),UUID(uuidString:String(temporary.lastPathComponent.dropFirst(".macscp-resume-".count))) != nil else{throw SFTPError.message("FTP 下载目标或暂存路径无效")}
  let parent=try Self.canonicalDirectory(destination.deletingLastPathComponent().path),tempParent=try Self.canonicalDirectory(temporary.deletingLastPathComponent().path)
  guard parent==tempParent else{throw SFTPError.message("FTP 下载暂存与目标必须位于同一目录")}
  let dir=open(parent,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC);guard dir>=0 else{throw Self.error("无法打开下载目录")}
  var keepDirectory=false;defer{if !keepDirectory{Darwin.close(dir)}}
  let prior=try Self.entry(dir,destination.lastPathComponent)
  if let prior=prior{guard prior.mode&UInt32(S_IFMT)==UInt32(S_IFREG),overwrite else{throw SFTPError.message("本地目标已存在或不是普通文件")}}
  var fd=openat(dir,temporary.lastPathComponent,O_RDWR|O_CREAT|O_EXCL|O_NOFOLLOW|O_CLOEXEC|O_NONBLOCK,mode_t(0o600))
  let created=fd>=0
  if fd<0,errno==EEXIST,resume{fd=openat(dir,temporary.lastPathComponent,O_RDWR|O_NOFOLLOW|O_CLOEXEC|O_NONBLOCK)}
  guard fd>=0 else{throw Self.error("无法打开下载暂存")}
  var keepFile=false;defer{if !keepFile{if created{var a=stat(),b=stat();if fstat(fd,&a)==0,fstatat(dir,temporary.lastPathComponent,&b,AT_SYMLINK_NOFOLLOW)==0,a.st_dev==b.st_dev,a.st_ino==b.st_ino{_ = unlinkat(dir,temporary.lastPathComponent,0)}};Darwin.close(fd)}}
  if created{guard fchmod(fd,mode_t(0o600))==0 else{throw Self.error("无法限制下载暂存权限")}}
  var info=stat();guard fstat(fd,&info)==0,UInt32(info.st_mode)&UInt32(S_IFMT)==UInt32(S_IFREG),info.st_uid==geteuid(),info.st_nlink==1,info.st_mode&0o777==0o600,info.st_size>=0 else{throw SFTPError.message("FTP 暂存必须为当前用户独占的 0600 普通文件")}
  self.directoryFD=dir;self.fileFD=fd;self.parent=parent;self.originalParent=destination.deletingLastPathComponent().path;self.destination=destination.lastPathComponent;self.temporary=temporary.lastPathComponent;self.startingTarget=prior;self.retainPartial=retainPartial;size=UInt64(info.st_size);file=FileHandle(fileDescriptor:fd,closeOnDealloc:false);keepDirectory=true;keepFile=true
 }
 deinit{if !published && !retainPartial{removeOwnedTemporary()};Darwin.close(fileFD);Darwin.close(directoryFD)}
 private func ownsTemporary()->Bool{var descriptor=stat(),entry=stat();guard fstat(fileFD,&descriptor)==0,fstatat(directoryFD,temporary,&entry,AT_SYMLINK_NOFOLLOW)==0 else{return false};return descriptor.st_dev==entry.st_dev && descriptor.st_ino==entry.st_ino && UInt32(entry.st_mode)&UInt32(S_IFMT)==UInt32(S_IFREG) && entry.st_nlink==1}
 private func removeOwnedTemporary(){if ownsTemporary(){_ = unlinkat(directoryFD,temporary,0)}}
 func publish(expectedSize:UInt64,modified:UInt32,permissions:UInt32?=nil,preserveExistingPermissions:Bool=true)throws{
  var opened=stat(),current=stat(),content=stat()
  guard (try? Self.canonicalDirectory(originalParent))==parent,fstat(directoryFD,&opened)==0,lstat(parent,&current)==0,opened.st_dev==current.st_dev,opened.st_ino==current.st_ino,UInt32(current.st_mode)&UInt32(S_IFMT)==UInt32(S_IFDIR),ownsTemporary() else{throw SFTPError.message("下载目录或暂存被替换，目标未发布")}
  guard fstat(fileFD,&content)==0,content.st_size>=0,UInt64(content.st_size)==expectedSize else{throw SFTPError.message("下载暂存大小变化，目标未发布")}
  guard try Self.entry(directoryFD,destination)==startingTarget else{throw SFTPError.message("下载期间本地目标发生变化，已保留当前目标")}
  let desired=preserveExistingPermissions ? (startingTarget?.mode ?? permissions ?? 0o600) : (permissions ?? 0o600)
  guard fchmod(fileFD,mode_t(desired&0o777))==0 else{throw Self.error("无法设置下载权限")}
  let times=[timeval(tv_sec:Int(modified),tv_usec:0),timeval(tv_sec:Int(modified),tv_usec:0)]
  guard times.withUnsafeBufferPointer({futimes(fileFD,$0.baseAddress)})==0,fsync(fileFD)==0 else{throw Self.error("无法完成下载暂存")}
  let result=startingTarget==nil ? renameatx_np(directoryFD,temporary,directoryFD,destination,UInt32(RENAME_EXCL)) : renameat(directoryFD,temporary,directoryFD,destination)
  guard result==0 else{throw Self.error("无法发布下载目标")};published=true;_ = fsync(directoryFD)
 }
}
