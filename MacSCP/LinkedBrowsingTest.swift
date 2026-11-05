import Foundation
@main struct LinkedBrowsingTests {
 static func main()throws{
  let link=LinkedBrowsing(enabled:true)
  let down=link.begin(side:.local,from:"/Users/me/www",counterpart:"/home/me/site")!
  let remote=try link.followedPath(down,arrived:"/Users/me/www/wiki/中文 空格%20#")!
  precondition(remote.side == .remote && remote.path=="/home/me/site/wiki/中文 空格%20#")
  let up=link.begin(side:.remote,from:remote.path,counterpart:"/Users/me/www/wiki/中文 空格%20#")!
  let local=try link.followedPath(up,arrived:"/home/me/site/wiki")!;precondition(local.path=="/Users/me/www/wiki" && local.side == .local)
  let same=try link.followedPath(up,arrived:up.from);precondition(same==nil)
  let root=link.begin(side:.remote,from:"/a/b",counterpart:"/x/y")!;let rootTarget=try link.followedPath(root,arrived:"/")!;precondition(rootTarget.path=="/")
  let short=link.begin(side:.remote,from:"/a/b/c",counterpart:"/x")!;do{_ = try link.followedPath(short,arrived:"/");fatalError("cannot mirror above counterpart root")}catch{}
  let first=link.begin(side:.remote,from:"/remote",counterpart:"/local")!,older=DirectoryBrowseRequest(target:"/remote/a",origin:.user,intent:first)
  let paired=LinkedBrowseRequest(id:first.id,side:.local,path:"/local/a"),pairedRead=DirectoryBrowseRequest(target:paired.path,origin:.linked(paired),intent:nil)
  precondition(!older.obsolete(in:link) && !pairedRead.obsolete(in:link))
  _ = link.begin(side:.local,from:"/local",counterpart:"/remote")!
  precondition(older.obsolete(in:link) && pairedRead.obsolete(in:link));let stale=try link.followedPath(first,arrived:"/remote/a");precondition(stale==nil)
  let refresh=DirectoryBrowseRequest(target:"/remote",origin:.passive,intent:nil);precondition(!refresh.obsolete(in:link))
  link.setEnabled(false);precondition(!older.obsolete(in:link) && pairedRead.obsolete(in:link) && link.begin(side:.local,from:"/a",counterpart:"/b")==nil)
  link.setEnabled(true)
  let rapidA=link.begin(side:.local,from:"/local",counterpart:"/remote")!
  let pendingA=try link.followedPath(rapidA,arrived:"/local/a")!
  let rapidB=link.begin(side:.local,from:"/local/a",counterpart:"/remote")!
  let pendingB=try link.followedPath(rapidB,arrived:"/local/b")!
  precondition(pendingB.path=="/remote/b" && !link.isCurrent(pendingA.id))
  link.accepted(pendingA);link.accepted(pendingB)
  let other=LinkedBrowsing(enabled:true);precondition(!other.isCurrent(first.id));link.setEnabled(true);precondition(!link.isCurrent(first.id))
  let normalized=try LinkedBrowsing.components("/a//b/./c/..");precondition(normalized==["a","b"])
  do{_ = try LinkedBrowsing.components("/../../x");fatalError("root escape")}catch{}
  do{_ = try LinkedBrowsing.components("relative/x");fatalError("relative input")}catch{}

  let fm=FileManager.default,base=fm.temporaryDirectory.appendingPathComponent("linked-browse-"+UUID().uuidString)
  try fm.createDirectory(at:base,withIntermediateDirectories:false);let fixture=base.resolvingSymlinksInPath();defer{try? fm.removeItem(at:fixture)}
  let localRoot=fixture.appendingPathComponent("本地"),remoteRoot=fixture.appendingPathComponent("远程")
  for directory in [localRoot,remoteRoot]{try fm.createDirectory(at:directory,withIntermediateDirectories:false)}
  let server=try SFTPClient(command:"/usr/libexec/sftp-server",arguments:[]);defer{server.close()}
  let remoteBase=try server.canonical(remoteRoot.path)
  let localChild=localRoot.appendingPathComponent("wiki/中文 空格%20#"),remoteChild=remoteBase+"/wiki/中文 空格%20#"
  try LinkedDirectoryCreator.local(localChild.path)
  precondition(LinkedDirectoryCreator.localMissing(localRoot.appendingPathComponent("missing/sub").path))
  let intent=link.begin(side:.local,from:localRoot.path,counterpart:remoteBase)!,target=try link.followedPath(intent,arrived:localChild.path)!
  precondition(target.path==remoteChild && RemoteDirectoryRead.missing(target.path,client:server))
  // No implicit directory creation: the missing read must fail first.
  do{_ = try RemoteDirectoryRead.read(target.path,client:server);fatalError("missing target unexpectedly read")}catch{}
  precondition(!fm.fileExists(atPath:remoteChild))
  try LinkedDirectoryCreator.remote(target.path,client:server);try LinkedDirectoryCreator.remote(target.path,client:server)
  let listing=try RemoteDirectoryRead.read(target.path,client:server);precondition(listing.path==remoteChild && listing.entries.isEmpty)
  let reverse=link.begin(side:.remote,from:remoteChild,counterpart:localChild.path)!,back=try link.followedPath(reverse,arrived:remoteBase)!
  precondition(back.path==localRoot.path)
  let file=fixture.appendingPathComponent("file"),bytes=Data("original".utf8);try bytes.write(to:file)
  let remoteFile=try server.canonical(file.path)
  precondition(!RemoteDirectoryRead.missing(remoteFile+"/child",client:server) && !LinkedDirectoryCreator.localMissing(file.path+"/child"))
  do{try LinkedDirectoryCreator.local(file.path+"/child");fatalError("local file parent")}catch{}
  do{try LinkedDirectoryCreator.remote(remoteFile+"/child",client:server);fatalError("remote file parent")}catch{}
  let shortcut=fixture.appendingPathComponent("link");try fm.createSymbolicLink(at:shortcut,withDestinationURL:localRoot)
  let remoteShortcut=(try server.canonical(fixture.path))+"/link"
  precondition(!RemoteDirectoryRead.missing(remoteShortcut+"/child",client:server))
  do{try LinkedDirectoryCreator.local(shortcut.path+"/child");fatalError("local link parent")}catch{}
  do{try LinkedDirectoryCreator.remote(remoteShortcut+"/child",client:server);fatalError("remote link parent")}catch{}
  let preserved=try Data(contentsOf:file);precondition(preserved==bytes && !fm.fileExists(atPath:localRoot.appendingPathComponent("child").path))
  print("PASS: bidirectional relative child/parent/root mapping, Unicode/literal percent/hash, stale user and paired results discarded, passive refresh and disable semantics, session ticket isolation; actual SFTP navigation and explicit nested directory creation; files/links/escape paths refused without modifying original data")
 }
}
