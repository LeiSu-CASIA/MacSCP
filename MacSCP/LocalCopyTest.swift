import Foundation
@main struct LocalCopyTests {
 static func check(_ value:Bool,file:StaticString = #file,line:UInt = #line){precondition(value,file:file,line:line)}
 static func main()throws{
  let fm=FileManager.default,root=fm.temporaryDirectory.appendingPathComponent("macscp-local-copy-"+UUID().uuidString)
  try fm.createDirectory(at:root,withIntermediateDirectories:false);defer{try? fm.removeItem(at:root)}
  let source=root.appendingPathComponent("source.bin"),target=root.appendingPathComponent("target.bin"),original=Data("original".utf8),bytes=Data((0..<(1024*1024)).map{UInt8($0%251)})
  try bytes.write(to:source);try original.write(to:target);try fm.setAttributes([.posixPermissions:0o640],ofItemAtPath:target.path)
  let state=TransferResume(source:source.path,destination:target.path,upload:false);var stop=false,reused:UInt64=0
  let first=LocalReadClient();first.progress={_ in stop=true};first.checkpoint={if stop{throw SFTPError.message("fixture stop")}}
  do{try first.downloadResumable(source.path,to:target,state:state,overwrite:true,verifyChecksum:true);fatalError("expected interruption")}catch{}
  check(try Data(contentsOf:target)==original && fm.fileExists(atPath:state.temporaryPath))
  let second=LocalReadClient();second.resumedProgress={reused+=$0};try second.downloadResumable(source.path,to:target,state:state,overwrite:true,verifyChecksum:true)
  check(try reused>0 && reused<UInt64(bytes.count) && (try Data(contentsOf:target))==bytes && !fm.fileExists(atPath:state.temporaryPath))
  check((try fm.attributesOfItem(atPath:target.path)[.posixPermissions] as? NSNumber)?.intValue==0o640)
  let race=root.appendingPathComponent("race.bin"),raceState=TransferResume(source:source.path,destination:root.appendingPathComponent("race.bin").path,upload:false);try original.write(to:race)
  let racing=LocalReadClient();var changed=false;racing.progress={_ in if !changed{changed=true;try! Data("concurrent writer".utf8).write(to:race)}}
  do{try racing.downloadResumable(source.path,to:race,state:raceState,overwrite:true,verifyChecksum:true);fatalError("expected target race refusal")}catch{}
  check(try Data(contentsOf:race)==Data("concurrent writer".utf8))
  let corrupt=root.appendingPathComponent("corrupt.bin"),badState=TransferResume(source:source.path,destination:root.appendingPathComponent("corrupt.bin").path,upload:false);var broke=false
  let partial=LocalReadClient();partial.progress={_ in broke=true};partial.checkpoint={if broke{throw SFTPError.message("stop")}}
  do{try partial.downloadResumable(source.path,to:corrupt,state:badState,overwrite:false,verifyChecksum:false)}catch{}
  let corruptFile=try FileHandle(forWritingTo:URL(fileURLWithPath:badState.temporaryPath));try corruptFile.write(contentsOf:Data("wrong".utf8));try corruptFile.close()
  do{try LocalReadClient().downloadResumable(source.path,to:corrupt,state:badState,overwrite:false,verifyChecksum:false);fatalError("expected prefix refusal")}catch{}
  check(!fm.fileExists(atPath:corrupt.path))
  let changedTarget=root.appendingPathComponent("changed.bin"),changedState=TransferResume(source:source.path,destination:root.appendingPathComponent("changed.bin").path,upload:false)
  var interrupted=false;let interruptedClient=LocalReadClient();interruptedClient.progress={_ in interrupted=true};interruptedClient.checkpoint={if interrupted{throw SFTPError.message("stop")}}
  do{try interruptedClient.downloadResumable(source.path,to:changedTarget,state:changedState,overwrite:false,verifyChecksum:false)}catch{}
  try Data(repeating:42,count:bytes.count).write(to:source)
  do{try LocalReadClient().downloadResumable(source.path,to:changedTarget,state:changedState,overwrite:false,verifyChecksum:false);fatalError("expected changed-source refusal")}catch{}
  check(!fm.fileExists(atPath:changedTarget.path))
  let tree=root.appendingPathComponent("tree"),out=root.appendingPathComponent("out")
  try fm.createDirectory(at:tree.appendingPathComponent("nested/empty"),withIntermediateDirectories:true);try Data("line\r\nline\n".utf8).write(to:tree.appendingPathComponent("nested/text.txt"))
  let job=TransferJob(up:false,source:tree.path,destination:out.path,directory:true,size:0);job.customAction="本地复制";job.policy=TransferPolicy(verifyChecksum:true);job.factory={LocalReadClient()};job.execute({})
  check(!job.failed && job.finished && fm.fileExists(atPath:out.appendingPathComponent("nested/empty").path));check(try Data(contentsOf:out.appendingPathComponent("nested/text.txt"))==Data("line\r\nline\n".utf8))
  try fm.createSymbolicLink(atPath:tree.appendingPathComponent("link").path,withDestinationPath:source.path)
  let refused=TransferJob(up:false,source:tree.path,destination:root.appendingPathComponent("refused").path,directory:true,size:0);refused.factory={LocalReadClient()};refused.execute({});check(refused.failed && !fm.fileExists(atPath:refused.destination))
  let reader=LocalReadClient();do{try reader.remove(source.path);fatalError("expected read-only")}catch{};reader.interrupt();do{_ = try reader.attributes(source.path);fatalError("expected interrupted")}catch{}
  check(fm.fileExists(atPath:source.path))
  print("PASS: local stream copy interrupted/resumed with verified prefix and exact bytes, atomic old-target protection and concurrent writer refusal, permissions, corrupt prefix/changed source refusal, recursive queued copy/empty directories/binary bytes, symlink scan refusal, read-only/interrupt; own temporary files only, no subprocess/network")
 }
}
