import Foundation
final class FTPMemoryPublication {
 var files=[String:FTPRemoteVersion](),networkDown=false,failBefore=false,failAfter=false,failCleanup=false,disconnectAfterBackup=false,foreignAfterBackup:FTPRemoteVersion?
 let target:String,stage:String,backup:String
 init(_ state:TransferResume)throws{target=state.destination;stage=state.temporaryPath;backup=try FTPFilePublisher.backup(destination:target,temporary:stage)}
 func ops()->FTPPublicationOperations{FTPPublicationOperations(snapshot:{path in if self.networkDown{throw SFTPError.message("network lost")};return self.files[path]},rename:{a,b in
  if self.networkDown{throw SFTPError.message("network lost")};if a==self.stage && self.failBefore{throw SFTPError.message("publish denied")}
  guard let item=self.files.removeValue(forKey:a) else{throw SFTPError.message("missing source")};self.files[b]=item
  if a==self.target,b==self.backup{if let foreign=self.foreignAfterBackup{self.files[self.target]=foreign};if self.disconnectAfterBackup{self.networkDown=true;throw SFTPError.message("lost backup acknowledgement")}}
  if a==self.stage,self.failAfter{self.networkDown=true;throw SFTPError.message("lost publish acknowledgement")}
 },remove:{path in if self.networkDown || self.failCleanup{throw SFTPError.message("cleanup unavailable")};self.files.removeValue(forKey:path)})}
}
@main struct FTPPublicationTests {
 static func main()throws{
  let old=FTPRemoteVersion(size:3,modified:1,mode:0o100600,digest:String(repeating:"a",count:64)),new=FTPRemoteVersion(size:4,modified:2,mode:0o100600,digest:String(repeating:"b",count:64)),foreign=FTPRemoteVersion(size:5,modified:3,mode:0o100600,digest:String(repeating:"d",count:64)),binding=String(repeating:"c",count:64)
  func fixture(original:FTPRemoteVersion?=old)throws->(TransferResume,FTPMemoryPublication){let state=TransferResume(source:"/local",destination:"/target",upload:true);state.sourceDigest=new.digest;state.ftpPublication=FTPPublicationRecord(binding:binding,original:original,phase:.ready,staged:new);let remote=try FTPMemoryPublication(state);remote.files[state.temporaryPath]=new;if let original=original{remote.files[state.destination]=original};return(state,remote)}
  func commit(_ state:TransferResume,_ remote:FTPMemoryPublication,checkpoint:()throws->Void={})throws{try FTPFilePublisher.commit(destination:state.destination,state:state,binding:binding,digest:new.digest,size:new.size,operations:remote.ops(),recovery:remote.ops,checkpoint:checkpoint)}
  var (state,remote)=try fixture();try commit(state,remote);precondition(remote.files[remote.target]==new && remote.files[remote.backup]==nil && remote.files[remote.stage]==nil && state.ftpPublication?.phase == .published)
  (state,remote)=try fixture(original:nil);try commit(state,remote);precondition(remote.files[remote.target]==new && remote.files[remote.backup]==nil)
  (state,remote)=try fixture();remote.failBefore=true;do{try commit(state,remote);fatalError("must reject publish")}catch{};precondition(remote.files[remote.target]==old && remote.files[remote.backup]==nil && remote.files[remote.stage]==new && state.ftpPublication?.phase == .ready);remote.failBefore=false;try commit(state,remote)
  (state,remote)=try fixture();var checks=0;do{try commit(state,remote,checkpoint:{checks+=1;if checks==2{throw SFTPError.message("cancelled")}});fatalError("must cancel")}catch{};precondition(remote.files[remote.target]==old && remote.files[remote.backup]==nil)
  (state,remote)=try fixture();remote.foreignAfterBackup=foreign;do{try commit(state,remote);fatalError("must preserve foreign target")}catch{};precondition(remote.files[remote.target]==foreign && remote.files[remote.backup]==old && remote.files[remote.stage]==new)
  (state,remote)=try fixture();remote.disconnectAfterBackup=true;do{try commit(state,remote);fatalError("must lose network")}catch{};precondition(remote.files[remote.target]==nil && remote.files[remote.backup]==old);remote.networkDown=false;remote.disconnectAfterBackup=false
  let restored=TransferResume(record:try JSONDecoder().decode(ResumeRecord.self,from:JSONEncoder().encode(state.record())));try commit(restored,remote);precondition(remote.files[remote.target]==new && remote.files[remote.backup]==nil)
  (state,remote)=try fixture();remote.failAfter=true;do{try commit(state,remote);fatalError("must lose final acknowledgement")}catch{};precondition(remote.files[remote.target]==new && remote.files[remote.stage]==nil && remote.files[remote.backup]==old);remote.networkDown=false;remote.failAfter=false;try commit(state,remote);precondition(remote.files[remote.backup]==nil)
  (state,remote)=try fixture();remote.failCleanup=true;do{try commit(state,remote);fatalError("cleanup must fail")}catch{};precondition(remote.files[remote.target]==new && remote.files[remote.backup]==old && state.ftpPublication?.phase == .published);remote.failCleanup=false;try commit(state,remote);precondition(remote.files[remote.backup]==nil)
  (state,remote)=try fixture();remote.files[remote.stage]=foreign;do{try commit(state,remote);fatalError("corrupt stage accepted")}catch{};precondition(remote.files[remote.target]==old && remote.files[remote.stage]==foreign)
  (state,remote)=try fixture();state.publicationBarrier={throw SFTPError.message("journal unavailable")};do{try commit(state,remote);fatalError("journal error ignored")}catch{};precondition(remote.files[remote.target]==old && remote.files[remote.backup]==nil && remote.files[remote.stage]==new);state.publicationBarrier=nil
  (state,remote)=try fixture();var barriers=0;state.publicationBarrier={barriers+=1;if barriers==2{throw SFTPError.message("journal failed after backup")}};do{try commit(state,remote);fatalError("backup journal failure ignored")}catch{};precondition(remote.files[remote.target]==old && remote.files[remote.backup]==nil && remote.files[remote.stage]==new);state.publicationBarrier=nil
  var invalid=state.record();invalid.ftpPublication=FTPPublicationRecord(binding:"invalid",original:old,phase:.ready,staged:new);do{try invalid.ftpPublication!.validated();fatalError("invalid binding accepted")}catch{}
  print("PASS: FTP publication new/overwrite, backup/restore on failure/cancel, foreign target preserved, lost backup/final acknowledgements recovered from encoded record, cleanup retry without reupload, corrupt stage refused, synchronous journal failure stops publication or restores original; deterministic fixture only")
 }
}
