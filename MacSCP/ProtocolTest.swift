import Foundation
@main struct SFTPTests {
 static func main()throws {
  let root=URL(fileURLWithPath:NSTemporaryDirectory()).appendingPathComponent("macterm-sftp-"+UUID().uuidString)
  try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:root)}
  let client=try SFTPClient(command:"/usr/libexec/sftp-server",arguments:[]);defer{client.close()}
  let nested=root.appendingPathComponent("中文 空格 ' \" $;目录");try FileManager.default.createDirectory(at:nested,withIntermediateDirectories:true)
  let source=root.appendingPathComponent("source.bin");let payload=Data((0..<150000).map{UInt8($0%251)});try payload.write(to:source)
  let remote=nested.appendingPathComponent("测试 ' \" $;file.bin").path
  try client.upload(source,to:remote)
  let canonical=try client.canonical(nested.path);precondition(canonical==nested.path || canonical=="/private"+nested.path)
  let entries=try client.list(root.path);precondition(entries.contains{$0.directory && $0.name==nested.lastPathComponent})
  let list=try client.list(nested.path);precondition(list.count==1 && list[0].size==payload.count && !list[0].directory)
  let destination=root.appendingPathComponent("download.bin");try client.download(remote,to:destination);let downloaded = try Data(contentsOf:destination);precondition(downloaded==payload)
  try Data("old".utf8).write(to:destination);try client.download(remote,to:destination);let replaced = try Data(contentsOf:destination);precondition(replaced==payload)
  do {try client.upload(source,to:remote);fatalError("Existing file must not be overwritten")}catch{}
  let empty=root.appendingPathComponent("empty");try Data().write(to:empty);try client.upload(empty,to:nested.appendingPathComponent("empty").path);try client.download(nested.appendingPathComponent("empty").path,to:root.appendingPathComponent("empty-copy"))
  do {_ = try client.list(root.appendingPathComponent("missing").path);fatalError("Missing directory must fail")}catch{}
  let created=root.appendingPathComponent("新建目录").path;try client.mkdir(created)
  let renamed=root.appendingPathComponent("重命名目录").path;try client.rename(created,to:renamed)
  try client.remove(renamed,directory:true)
  let renamedFile=nested.appendingPathComponent("renamed.bin").path;try client.rename(remote,to:renamedFile);try client.remove(renamedFile)
  let failed=nested.appendingPathComponent("failed.bin").path
  let rejecting=try SFTPClient(command:"/usr/libexec/sftp-server",arguments:["-P","write"]);defer{rejecting.close()}
  do {try rejecting.upload(source,to:failed);fatalError("Server write rejection must fail")}catch{}
  let afterFailure=try client.list(nested.path);precondition(!afterFailure.contains{$0.name.contains(".macscp-") || $0.name=="failed.bin"})
  var ticks=0;client.progress={_ in ticks+=1};try client.upload(source,to:remote);precondition(ticks>2)
  let cancelling=try SFTPClient(command:"/usr/libexec/sftp-server",arguments:[]);defer{cancelling.close()};var cancelled=false
  cancelling.progress={done in if done>0 && !cancelled {cancelled=true;cancelling.process.terminate()}}
  do {try cancelling.upload(source,to:nested.appendingPathComponent("cancelled.bin").path);fatalError("Cancelled upload must fail")}catch{}
  precondition(cancelled && !FileManager.default.fileExists(atPath:nested.appendingPathComponent("cancelled.bin").path))
  print("PASS: mkdir, rename, remove, atomic publish, rejected-write cleanup, progress, cancellation without final file")
  print("SFTP passed: real OpenSSH server, list, canonical paths, binary multi-chunk upload/download, Unicode and quoted filenames, empty files, local replacement, remote overwrite protection, errors")
 }
}
