import Foundation
@main struct TransferTests {
 static func main()throws{
 let root=URL(fileURLWithPath:NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString);try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:root)}
 let src=root.appendingPathComponent("源目录");try FileManager.default.createDirectory(at:src.appendingPathComponent("子目录"),withIntermediateDirectories:true);let data=Data(repeating:77,count:500000);try data.write(to:src.appendingPathComponent("子目录/文件.bin"));try Data().write(to:src.appendingPathComponent("empty"))
 func job(_ up:Bool,_ a:URL,_ b:URL)->TransferJob{let j=TransferJob(up:up,source:a.path,destination:b.path,directory:true,size:0);j.factory={try SFTPClient(command:"/usr/libexec/sftp-server",arguments:[])};return j}
 let uploaded=root.appendingPathComponent("uploaded"),downloaded=root.appendingPathComponent("downloaded");let u=job(true,src,uploaded);u.execute({});precondition(u.finished && !u.failed);let d=job(false,uploaded,downloaded);d.execute({});precondition(d.finished && !d.failed);let actual=try Data(contentsOf:downloaded.appendingPathComponent("子目录/文件.bin"));precondition(actual==data)
 let conflict=job(true,src,uploaded);conflict.execute({});precondition(conflict.failed)
 let cancelled=job(true,src,root.appendingPathComponent("cancelled"));cancelled.cancel();cancelled.execute({});precondition(cancelled.finished && !FileManager.default.fileExists(atPath:root.appendingPathComponent("cancelled").path))
 let paused=job(true,src,root.appendingPathComponent("paused"));paused.setPaused(true);let done=DispatchSemaphore(value:0);DispatchQueue.global().async{paused.execute({});done.signal()};precondition(done.wait(timeout:.now()+0.2) == .timedOut);paused.setPaused(false);precondition(done.wait(timeout:.now()+10) == .success);precondition(!paused.failed)
 print("PASS: recursive Unicode tree upload/download, empty file, collision protection, cancellation and pause/resume")
 }
}
