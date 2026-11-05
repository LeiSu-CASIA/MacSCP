import Foundation

// Owns one login's memory-only credentials and all clients created for it.
final class FTPLoginSession {
 private final class WeakClient {weak var value:FTPClient?;init(_ value:FTPClient){self.value=value}}
 private let lock=NSLock();private var connection:FTPConnection?;private var clients=[WeakClient]()
 private var value:RemotePaneConnectionState = .connecting
 let settings:FTPSiteOptions;private let savedPasswordUsed:Bool
 var state:RemotePaneConnectionState{lock.lock();defer{lock.unlock()};return value}
 init(connection:FTPConnection,settings:FTPSiteOptions,savedPasswordUsed:Bool=false){self.connection=connection;self.settings=settings;self.savedPasswordUsed=savedPasswordUsed}
 func makeClient(preserveUploadTime:Bool?=nil)throws->FTPClient{
  lock.lock();defer{lock.unlock()};guard let connection=connection,value == .connecting || value == .connected else{throw SFTPError.message("FTP 会话已结束，请手动重新登录")}
  let client=try FTPClient(connection,publicationPolicy:settings.allowNonAtomicWrites ? .allowNonAtomic : .requireAtomic,preserveUploadTime:preserveUploadTime ?? settings.preserveTime,preserveUploadPermissions:settings.preservePermissions)
  clients.removeAll{$0.value==nil};clients.append(WeakClient(client));return client
 }
 func authenticate()throws->String{
  do{let client=try makeClient();defer{client.close()};let path=try client.canonical(".");_ = try client.list(path,maximumEntries:100000)
   lock.lock();defer{lock.unlock()};guard value == .connecting,connection != nil else{throw SFTPError.message("FTP 登录已取消")};value = .connected;return path
  }catch{lock.lock();if value == .connecting{let rejected=savedPasswordUsed && (error as? FTPCurlFailure)?.code==67;value = .failed(rejected ? "已保存密码未通过认证。请手动重新连接并输入新密码；不会自动反复尝试。" : error.localizedDescription);connection=nil};lock.unlock();throw error}
 }
 func cancel(){lock.lock();value = .cancelled;connection=nil;let active=clients.compactMap{$0.value};clients=[];lock.unlock();for client in active{client.interrupt()}}
 deinit{cancel()}
}
final class FTPLoginRegistry {
 private let lock=NSLock();private var logins=[String:(String,FTPLoginSession)]()
 func insert(_ login:FTPLoginSession,site:Session,token:String){lock.lock();logins[token]=(site.identity,login);lock.unlock()}
 func client(site:Session,token:String,preserveUploadTime:Bool?=nil)throws->FTPClient{lock.lock();let item=logins[token];lock.unlock();guard let (identity,login)=item,identity==site.identity,login.state == .connected else{throw SFTPError.message("FTP 会话已关闭或尚未连接")};return try login.makeClient(preserveUploadTime:preserveUploadTime)}
 func remove(_ token:String){lock.lock();let item=logins.removeValue(forKey:token);lock.unlock();item?.1.cancel()}
}
