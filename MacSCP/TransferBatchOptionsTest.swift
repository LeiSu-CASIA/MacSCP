import Foundation
@main struct TransferBatchOptionsTests {
 static func check(_ value:Bool){precondition(value)}
 static func main()throws{
  check(try TransferBatchOptions.directory(" /home/中文 目录/ ")=="/home/中文 目录/")
  for invalid in ["","relative","/one\ntwo","/zero\0bad"]{do{_ = try TransferBatchOptions.directory(invalid);fatalError("expected invalid directory")}catch{}}
  let site=Session(name:"fixture",host:"batch.invalid",user:"fixture",port:22,key:""),job=TransferJob(up:true,source:"/source/file",destination:"/target/file",directory:false,size:1)
  job.recoverySite=site;job.overrideSpeedLimit=0
  let snapshot=job.snapshot(site:site),record=job.recoveryRecord()!
  check(snapshot.overrideSpeedLimit==0 && record.overrideSpeedLimit==0)
  let restored=try TransferJob.restore(JSONDecoder().decode(TransferRecord.self,from:JSONEncoder().encode(snapshot)));check(restored.overrideSpeedLimit==0)
  job.overrideSpeedLimit=128*1024;check(try TransferJob.restore(job.snapshot(site:site)).overrideSpeedLimit==128*1024)
  var invalid=job.snapshot(site:site);invalid.overrideSpeedLimit=1073741825;do{_ = try invalid.validated();fatalError("expected invalid speed")}catch{}
  var json=try JSONSerialization.jsonObject(with:JSONEncoder().encode(record)) as! [String:Any];json.removeValue(forKey:"overrideSpeedLimit")
  let legacy=try JSONDecoder().decode(TransferRecord.self,from:JSONSerialization.data(withJSONObject:json));check(try TransferJob.restore(legacy).overrideSpeedLimit==nil)
  print("PASS: batch directory validation, explicit unlimited/nonzero independent speed snapshot and ordinary recovery roundtrip, upper bound and legacy nil inheritance; no filesystem/network")
 }
}
