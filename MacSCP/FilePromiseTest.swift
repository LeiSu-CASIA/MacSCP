import Cocoa
@main struct FilePromiseTests {
 static func main()throws{
  NSApplication.shared.setActivationPolicy(.prohibited)
  let fm=FileManager.default,root=fm.temporaryDirectory.appendingPathComponent("promise-"+UUID().uuidString)
  try fm.createDirectory(at:root,withIntermediateDirectories:false);defer{try? fm.removeItem(at:root)}
  let source=root.appendingPathComponent("source ' 中文.bin"),target=root.appendingPathComponent("Finder renamed file.bin")
  let data=Data((0..<200000).map{UInt8($0%251)});try data.write(to:source)
  let file=DragFile(path:source.path,directory:false,size:UInt64(data.count),connection:"original-session")
  var callbacks=0,lastError:Error?
  func delivery(_ url:URL,file item:DragFile?=nil)throws->PromisedFileDownload{
   let delivery=try PromisedFileDownload(file:item ?? file,destination:url){error in callbacks+=1;lastError=error}
   delivery.job.factory={try SFTPClient(command:"/usr/libexec/sftp-server",arguments:[])}
   delivery.job.onCompletion={delivery.finish()}
   precondition(!delivery.job.retryAllowed && delivery.job.recoveryRecord()==nil && delivery.job.column("destination")==url.path)
   return delivery
  }
  let first=try delivery(target)
  let attributes=try fm.attributesOfItem(atPath:first.staging.path);precondition((attributes[.posixPermissions] as! NSNumber).intValue==0o700)
  first.job.execute({});first.finish()
  first.job.cancel();precondition(first.job.column("progress")=="已完成")
  let actual=try Data(contentsOf:target)
  precondition(callbacks==1 && lastError==nil && actual==data && !fm.fileExists(atPath:first.staging.path))
  let conflict=try delivery(target);conflict.job.execute({});let unchanged=try Data(contentsOf:target)
  precondition(callbacks==2 && lastError != nil && conflict.job.failed && unchanged==data && !fm.fileExists(atPath:conflict.staging.path))
  let symlink=root.appendingPathComponent("link");try fm.createSymbolicLink(at:symlink,withDestinationURL:target)
  let linkConflict=try delivery(symlink);linkConflict.job.execute({})
  let retainedLink=try fm.destinationOfSymbolicLink(atPath:symlink.path);precondition(callbacks==3 && lastError != nil && retainedLink==target.path)
  let cancelled=try delivery(root.appendingPathComponent("cancelled"));let pending=BlockOperation{cancelled.job.execute({})};cancelled.job.operation=pending
  let suspended=OperationQueue();suspended.isSuspended=true;suspended.addOperation(pending);cancelled.job.cancel();cancelled.job.cancel()
  precondition(callbacks==4 && lastError != nil && !fm.fileExists(atPath:cancelled.staging.path));suspended.isSuspended=false;suspended.waitUntilAllOperationsAreFinished()
  precondition(callbacks==4)
  let running=try delivery(root.appendingPathComponent("cancelled-running"));running.job.speedLimit=65536
  running.job.execute{if running.job.transferredBytes>0{running.job.cancel()}}
  precondition(callbacks==5 && lastError != nil && !fm.fileExists(atPath:running.staging.path) && !fm.fileExists(atPath:running.destination.path))
  let directory=root.appendingPathComponent("folder source"),folderTarget=root.appendingPathComponent("folder result")
  try fm.createDirectory(at:directory.appendingPathComponent("child"),withIntermediateDirectories:true)
  try data.write(to:directory.appendingPathComponent("child/data.bin"));try Data().write(to:directory.appendingPathComponent("empty"))
  let folder=try delivery(folderTarget,file:DragFile(path:directory.path,directory:true,size:0,connection:"original-session"))
  folder.job.execute({});let copied=try Data(contentsOf:folderTarget.appendingPathComponent("child/data.bin"))
  precondition(callbacks==6 && lastError==nil && copied==data && !fm.fileExists(atPath:folder.staging.path))
  let missing=try delivery(root.appendingPathComponent("missing-result"),file:DragFile(path:root.appendingPathComponent("missing").path,directory:false,size:1,connection:"closed-session"));missing.job.execute({})
  precondition(callbacks==7 && lastError != nil && !fm.fileExists(atPath:missing.staging.path))
  var submissions=0
  let provider=RemoteDragPromiseProvider(file:file){_ in submissions+=1}
  precondition(submissions==0 && provider.delegate != nil && provider.fileType=="public.data")
  let payload=provider.pasteboardPropertyList(forType:scpPasteboard) as! Data
  let decoded=try JSONDecoder().decode(DragFile.self,from:payload);precondition(decoded.connection==file.connection && decoded.path==file.path)
  let writer=provider.delegate as! RemoteFilePromise
  precondition(writer.filePromiseProvider(provider,fileNameForType:provider.fileType)==source.lastPathComponent)
  // A real native promise callback, without changing the user's clipboard/Finder.
  let promised=root.appendingPathComponent("promised.bin")
  let activeProvider=RemoteDragPromiseProvider(file:file){item in
   submissions+=1;item.job.factory={try SFTPClient(command:"/usr/libexec/sftp-server",arguments:[])}
   item.job.onCompletion={item.finish()};item.job.execute({})
  }
  (activeProvider.delegate as! RemoteFilePromise).filePromiseProvider(activeProvider,writePromiseTo:promised){error in callbacks+=1;lastError=error}
  let promisedBytes=try Data(contentsOf:promised)
  precondition(submissions==1 && callbacks==8 && lastError==nil && promisedBytes==data)
  let contents=try fm.contentsOfDirectory(atPath:root.path);precondition(!contents.contains{$0.hasPrefix(".macscp-promise-")})
  print("PASS: native promise retains delegate/custom server metadata, lazy start, real SFTP file/directory fulfilment, Finder-assigned name, exclusive publication preserves files/symlinks, cancellation while queue suspended/running, missing source, exactly-once completion and temporary cleanup")
 }
}
