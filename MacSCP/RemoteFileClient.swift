import Foundation

typealias RemoteFileAttributes=(size:UInt64,mode:UInt32,modified:UInt32)
struct RemoteFileCapabilities:OptionSet {
 let rawValue:Int
 static let atomicOverwrite=Self(rawValue:1<<0),permissions=Self(rawValue:1<<1),symbolicLinks=Self(rawValue:1<<2),remoteCopy=Self(rawValue:1<<3),checksum=Self(rawValue:1<<4),resume=Self(rawValue:1<<5),timestamps=Self(rawValue:1<<6),downloadResume=Self(rawValue:1<<7),timestampOnly=Self(rawValue:1<<8)
}

// A backend owns its transport. Feature code never receives its Process or wire packets.
protocol RemoteFileClient:AnyObject {
 var capabilities:RemoteFileCapabilities{get}
 var progress:((UInt64)->Void)?{get set}
 var resumedProgress:((UInt64)->Void)?{get set}
 var phase:((String)->Void)?{get set}
 var auxiliaryProgress:((UInt64)->Void)?{get set}
 var checkpoint:(()throws->Void)?{get set}
 func close()
 func interrupt()
 func canonical(_ path:String)throws->String
 func list(_ path:String,resolveLinks:Bool,maximumEntries:Int?)throws->[RemoteFile]
 func attributes(_ path:String)throws->RemoteFileAttributes?
 func followedAttributes(_ path:String)throws->RemoteFileAttributes?
 func download(_ remote:String,to local:URL,maximumBytes:UInt64?)throws
 func upload(_ local:URL,to remote:String,overwrite:Bool,permissions:UInt32?,beforeCommit:(()throws->Void)?)throws
 func uploadResumable(_ local:URL,to remote:String,state:TransferResume,overwrite:Bool,verifyChecksum:Bool)throws
 func downloadResumable(_ remote:String,to local:URL,state:TransferResume,overwrite:Bool,verifyChecksum:Bool)throws
 func mkdir(_ path:String)throws
 func rename(_ source:String,to destination:String)throws
 func remove(_ path:String,directory:Bool)throws
 func setModificationTime(_ path:String,to seconds:UInt32,expected:RemoteFileAttributes,beforeCommit:(()throws->Void)?)throws
 func chmod(_ path:String,mode:UInt32)throws
 func readLink(_ path:String)throws->String
 func createSymbolicLink(target:String,path:String)throws
 func checksum(_ path:String)throws->String
 func copyRemoteFile(_ source:String,to destination:String)throws
}
extension RemoteFileClient {
 func setModificationTime(_ path:String,to seconds:UInt32,expected:RemoteFileAttributes,beforeCommit:(()throws->Void)?)throws{throw SFTPError.message("当前协议不支持仅修改时间戳")}
 // Distinct overloads provide convenience without recursive default witnesses.
 func list(_ path:String)throws->[RemoteFile]{try list(path,resolveLinks:false,maximumEntries:nil)}
 func list(_ path:String,resolveLinks:Bool)throws->[RemoteFile]{try list(path,resolveLinks:resolveLinks,maximumEntries:nil)}
 func list(_ path:String,maximumEntries:Int)throws->[RemoteFile]{try list(path,resolveLinks:false,maximumEntries:maximumEntries)}
 func download(_ remote:String,to local:URL)throws{try download(remote,to:local,maximumBytes:nil)}
 func upload(_ local:URL,to remote:String,overwrite:Bool=false)throws{try upload(local,to:remote,overwrite:overwrite,permissions:nil,beforeCommit:nil)}
 func upload(_ local:URL,to remote:String,overwrite:Bool,permissions:UInt32?)throws{try upload(local,to:remote,overwrite:overwrite,permissions:permissions,beforeCommit:nil)}
 func remove(_ path:String)throws{try remove(path,directory:false)}
 func uploadResumable(_ local:URL,to remote:String,state:TransferResume,overwrite:Bool=false)throws{try uploadResumable(local,to:remote,state:state,overwrite:overwrite,verifyChecksum:false)}
 func downloadResumable(_ remote:String,to local:URL,state:TransferResume,overwrite:Bool=false)throws{try downloadResumable(remote,to:local,state:state,overwrite:overwrite,verifyChecksum:false)}
}

enum RemoteItemMutation {
 case makeDirectory(String),rename(String,String)
 func perform(in directory:String,client:RemoteFileClient)throws{
  func path(_ name:String)->String{(directory=="/" ? "/" : directory+"/")+name}
  switch self{case .makeDirectory(let name):try client.mkdir(path(name));case .rename(let source,let destination):try client.rename(path(source),to:path(destination))}
 }
}
