import Cocoa
@main struct FileDragPayloadTests {
 static func check(_ value:Bool){precondition(value)}
 static func main()throws{
  let fm=FileManager.default,root=fm.temporaryDirectory.appendingPathComponent("macscp-drag-payload-"+UUID().uuidString)
  try fm.createDirectory(at:root,withIntermediateDirectories:false);defer{try? fm.removeItem(at:root)}
  let file=root.appendingPathComponent("中文 %20 #.txt");try Data("payload".utf8).write(to:file)
  let remote=DragFile(path:"/remote/中文 %20 #.txt",directory:false,size:7,connection:"fixture-token"),encoded=try JSONEncoder().encode(remote)
  let result=try FileDragPayload.decode([.init(file:encoded,url:nil),.init(file:nil,url:file.absoluteString),.init(file:encoded,url:nil)])
  check(result.count==2 && result[0].path==remote.path && result[0].connection=="fixture-token" && result[1].path==file.path && result[1].connection==nil)
  let malformed=[FileDragRepresentation(file:Data("invalid".utf8),url:file.absoluteString),.init(file:nil,url:"sftp://server/file"),.init(file:nil,url:"file://foreign-host/file")]
  for item in malformed{do{_ = try FileDragPayload.decode([item]);fatalError("expected malformed source refusal")}catch{}}
  for path in ["/","relative","/root/../file","/root//file","/root/\0file"]{do{_ = try FileDragPayload.decode([.init(file:JSONEncoder().encode(DragFile(path:path,directory:false,size:0,connection:nil)),url:nil)]);fatalError("expected invalid path")}catch{}}
  do{_ = try FileDragPayload.decode(Array(repeating:.init(file:encoded,url:nil),count:10001));fatalError("expected count bound")}catch{}
  do{_ = try FileDragPayload.decode([.init(file:Data(repeating:0,count:FileReferenceValidation.maximumBytes+1),url:nil)]);fatalError("expected byte bound")}catch{}
  let link=root.appendingPathComponent("link");try fm.createSymbolicLink(at:link,withDestinationURL:file)
  do{_ = try FileDragPayload.decode([.init(file:nil,url:link.absoluteString)]);fatalError("expected symbolic link refusal")}catch{}
  do{_ = try FileDragPayload.decode([]);fatalError("expected empty refusal")}catch{}
  print("PASS: private remote and public file URL drag payloads, Unicode/literal percent/hash, exact origin token and deduplication, malformed private data never falls back, URL/path/symlink/count/byte/empty refusal; own fixture files only")
 }
}
