import Foundation
@main struct SyncContentsTests {
 static func check(_ value:Bool,file:StaticString = #file,line:UInt = #line){precondition(value,file:file,line:line)}
 static func refused(_ action:()throws->Void){do{try action();fatalError("invalid selection accepted")}catch{}}
 static func main()throws {
  let d=SyncNode(directory:true,size:0,modified:100),f=SyncNode(directory:false,size:4,modified:100)
  let snapshot=["tree":d,"tree/sub":d,"tree/sub/keep.txt":f,"tree/sub/skip.bin":f,"tree/empty":d,"tree/keep.txt":f,"tree/private":d,"tree/private/secret.txt":f,"other":f]
  var model=try SyncContents(root:"tree",snapshot:snapshot,policy:TransferPolicy(include:"*.txt",exclude:"private/"))
  check(model.leaves==["tree/sub/keep.txt","tree/empty","tree/keep.txt"] && model.selected==model.leaves && model.state("tree") == .on)
  model.setAll(false);model.set("tree/sub/keep.txt",on:true)
  check(model.state("tree") == .mixed && model.state("tree/sub") == .on && model.state("tree/empty") == .off)
  check(model.requiredPaths==["tree","tree/sub","tree/sub/keep.txt"] && model.bytes==4)
  model.set("tree",on:true);check(model.selected==model.leaves);model.set("tree/sub",on:false);check(!model.selected.contains("tree/sub/keep.txt"))
  refused{_ = try SyncContents(root:"../tree",snapshot:snapshot,policy:TransferPolicy())}
  refused{_ = try SyncContents(root:"tree",snapshot:snapshot,policy:TransferPolicy(),selected:["other"])}
  refused{_ = try SyncContents(root:"tree",snapshot:["tree":d,"tree/missing/file":f],policy:TransferPolicy())}
  var changed=snapshot;changed["tree/keep.txt"]=SyncNode(directory:false,size:5,modified:100)
  refused{_ = try model.validated(root:"tree",snapshot:changed,policy:TransferPolicy(include:"*.txt",exclude:"private/"))}
  let fm=FileManager.default,root=fm.temporaryDirectory.appendingPathComponent("sync-contents-"+UUID().uuidString),local=root.appendingPathComponent("local"),remote=root.appendingPathComponent("remote"),download=root.appendingPathComponent("download")
  for path in [local.appendingPathComponent("tree/sub"),local.appendingPathComponent("tree/empty"),local.appendingPathComponent("tree/not-selected-empty"),remote,download]{try fm.createDirectory(at:path,withIntermediateDirectories:true)};defer{try? fm.removeItem(at:root)}
  try Data("keep".utf8).write(to:local.appendingPathComponent("tree/sub/keep.txt"));try Data("skip".utf8).write(to:local.appendingPathComponent("tree/sub/skip.txt"));try Data("root skip".utf8).write(to:local.appendingPathComponent("tree/skip.txt"))
  let client=try SFTPClient(command:"/usr/libexec/sftp-server",arguments:[]);defer{client.close()}
  let snap=try SyncPlanner.local(local.path);var selection=try SyncContents(root:"tree",snapshot:snap,policy:TransferPolicy());selection.setAll(false);selection.set("tree/sub/keep.txt",on:true);selection.set("tree/empty",on:true)
  let up=TransferJob(up:true,source:local.appendingPathComponent("tree").path,destination:remote.appendingPathComponent("tree").path,directory:true,size:selection.bytes)
  up.policyRootRelative="tree";up.restrictedPaths=selection.requiredPaths;up.factory={try SFTPClient(command:"/usr/libexec/sftp-server",arguments:[])};up.execute({})
  check(up.finished && !up.failed && up.transferredBytes==4)
  check(try Data(contentsOf:remote.appendingPathComponent("tree/sub/keep.txt"))==Data("keep".utf8));check(fm.fileExists(atPath:remote.appendingPathComponent("tree/empty").path))
  for name in ["tree/sub/skip.txt","tree/skip.txt","tree/not-selected-empty"]{check(!fm.fileExists(atPath:remote.appendingPathComponent(name).path))}
  let rs=try SyncPlanner.remote(remote.path,client:client);var picked=try SyncContents(root:"tree",snapshot:rs,policy:TransferPolicy());picked.setAll(false);picked.set("tree/sub/keep.txt",on:true)
  let down=TransferJob(up:false,source:remote.appendingPathComponent("tree").path,destination:download.appendingPathComponent("tree").path,directory:true,size:picked.bytes)
  down.policyRootRelative="tree";down.restrictedPaths=picked.requiredPaths;down.factory={try SFTPClient(command:"/usr/libexec/sftp-server",arguments:[])};down.execute({})
  check(down.finished && !down.failed);check(try Data(contentsOf:download.appendingPathComponent("tree/sub/keep.txt"))==Data("keep".utf8));check(!fm.fileExists(atPath:download.appendingPathComponent("tree/empty").path))
  let recovering=TransferJob(up:true,source:"owned",destination:"owned",directory:true,size:0);recovering.restrictedPaths=["tree"];recovering.recoverySite=Session(name:"fixture",host:"fixture.invalid",user:"fixture",port:22,key:"");check(recovering.recoveryRecord()==nil)
  print("PASS: tree leaf and empty-directory selection, mixed states, ancestor scope, masks, invalid/cross-root/stale rejection, actual local SFTP upload/download excludes unchecked files/directories, restricted scopes never serialized as unrestricted recovery")
 }
}
