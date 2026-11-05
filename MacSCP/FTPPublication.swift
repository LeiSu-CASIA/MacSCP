import Foundation

struct FTPRemoteVersion:Codable,Equatable {
 let size:UInt64,modified:UInt32,mode:UInt32,digest:String
 func validated()throws{guard size<=UInt64(Int64.max),mode&0o170000==0o100000,digest.count==64,digest.allSatisfy({$0.isHexDigit}) else{throw SFTPError.message("FTP 发布版本无效")}}
}
struct FTPPublicationRecord:Codable,Equatable {
 enum Phase:String,Codable{case transferring,ready,backedUp,published}
 let binding:String,original:FTPRemoteVersion?
 var phase:Phase;var staged:FTPRemoteVersion?=nil
 func validated()throws{guard binding.count==64,binding.allSatisfy({$0.isHexDigit}) else{throw SFTPError.message("FTP 发布端点绑定无效")};try original?.validated();try staged?.validated();if phase != .transferring,staged==nil{throw SFTPError.message("FTP 发布记录缺少已验证暂存")}}
}
struct FTPPublicationOperations {
 let snapshot:(String)throws->FTPRemoteVersion?
 let rename:(String,String)throws->Void
 let remove:(String)throws->Void
}
enum FTPFilePublisher {
 static func backup(destination:String,temporary:String)throws->String{
  let prefix=destination+".macscp-resume-";guard temporary.hasPrefix(prefix),let uuid=UUID(uuidString:String(temporary.dropFirst(prefix.count))) else{throw SFTPError.message("FTP 发布暂存路径无效")}
  return destination+".macscp-backup-"+uuid.uuidString
 }
 static func commit(destination:String,state:TransferResume,binding:String,digest:String,size:UInt64,operations:FTPPublicationOperations,recovery:()throws->FTPPublicationOperations,checkpoint:()throws->Void)throws{
  guard var record=state.ftpPublication,record.binding==binding,record.phase != .transferring,state.sourceDigest==digest,record.staged?.digest==digest,record.staged?.size==size else{throw SFTPError.message("FTP 发布记录与已验证暂存不匹配")};try record.validated()
  let stage=state.temporaryPath,backup=try backup(destination:destination,temporary:stage)
  func isNew(_ value:FTPRemoteVersion?)->Bool{value==record.staged}
  func save(_ phase:FTPPublicationRecord.Phase)throws{record.phase=phase;try state.persistPublication(record)}
  func finish(_ ops:FTPPublicationOperations)throws{
   guard isNew(try ops.snapshot(destination)),try ops.snapshot(stage)==nil else{throw SFTPError.message("FTP 已发布目标或暂存发生变化，保留回滚文件："+backup)}
   if let old=try ops.snapshot(backup){guard let expected=record.original,old==expected else{throw SFTPError.message("FTP 回滚文件变化，未清理："+backup)};try ops.remove(backup)}
   try save(.published)
  }
  do{
   try state.publicationBarrier?()
   let staged=try operations.snapshot(stage),target=try operations.snapshot(destination),saved=try operations.snapshot(backup)
   if staged==nil{guard isNew(target) else{throw SFTPError.message("FTP 暂存缺失且目标不匹配；请检查回滚路径："+backup)};try save(.published);try finish(operations);return}
   guard isNew(staged) else{throw SFTPError.message("FTP 暂存内容未通过最终验证")}
   if let original=record.original{
    if saved==nil{guard target==original else{throw SFTPError.message("FTP 目标在上传期间变化，未覆盖")};try checkpoint();try operations.rename(destination,backup);try save(.backedUp)}
    else{guard saved==original,target==nil else{throw SFTPError.message("FTP 回滚或目标状态存在冲突，保留："+backup)};try save(.backedUp)}
   }else{guard target==nil,saved==nil else{throw SFTPError.message("FTP 新目标或回滚路径已存在，未覆盖")}}
   try checkpoint();guard try operations.snapshot(destination)==nil else{throw SFTPError.message("FTP 发布前目标已出现，保留暂存及回滚")}
   guard isNew(try operations.snapshot(stage)) else{throw SFTPError.message("FTP 发布前暂存内容变化")}
   try operations.rename(stage,destination);try save(.published);try finish(operations)
  }catch{
   let originalError=error
   do{let ops=try recovery()
    let target=try ops.snapshot(destination),staged=try ops.snapshot(stage)
    if isNew(target),staged==nil{try save(.published);try finish(ops);return}
    if let expected=record.original,target==nil,try ops.snapshot(backup)==expected{try ops.rename(backup,destination);try save(.ready)}
   }catch{throw SFTPError.message("FTP 发布未能完成或回滚，保留路径：\(backup)；\(originalError.localizedDescription)；\(error.localizedDescription)")}
   throw originalError
  }
 }
}
