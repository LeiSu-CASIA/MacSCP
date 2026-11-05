import Cocoa
@main struct ClipboardIntegrationTests {
 static func check(_ value:Bool){precondition(value)}
 static func main()throws{
  NSApplication.shared.setActivationPolicy(.prohibited)
  let fm=FileManager.default,root=fm.temporaryDirectory.appendingPathComponent("clipboard-adapter-"+UUID().uuidString)
  try fm.createDirectory(at:root,withIntermediateDirectories:false);defer{try? fm.removeItem(at:root)}
  let urls=[root.appendingPathComponent("中文 空格 %20 #.txt"),root.appendingPathComponent("second.txt")]
  for url in urls{try Data("fixture".utf8).write(to:url)}
  // Always an explicitly named disposable pasteboard; never access .general.
  let board=NSPasteboard(name:.init("macscp-private-clipboard-test-"+UUID().uuidString));defer{board.releaseGlobally()}
  let adapter=SystemFileClipboard(board),owner=UUID(),files=urls.map{DragFile(path:$0.path,directory:false,size:7,connection:nil)}
  try adapter.write(FileClipboardEnvelope.encode(owner:owner,files:files))
  let local=try adapter.read();precondition(local.urls==urls && local.payload != nil && board.pasteboardItems?.count==2)
  check(try FileClipboardEnvelope.files(local,owner:owner)?.map{$0.path}==urls.map{$0.path})
  check(try FileClipboardEnvelope.files(local,owner:UUID())?.map{$0.path}==urls.map{$0.path})
  let remote=[DragFile(path:"/fixture/remote file.txt",directory:false,size:8,connection:"private-fixture-token")]
  try adapter.write(FileClipboardEnvelope.encode(owner:owner,files:remote));let copied=try adapter.read()
  check(copied.urls.isEmpty && copied.text==remote[0].path && copied.payload != nil)
  check(board.pasteboardItems?.first?.types.contains(.fileURL)==false)
  check(try FileClipboardEnvelope.files(copied,owner:owner)?.first?.connection=="private-fixture-token")
  try adapter.write(FileClipboardSnapshot(text:root.path));let text=try adapter.read()
  check(text.payload==nil && text.urls.isEmpty && text.text==root.path)
  print("PASS: actual private named NSPasteboard adapter roundtrip, multiple file URLs/Chinese/literal percent/hash, same-instance payload and foreign-instance local fallback, remote-only internal format without fake local URL, path-only replacement clears old formats; no general clipboard, visible window, auth or network")
 }
}
