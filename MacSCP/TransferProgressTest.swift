import Foundation
@main struct TransferProgressTests {
 static func check(_ value:Bool,file:StaticString = #file,line:UInt = #line){precondition(value,file:file,line:line)}
 static func main()throws{
  let fm=FileManager.default,root=fm.temporaryDirectory.appendingPathComponent("transfer-progress-"+UUID().uuidString)
  try fm.createDirectory(at:root,withIntermediateDirectories:false);defer{try? fm.removeItem(at:root)}
  let source=root.appendingPathComponent("source.txt"),target=root.appendingPathComponent("target.txt"),raw=Data(String(repeating:"line\n",count:20000).utf8),converted=Data(String(repeating:"line\r\n",count:20000).utf8)
  try raw.write(to:source)
  let policy=TransferPolicy(verifyChecksum:true,text:TextTransferOptions(mode:.text,remote:.crlf))
  let job=TransferJob(up:true,source:source.path,destination:target.path,directory:false,size:UInt64(raw.count));job.policy=policy;job.factory={try SFTPClient(command:"/usr/libexec/sftp-server",arguments:[])}
  var prepared=false,active=[TransferProgressSnapshot]()
  job.execute{let value=job.progressSnapshot();if value.currentFile != nil && !value.estimated && value.total==UInt64(converted.count){prepared=true};if !value.finished{active.append(value)}}
  let final=job.progressSnapshot();check(prepared && !job.failed && final.total==UInt64(converted.count) && final.bytes==final.total && final.fraction==1 && !final.estimated)
  check(active.allSatisfy{$0.fraction.map{$0<1} ?? true});check(final.completedFiles==1 && final.totalFiles==1);check(try Data(contentsOf:target)==converted)
  let destination=root.appendingPathComponent("restored.txt"),stopped=TransferJob(up:true,source:source.path,destination:destination.path,directory:false,size:UInt64(raw.count));stopped.policy=policy;stopped.factory={try SFTPClient(command:"/usr/libexec/sftp-server",arguments:[])};var interrupted=false
  stopped.execute{let value=stopped.progressSnapshot();if !interrupted,value.bytes>0,!value.finished{interrupted=true;stopped.suspendForExit()}}
  check(interrupted && stopped.failed && stopped.finished && (stopped.progressSnapshot().fraction ?? 0)<1)
  let site=Session(name:"fixture",host:"progress.invalid",user:"fixture",port:22,key:""),record=try JSONDecoder().decode(TransferRecord.self,from:JSONEncoder().encode(stopped.snapshot(site:site)))
  let restored=try TransferJob.restore(record);restored.factory={try SFTPClient(command:"/usr/libexec/sftp-server",arguments:[])};restored.execute({});check(!restored.failed && restored.progressSnapshot().total==UInt64(converted.count) && restored.transferredBytes==UInt64(converted.count) && restored.reusedBytes>0)
  check(restored.endpointDescription?.contains("progress.invalid")==true)
  let completed=TransferRecord(id:UUID(),site:site,up:true,source:source.path,destination:target.path,directory:false,size:UInt64(raw.count),overwrite:false,resumes:[],completed:[target.path],created:[],policy:policy)
  let skip=try TransferJob.restore(completed);skip.factory={try SFTPClient(command:"/usr/libexec/sftp-server",arguments:[])};skip.execute({});let reused=skip.progressSnapshot();check(!skip.failed && reused.bytes==UInt64(converted.count) && reused.total==reused.bytes && reused.reused==reused.bytes && reused.speed==0)
  let shrinkSource=root.appendingPathComponent("shrink.txt"),shrinkTarget=root.appendingPathComponent("shrink-target.txt");try converted.write(to:shrinkSource)
  let shrink=TransferJob(up:true,source:shrinkSource.path,destination:shrinkTarget.path,directory:false,size:UInt64(converted.count));shrink.policy=TransferPolicy(text:TextTransferOptions(mode:.text));shrink.factory={try SFTPClient(command:"/usr/libexec/sftp-server",arguments:[])};shrink.execute({});check(!shrink.failed && shrink.progressSnapshot().total==UInt64(raw.count) && shrink.transferredBytes==UInt64(raw.count))
  let custom=TransferJob(up:true,source:source.path,destination:root.appendingPathComponent("custom.txt").path,directory:false,size:1);custom.policy=policy;custom.customAction="持续更新";custom.factory={try SFTPClient(command:"/usr/libexec/sftp-server",arguments:[])};custom.customOperation={client,point in try point();try client.upload(source,to:custom.destination)};custom.execute({});check(!custom.failed && custom.progressSnapshot().total==custom.transferredBytes && !custom.progressSnapshot().estimated)
  let binary=TransferJob(up:true,source:source.path,destination:root.appendingPathComponent("binary.txt").path,directory:false,size:1);binary.factory={try SFTPClient(command:"/usr/libexec/sftp-server",arguments:[])};binary.execute({});check(!binary.failed && binary.progressSnapshot().total==UInt64(raw.count) && binary.transferredBytes==UInt64(raw.count))
  let bad=TransferJob(up:true,source:"/owned/fixture",destination:"/owned/fixture",directory:false,size:1);bad.factory={throw SFTPError.message("owned failure")};bad.execute({});check(bad.failed && bad.progressSnapshot().fraction==0)
  print("PASS: real converted upload expansion/shrink totals, active progress below 100 until publication, serialized interrupted resume without double accounting, completed-text reuse uses wire length, endpoint metadata, custom totals and failure progress; owned SFTP stdio only")
 }
}
