import Foundation
struct SyncPartialDeletion {
 let base:SyncDeletionPlan,contents:SyncContents
 let roots:[String]
 init(base:SyncDeletionPlan,contents:SyncContents,policy:TransferPolicy)throws {
  guard base.candidate.directory,base.candidate.deletion,!contents.selected.isEmpty else{throw SFTPError.message("请选择目录内要清理的项目")}
  let snapshot=base.candidate.upload==true ? base.remoteSnapshot : base.localSnapshot
  let bound=try contents.validated(root:base.candidate.relative,snapshot:snapshot,policy:policy)
  let expected=snapshot.filter{$0.key==base.candidate.relative || $0.key.hasPrefix(base.candidate.relative+"/")}
  guard bound.manifest==expected else{throw SFTPError.message("清理目录含未列出的项目，请重新比较后选择")}
  self.base=base;self.contents=bound;roots=bound.selectedRoots
  guard !roots.isEmpty else{throw SFTPError.message("清理范围为空")}
 }
 func validate(client:RemoteFileClient)throws{try base.validate(client:client)}
 private func checkLocalParents(_ path:String,known:[String:LocalTrashSignature])throws{
  var parent=(SyncDeletionPlan.join(base.localRoot,path) as NSString).deletingLastPathComponent
  let root=SyncDeletionPlan.join(base.localRoot,base.candidate.relative)
  while parent==root || parent.hasPrefix(root+"/"){guard let expected=known[parent],let current=try SyncDeletionPlan.localSignature(parent),expected.sameDirectory(current) else{throw SFTPError.message("清理父目录被替换："+parent)};if parent==root{break};parent=(parent as NSString).deletingLastPathComponent}
 }
 private func checkRemoteParents(_ item:RemoteDeleteItem,client:RemoteFileClient,known:[String:RemoteDeleteItem])throws{
  var parent=(item.path as NSString).deletingLastPathComponent;let root=SyncDeletionPlan.join(base.remoteRoot,base.candidate.relative)
  while parent==root || parent.hasPrefix(root+"/"){guard let expected=known[parent],expected.directory,let current=try client.attributes(parent),current.mode==expected.mode,try client.canonical(parent)==parent else{throw SFTPError.message("清理父目录被替换："+parent)};if parent==root{break};parent=(parent as NSString).deletingLastPathComponent}
 }
 private func selectedAncestor(_ path:String,roots:Set<String>)->String?{var cursor=path;while cursor != "/",!cursor.isEmpty{if roots.contains(cursor){return cursor};cursor=(cursor as NSString).deletingLastPathComponent};return nil}
 func execute(client:RemoteFileClient,checkpoint:()throws->Void,trash:(URL)throws->Void)throws{
  try checkpoint();try validate(client:client)
  if base.candidate.upload==false {
   let known=Dictionary(uniqueKeysWithValues:base.localItems.map{($0.path,$0.signature)}),targets=Set(roots.map{SyncDeletionPlan.join(base.localRoot,$0)})
   var groups=[String:[LocalTrashItem]]();for item in base.localItems{if let target=selectedAncestor(item.path,roots:targets){groups[target,default:[]].append(item)}}
   for relative in roots {
    try checkpoint();try base.validateParents(client:client);try base.validateSourceAbsent(client:client);try checkLocalParents(relative,known:known)
    let target=SyncDeletionPlan.join(base.localRoot,relative),item=SyncCandidate(relative:relative,local:base.localSnapshot[relative],remote:nil,upload:false,selected:true,typeConflict:false,deletion:true)
    try SyncComparison.verify(item,localRoot:base.localRoot,remoteRoot:base.remoteRoot,localSnapshot:base.localSnapshot,remoteSnapshot:base.remoteSnapshot,client:client)
    for entry in groups[target] ?? []{try checkpoint();guard try SyncDeletionPlan.localSignature(entry.path)==entry.signature else{throw SFTPError.message("清理前本地项目已变化："+entry.path)}}
    try checkpoint();try trash(URL(fileURLWithPath:target))
   };return
  }
  let prefixes=Set(roots.map{SyncDeletionPlan.join(base.remoteRoot,$0)}),known=Dictionary(uniqueKeysWithValues:base.remoteItems.map{($0.path,$0)})
  for item in base.remoteItems where selectedAncestor(item.path,roots:prefixes) != nil {
   try checkpoint();try base.validateParents(client:client);try base.validateSourceAbsent(client:client);try checkRemoteParents(item,client:client,known:known)
   guard let current=try client.attributes(item.path),current.mode==item.mode,item.directory || current.size==item.size && current.modified==item.modified else{throw SFTPError.message("清理前远程项目已变化："+item.path)}
   if item.directory{guard try client.list(item.path,maximumEntries:1).isEmpty else{throw SFTPError.message("清理目录中出现新项目："+item.path)}}
   else{let relative=String(item.path.dropFirst(base.remoteRoot=="/" ? 1 : base.remoteRoot.count+1));if let checksum=base.remoteSnapshot[relative]?.checksum{guard try client.checksum(item.path)==checksum else{throw SFTPError.message("清理前远程内容已变化："+item.path)}}}
   try checkpoint();try client.remove(item.path,directory:item.directory)
  }
 }
}
