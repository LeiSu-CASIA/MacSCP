import Cocoa
@main struct NativeFilePromiseTests {
 static func main()throws{
  NSApplication.shared.setActivationPolicy(.prohibited)
  let fm=FileManager.default,root=fm.temporaryDirectory.appendingPathComponent("native-promise-"+UUID().uuidString)
  let sources=root.appendingPathComponent("sources"),target=root.appendingPathComponent("received")
  for directory in [sources,target]{try fm.createDirectory(at:directory,withIntermediateDirectories:true)}
  defer{try? fm.removeItem(at:root)}
  let names=["单个文件 ' $.txt","second.bin"]
  let data=[Data("真实原生 promise receiver\n".utf8),Data(repeating:39,count:200000)]
  let work=OperationQueue();work.maxConcurrentOperationCount=2
  let state=NSLock();var submitted=0
  var providers=[RemoteDragPromiseProvider]()
  for (i,name) in names.enumerated(){
   let source=sources.appendingPathComponent(name);try data[i].write(to:source)
   let provider=RemoteDragPromiseProvider(file:DragFile(path:source.path,directory:false,size:UInt64(data[i].count),connection:"test-source-session")){delivery in
    state.lock();submitted+=1;state.unlock()
    delivery.job.factory={try SFTPClient(command:"/usr/libexec/sftp-server",arguments:[])}
    delivery.job.onCompletion={delivery.finish()}
    work.addOperation{delivery.job.execute({})}
   }
   providers.append(provider)
  }
  let pasteboard=NSPasteboard(name:NSPasteboard.Name("local.macscp.promise-test."+UUID().uuidString))
  defer{pasteboard.releaseGlobally()}
  guard pasteboard.writeObjects(providers) else{throw SFTPError.message("无法写入独立测试 pasteboard")}
  let internalData=pasteboard.pasteboardItems!.first!.data(forType:scpPasteboard)!
  let decoded=try JSONDecoder().decode(DragFile.self,from:internalData);precondition(decoded.connection=="test-source-session")
  precondition(submitted==0) // Merely inspecting internal metadata must not download.
  guard let receivers=pasteboard.readObjects(forClasses:[NSFilePromiseReceiver.self],options:nil) as? [NSFilePromiseReceiver],receivers.count==2 else{throw SFTPError.message("原生 receiver 无法读取两个 promise")}
  precondition(receivers.allSatisfy{$0.fileTypes==["public.data"] && $0.fileNames.isEmpty})
  precondition(submitted==0)
  // AppKit permits receivePromisedFiles only inside an actual native drag
  // callback. Do not fake this context or operate the user's Finder for a test.
  print("PASS: two native NSFilePromiseReceivers recognize dedicated pasteboard promises, source-session custom payload preserved, both advertise public.data, receiver inspection does not start downloads; fulfilment requires a real native drag callback and is separately covered at the provider delegate")
 }
}
