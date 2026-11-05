import Foundation

// A separate backend type (not a SFTPClient subclass) exercises every high-level consumer through the contract.
final class AlternateRemoteClient:RemoteFileClient {
 private let backend:SFTPClient
 private(set) var interrupts=0
 init()throws{backend=try SFTPClient(command:"/usr/libexec/sftp-server",arguments:[])}
 var capabilities:RemoteFileCapabilities{backend.capabilities}
 var progress:((UInt64)->Void)?{get{backend.progress}set{backend.progress=newValue}}
 var resumedProgress:((UInt64)->Void)?{get{backend.resumedProgress}set{backend.resumedProgress=newValue}}
 var phase:((String)->Void)?{get{backend.phase}set{backend.phase=newValue}}
 var auxiliaryProgress:((UInt64)->Void)?{get{backend.auxiliaryProgress}set{backend.auxiliaryProgress=newValue}}
 var checkpoint:(()throws->Void)?{get{backend.checkpoint}set{backend.checkpoint=newValue}}
 func close(){backend.close()}
 func interrupt(){interrupts+=1;backend.interrupt()}
 func canonical(_ path:String)throws->String{try backend.canonical(path)}
 func list(_ path:String,resolveLinks:Bool,maximumEntries:Int?)throws->[RemoteFile]{try backend.list(path,resolveLinks:resolveLinks,maximumEntries:maximumEntries)}
 func attributes(_ path:String)throws->RemoteFileAttributes?{try backend.attributes(path)}
 func followedAttributes(_ path:String)throws->RemoteFileAttributes?{try backend.followedAttributes(path)}
 func download(_ remote:String,to local:URL,maximumBytes:UInt64?)throws{try backend.download(remote,to:local,maximumBytes:maximumBytes)}
 func upload(_ local:URL,to remote:String,overwrite:Bool,permissions:UInt32?,beforeCommit:(()throws->Void)?)throws{try backend.upload(local,to:remote,overwrite:overwrite,permissions:permissions,beforeCommit:beforeCommit)}
 func uploadResumable(_ local:URL,to remote:String,state:TransferResume,overwrite:Bool,verifyChecksum:Bool)throws{try backend.uploadResumable(local,to:remote,state:state,overwrite:overwrite,verifyChecksum:verifyChecksum)}
 func downloadResumable(_ remote:String,to local:URL,state:TransferResume,overwrite:Bool,verifyChecksum:Bool)throws{try backend.downloadResumable(remote,to:local,state:state,overwrite:overwrite,verifyChecksum:verifyChecksum)}
 func mkdir(_ path:String)throws{try backend.mkdir(path)}
 func rename(_ source:String,to destination:String)throws{try backend.rename(source,to:destination)}
 func remove(_ path:String,directory:Bool)throws{try backend.remove(path,directory:directory)}
 func setModificationTime(_ path:String,to seconds:UInt32,expected:RemoteFileAttributes,beforeCommit:(()throws->Void)?)throws{try backend.setModificationTime(path,to:seconds,expected:expected,beforeCommit:beforeCommit)}
 func chmod(_ path:String,mode:UInt32)throws{try backend.chmod(path,mode:mode)}
 func readLink(_ path:String)throws->String{try backend.readLink(path)}
 func createSymbolicLink(target:String,path:String)throws{try backend.createSymbolicLink(target:target,path:path)}
 func checksum(_ path:String)throws->String{try backend.checksum(path)}
 func copyRemoteFile(_ source:String,to destination:String)throws{try backend.copyRemoteFile(source,to:destination)}
 func disableAtomicOverwrite(){backend.extensions.remove("posix-rename@openssh.com")}
}
@main struct RemoteClientTests {
 static func check(_ value:Bool){precondition(value)}
 static func main()throws{
  let fm=FileManager.default,root=fm.temporaryDirectory.appendingPathComponent("remote-client-"+UUID().uuidString),source=root.appendingPathComponent("source"),remote=root.appendingPathComponent("uploaded"),local=root.appendingPathComponent("downloaded")
  try fm.createDirectory(at:source.appendingPathComponent("nested"),withIntermediateDirectories:true);defer{try? fm.removeItem(at:root)}
  try Data("original".utf8).write(to:source.appendingPathComponent("text.txt"));let data=Data(repeating:77,count:120000);try data.write(to:source.appendingPathComponent("nested/data.bin"))
  let upload=TransferJob(up:true,source:source.path,destination:remote.path,directory:true,size:0);upload.policy=TransferPolicy(verifyChecksum:true);upload.policyConfigured=true;upload.factory={try AlternateRemoteClient()};upload.execute({});check(upload.finished && !upload.failed)
  let download=TransferJob(up:false,source:remote.path,destination:local.path,directory:true,size:0);download.factory={try AlternateRemoteClient()};download.execute({});check(try download.finished && !download.failed && Data(contentsOf:local.appendingPathComponent("nested/data.bin"))==data)
  let backend=try AlternateRemoteClient(),client:RemoteFileClient=backend;defer{client.close()}
  check(client.capabilities.contains([.atomicOverwrite,.checksum,.resume,.symbolicLinks,.permissions]))
  check(try client.list(remote.path).count==2);check(try client.list(remote.path,resolveLinks:true).count==2);check(try client.list(remote.path,maximumEntries:2).count==2)
  let listing=try RemoteDirectoryRead.read(remote.path,client:client);check(listing.entries.count==2)
  let stats=try DirectorySizeScanner.remote(paths:[remote.path],client:client,cancellation:DirectorySizeCancellation());check(stats.complete && stats.bytes==120008)
  let search=try RemoteSearch.find(root:remote.path,query:"*.txt",client:client,cancellation:SearchCancellation());check(search.hits.count==1)
  let snapshot=try SyncPlanner.remote(remote.path,client:client);check(snapshot["nested/data.bin"]?.size==120000)
  let path=remote.appendingPathComponent("text.txt").path,document=try RemoteTextDocument(path:path,client:client);try document.save("updated",client:client);check(try Data(contentsOf:URL(fileURLWithPath:path))==Data("updated".utf8))
  try RemoteItemMutation.makeDirectory("new-dir").perform(in:remote.path,client:client);try RemoteItemMutation.rename("new-dir","renamed").perform(in:remote.path,client:client);try client.remove(remote.appendingPathComponent("renamed").path,directory:true)
  let hash=try client.checksum(path);check(hash == (try StableChecksum.local(path)))
  backend.disableAtomicOverwrite();check(!client.capabilities.contains(.atomicOverwrite));do{try document.save("must not replace",client:client);fatalError("atomic overwrite must remain required")}catch{};check(try Data(contentsOf:URL(fileURLWithPath:path))==Data("updated".utf8))
  client.interrupt();check(backend.interrupts==1)
  print("PASS: distinct protocol client drives real recursive transfers, callbacks/SHA, browsing/search/sync/statistics/editor, convenience dispatch and typed mutations; negotiated atomic capability and refusal preserve target; transport interruption encapsulated; fixture only, no FTP implementation claimed")
 }
}
