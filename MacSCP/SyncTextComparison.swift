import Foundation

enum SyncTextComparison {
 static func differences(local:[String:SyncNode],remote:[String:SyncNode],localRoot:String,remoteRoot:String,policy:TransferPolicy,settings:SyncSettings,client:RemoteFileClient,allows:((String,Bool)->Bool)?=nil,checkpoint:@escaping()throws->Void = {})throws->[String:Bool]{
  guard let options=policy.text,options.mode != .binary,settings.comparison.fileMode != .timestamps,settings.direction == .both || settings.comparison.size || settings.comparison.checksum else{return[:]}
  var result=[String:Bool]()
  for path in Set(local.keys).intersection(remote.keys).sorted(){
   try checkpoint();guard let l=local[path],let r=remote[path],!l.directory,!r.directory,SyncComparison.permitted(path,directory:false,allows:allows),try options.applies(path) else{continue}
   let delta=floor(l.modified)-floor(r.modified)
   if settings.comparison.modificationTime,abs(delta)>settings.comparison.timeTolerance{continue}
   if settings.direction == .both,l.size==r.size{continue}
   let lp=SyncDeletionPlan.join(localRoot,path),rp=SyncDeletionPlan.join(remoteRoot,path)
   func expected(_ up:Bool)throws->(UInt64,String){
    if up{return try TextTransfer.withSnapshot(lp,options:options,upload:true,checkpoint:checkpoint){url,_ in let a=try FileManager.default.attributesOfItem(atPath:url.path);return((a[.size] as! NSNumber).uint64Value,try StableChecksum.local(url.path,checkpoint:checkpoint))}}
    return try TextTransfer.withRemoteSnapshot(rp,client:client,verify:policy.verifyChecksum,checkpoint:checkpoint){raw,_ in try TextTransfer.withSnapshot(raw.path,options:options,upload:false,checkpoint:checkpoint){url,_ in let a=try FileManager.default.attributesOfItem(atPath:url.path);return((a[.size] as! NSNumber).uint64Value,try StableChecksum.local(url.path,checkpoint:checkpoint))}}
   }
   if settings.direction == .both{let uploaded=try expected(true),remoteHash=try r.checksum ?? client.checksum(rp);if uploaded.0==r.size && uploaded.1==remoteHash{result[path]=false;continue};let downloaded=try expected(false),localHash=try l.checksum ?? StableChecksum.local(lp,checkpoint:checkpoint);result[path] = !(downloaded.0==l.size && downloaded.1==localHash)}
   else{let up=settings.direction == .upload,converted=try expected(up),target=up ? r : l;var differs=settings.comparison.size && converted.0 != target.size
    if !differs,settings.comparison.checksum{let digest=try target.checksum ?? (up ? client.checksum(rp) : StableChecksum.local(lp,checkpoint:checkpoint));differs=converted.1 != digest};result[path]=differs
   }
  };return result
 }
}
