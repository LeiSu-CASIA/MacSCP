import Foundation
@main struct SyncPartialDeletionTests {
 static func check(_ value:Bool,file:StaticString = #file,line:UInt = #line){precondition(value,file:file,line:line)}
 static func refused(_ action:()throws->Void){do{try action();fatalError("unsafe partial deletion accepted")}catch{}}
 static func main()throws {
  let fm=FileManager.default,root=fm.temporaryDirectory.appendingPathComponent("partial-cleanup-"+UUID().uuidString),local=root.appendingPathComponent("local"),remote=root.appendingPathComponent("remote"),bin=root.appendingPathComponent("test-bin")
  for path in [local,remote,bin]{try fm.createDirectory(at:path,withIntermediateDirectories:true)};defer{try? fm.removeItem(at:root)}
  let client=try SFTPClient(command:"/usr/libexec/sftp-server",arguments:[]);defer{client.close()}
  func put(_ base:URL,_ path:String,_ text:String="fixture")throws{let url=base.appendingPathComponent(path);try fm.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true);try Data(text.utf8).write(to:url)}
  func make(_ name:String,up:Bool=true,hash:Bool=false)throws->SyncDeletionPlan{var l=try SyncPlanner.local(local.path),r=try SyncPlanner.remote(remote.path,client:client);if hash{l=try SyncChecksums.local(l,root:local.path);r=try SyncChecksums.remote(r,root:remote.path,client:client)};let candidate=SyncComparison.candidates(local:l,remote:r,direction:up ? .upload : .download,deleteExtraneous:true).first{$0.relative==name}!;return try SyncDeletionPlan.prepare(candidate,localRoot:local.path,remoteRoot:remote.path,localSnapshot:l,remoteSnapshot:r,client:client)}
  func selection(_ plan:SyncDeletionPlan,_ picked:[String])throws->SyncContents{var model=try SyncContents(root:plan.candidate.relative,snapshot:plan.candidate.upload==true ? plan.remoteSnapshot : plan.localSnapshot,policy:TransferPolicy());model.setAll(false);for path in picked{model.set(path,on:true)};return model}
  let canonicalLocal=try LocalTrashPlan.canonicalDirectory(local.path);var moved=[String]()
  func trash(_ path:URL)throws{moved.append(String(path.path.dropFirst(canonicalLocal.count+1)));try fm.moveItem(at:path,to:bin.appendingPathComponent(UUID().uuidString+"-"+path.lastPathComponent))}
  func run(_ partial:SyncPartialDeletion,_ point:()throws->Void={})throws{try partial.execute(client:client,checkpoint:point,trash:trash)}
  for base in [local,remote]{let name=base==local ? "localtree" : "tree";try put(base,name+"/sub/drop");try put(base,name+"/sub/keep");try put(base,name+"/full/a");try put(base,name+"/full/b");try fm.createDirectory(at:base.appendingPathComponent(name+"/empty"),withIntermediateDirectories:true)}
  let remotePlan=try make("tree"),picked=try selection(remotePlan,["tree/sub/drop","tree/full","tree/empty"])
  check(Set(picked.selectedRoots)==["tree/sub/drop","tree/full","tree/empty"])
  try run(SyncPartialDeletion(base:remotePlan,contents:picked,policy:TransferPolicy()))
  check(fm.fileExists(atPath:remote.appendingPathComponent("tree/sub/keep").path) && fm.fileExists(atPath:remote.appendingPathComponent("tree/sub").path))
  for path in ["tree/sub/drop","tree/full","tree/empty"]{check(!fm.fileExists(atPath:remote.appendingPathComponent(path).path))}
  let localPlan=try make("localtree",up:false),localChoice=try selection(localPlan,["localtree/sub/drop","localtree/full","localtree/empty"])
  try run(SyncPartialDeletion(base:localPlan,contents:localChoice,policy:TransferPolicy()))
  check(Set(moved)==["localtree/sub/drop","localtree/full","localtree/empty"] && fm.fileExists(atPath:local.appendingPathComponent("localtree/sub/keep").path))
  // Old plans never authorize a new tree member, even if it would not have been selected.
  try put(remote,"stale/drop");try put(remote,"stale/keep");let stale=try make("stale"),stalePart=try SyncPartialDeletion(base:stale,contents:selection(stale,["stale/drop"]),policy:TransferPolicy())
  try put(remote,"stale/new");refused{try run(stalePart)};check(fm.fileExists(atPath:remote.appendingPathComponent("stale/drop").path))
  try put(local,"appeared/drop");try put(local,"appeared/keep");let appeared=try make("appeared",up:false),appearedPart=try SyncPartialDeletion(base:appeared,contents:selection(appeared,["appeared/drop"]),policy:TransferPolicy())
  try put(remote,"appeared/source");refused{try run(appearedPart)};check(fm.fileExists(atPath:local.appendingPathComponent("appeared/drop").path))
  // A projected directory cannot hide an excluded descendant and then delete its parent.
  let masked=try SyncContents(root:"stale",snapshot:stale.remoteSnapshot,policy:TransferPolicy(exclude:"keep"))
  refused{_ = try SyncPartialDeletion(base:stale,contents:masked,policy:TransferPolicy(exclude:"keep"))}
  let empty=try selection(stale,[]);refused{_ = try SyncPartialDeletion(base:stale,contents:empty,policy:TransferPolicy())}
  try put(remote,"late/full/a");try put(remote,"late/keep");let late=try make("late"),latePart=try SyncPartialDeletion(base:late,contents:selection(late,["late/full"]),policy:TransferPolicy());var lateAdded=false
  refused{try run(latePart,{if !lateAdded && !fm.fileExists(atPath:remote.appendingPathComponent("late/full/a").path){lateAdded=true;try put(remote,"late/full/new","new remote writer")}})}
  check(lateAdded && fm.fileExists(atPath:remote.appendingPathComponent("late/full/new").path) && fm.fileExists(atPath:remote.appendingPathComponent("late/keep").path))
  // Cancellation is checked before the first mutation.
  try put(remote,"cancel/drop");try put(remote,"cancel/keep");let cancelled=try make("cancel"),cancelPart=try SyncPartialDeletion(base:cancelled,contents:selection(cancelled,["cancel/drop"]),policy:TransferPolicy())
  refused{try run(cancelPart,{throw SFTPError.message("fixture cancelled")})};check(fm.fileExists(atPath:remote.appendingPathComponent("cancel/drop").path))
  // A local subtree receiving a new member between trash moves must remain intact.
  try put(local,"racing/a");try put(local,"racing/dir/b");try put(local,"racing/keep");let racing=try make("racing",up:false),racingPart=try SyncPartialDeletion(base:racing,contents:selection(racing,["racing/a","racing/dir"]),policy:TransferPolicy())
  var injected=false
  refused{try racingPart.execute(client:client,checkpoint:{},trash:{path in try trash(path);if !injected{injected=true;let remaining=path.lastPathComponent=="dir" ? "racing/a" : "racing/dir/new";try put(local,remaining,"new writer")}})}
  check(injected && fm.fileExists(atPath:local.appendingPathComponent("racing/keep").path))
  try put(local,"parent-change/a");try put(local,"parent-change/b");try put(local,"parent-change/keep")
  let parentPlan=try make("parent-change",up:false),parentPart=try SyncPartialDeletion(base:parentPlan,contents:selection(parentPlan,["parent-change/a","parent-change/b"]),policy:TransferPolicy())
  let outside=root.appendingPathComponent("outside");try fm.createDirectory(at:outside,withIntermediateDirectories:true);try put(outside,"a","outside a");try put(outside,"b","outside b");var replaced=false
  refused{try parentPart.execute(client:client,checkpoint:{},trash:{url in try trash(url);if !replaced{replaced=true;try fm.moveItem(at:local.appendingPathComponent("parent-change"),to:root.appendingPathComponent("held-parent"));try fm.createSymbolicLink(atPath:local.appendingPathComponent("parent-change").path,withDestinationPath:outside.path)}})}
  check(replaced);check(try Data(contentsOf:outside.appendingPathComponent("b"))==Data("outside b".utf8));try fm.removeItem(at:local.appendingPathComponent("parent-change"))
  // Hash revalidation catches a concurrent same-size/same-time change after an earlier deletion.
  try put(remote,"hashed/a","aaaa");try put(remote,"hashed/b","bbbb");try put(remote,"hashed/keep","keep")
  let hashed=try make("hashed",hash:true),hashedPart=try SyncPartialDeletion(base:hashed,contents:selection(hashed,["hashed/a","hashed/b"]),policy:TransferPolicy());var changed:String?
  refused{try run(hashedPart,{
   if changed==nil{let a=fm.fileExists(atPath:remote.appendingPathComponent("hashed/a").path),b=fm.fileExists(atPath:remote.appendingPathComponent("hashed/b").path);if a != b{let path=a ? "hashed/a" : "hashed/b";changed=path;try put(remote,path,"xxxx");try fm.setAttributes([.modificationDate:Date(timeIntervalSince1970:hashed.remoteSnapshot[path]!.modified)],ofItemAtPath:remote.appendingPathComponent(path).path)}}
  })}
  check(changed != nil);check(try Data(contentsOf:remote.appendingPathComponent(changed!))==Data("xxxx".utf8));check(fm.fileExists(atPath:remote.appendingPathComponent("hashed/keep").path))
  print("PASS: partial remote/local cleanup preserves unchecked siblings and mixed parents, whole subtree/empty-directory selection, original-plan/new-member/source-appearance/cancel/mask checks, local concurrent writes and per-item remote hash revalidation; local SFTP plus injected test bin only")
 }
}
