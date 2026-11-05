import Cocoa

// A separate promise is made for each dragged item. No file is downloaded merely
// by starting a drag, and the source session is captured before tabs can change.
final class RemoteDragPromiseProvider:NSFilePromiseProvider {
 let file:DragFile
 init(file:DragFile,submit:@escaping(PromisedFileDownload)->Void){
  self.file=file
  super.init()
  let writer=RemoteFilePromise(file:file,submit:submit)
  fileType=file.directory ? "public.folder" : "public.data"
  delegate=writer;userInfo=writer // AppKit's delegate reference is weak.
 }
 override func writableTypes(for pasteboard:NSPasteboard)->[NSPasteboard.PasteboardType]{super.writableTypes(for:pasteboard)+[scpPasteboard]}
 override func pasteboardPropertyList(forType type:NSPasteboard.PasteboardType)->Any?{
  type==scpPasteboard ? try? JSONEncoder().encode(file) : super.pasteboardPropertyList(forType:type)
 }
 override func writingOptions(forType type:NSPasteboard.PasteboardType,pasteboard:NSPasteboard)->NSPasteboard.WritingOptions{
  type==scpPasteboard ? [] : super.writingOptions(forType:type,pasteboard:pasteboard)
 }
}

final class RemoteFilePromise:NSObject,NSFilePromiseProviderDelegate {
 let file:DragFile
 let submit:(PromisedFileDownload)->Void
 private let queue=OperationQueue()
 init(file:DragFile,submit:@escaping(PromisedFileDownload)->Void){self.file=file;self.submit=submit;super.init();queue.name="MacSCP file promises";queue.maxConcurrentOperationCount=1}
 func filePromiseProvider(_ filePromiseProvider:NSFilePromiseProvider,fileNameForType fileType:String)->String{(file.path as NSString).lastPathComponent}
 func operationQueue(for filePromiseProvider:NSFilePromiseProvider)->OperationQueue{queue}
 func filePromiseProvider(_ filePromiseProvider:NSFilePromiseProvider,writePromiseTo url:URL,completionHandler:@escaping(Error?)->Void){
  do{let delivery=try PromisedFileDownload(file:file,destination:url,completion:completionHandler);submit(delivery)}catch{completionHandler(error)}
 }
}

final class PromisedFileDownload {
 let job:TransferJob
 let destination:URL
 let staging:URL
 private let completion:(Error?)->Void
 private let lock=NSLock()
 private var completed=false
 init(file:DragFile,destination:URL,completion:@escaping(Error?)->Void)throws{
  guard destination.isFileURL,!destination.lastPathComponent.isEmpty,destination.path != "/",file.connection != nil else{throw SFTPError.message("无效的拖拽下载目标")}
  self.destination=destination;self.completion=completion
  staging=destination.deletingLastPathComponent().appendingPathComponent(".macscp-promise-"+UUID().uuidString,isDirectory:true)
  try FileManager.default.createDirectory(at:staging,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
  let temporary=staging.appendingPathComponent(destination.lastPathComponent)
  job=TransferJob(up:false,source:file.path,destination:temporary.path,directory:file.directory,size:file.size)
  job.retryAllowed=false;job.displayDestination=destination.path
  job.afterTransfer={
   // Finder may choose a different filename for a duplicate. Honor the exact URL
   // supplied by AppKit; never replace an existing entry, even in a race.
   guard renamex_np(temporary.path,destination.path,UInt32(RENAME_EXCL))==0 else{throw NSError(domain:NSPOSIXErrorDomain,code:Int(errno),userInfo:[NSLocalizedDescriptionKey:"无法发布拖拽下载："+String(cString:strerror(errno))])}
  }
 }
 func finish(){
  lock.lock();guard !completed else{lock.unlock();return};completed=true;lock.unlock();job.onCompletion=nil
  let error:Error? = job.failed || !job.finished || job.column("progress")=="已取消" ? SFTPError.message(job.column("progress")) : nil
  try? FileManager.default.removeItem(at:staging)
  completion(error)
 }
 deinit{try? FileManager.default.removeItem(at:staging)}
}
