import Foundation
enum SyncDirection:String,Codable {case upload,download,both}
enum SyncFileMode:String,Codable {case synchronize,mirror,timestamps}
struct SyncComparisonOptions:Codable,Equatable {
 var fileMode:SyncFileMode = .synchronize
 var modificationTime=true,size=false,checksum=false,existingOnly=false
 var timeTolerance:Double=2
 var timestampSameSizeOnly=false
 enum CodingKeys:String,CodingKey{case fileMode,modificationTime,size,checksum,existingOnly,timeTolerance,timestampSameSizeOnly}
 func validated(direction:SyncDirection)throws->Self {
  guard timeTolerance.isFinite,(0...300).contains(timeTolerance) else{throw SFTPError.message("同步时间容差应为 0–300 秒")}
  if fileMode == .timestamps{guard modificationTime,!size,!checksum,!existingOnly else{throw SFTPError.message("时间戳模式只比较修改时间，可另选仅同大小")}}else if timestampSameSizeOnly{throw SFTPError.message("仅同大小限制只用于时间戳模式")}
  if direction == .both{guard fileMode != .mirror,modificationTime,!size,!checksum else{throw SFTPError.message("双向同步使用时间比较；镜像、大小和内容比较仅用于单向同步")}}
  return self
 }
 var summary:String{if fileMode == .timestamps{return "仅同步修改时间 · 不传输内容、不删除 · \(timestampSameSizeOnly ? "仅相同大小" : "同名普通文件") · 容差 \(timeTolerance.formatted()) 秒"};let criteria=[modificationTime ? "时间（容差 \(timeTolerance.formatted()) 秒）" : nil,size ? "大小" : nil,checksum ? "SHA-256" : nil].compactMap{$0};return (fileMode == .mirror ? "镜像：源端为准，可覆盖较新的目标" : "普通同步")+" · "+(criteria.isEmpty ? "只比较缺失项目" : criteria.joined(separator:" + "))+(existingOnly ? " · 仅更新已有文件" : "")}
 // Compare at whole-second resolution, matching the metadata available from SFTP v3/FTP.
 func shouldTransfer(source:SyncNode,target:SyncNode)throws->Bool {
  if modificationTime{let delta=floor(source.modified)-floor(target.modified);if abs(delta)>timeTolerance{return fileMode == .mirror || delta>0}}
  if size,source.size != target.size{return true}
  if checksum{guard let a=source.checksum,let b=target.checksum else{throw SFTPError.message("所选内容比较缺少校验结果，请重新比较")};return a != b}
  return false
 }
}
extension SyncComparisonOptions {
 init(from decoder:Decoder)throws {
  let c=try decoder.container(keyedBy:CodingKeys.self)
  self.init(fileMode:try c.decodeIfPresent(SyncFileMode.self,forKey:.fileMode) ?? .synchronize,modificationTime:try c.decodeIfPresent(Bool.self,forKey:.modificationTime) ?? true,size:try c.decodeIfPresent(Bool.self,forKey:.size) ?? false,checksum:try c.decodeIfPresent(Bool.self,forKey:.checksum) ?? false,existingOnly:try c.decodeIfPresent(Bool.self,forKey:.existingOnly) ?? false,timeTolerance:try c.decodeIfPresent(Double.self,forKey:.timeTolerance) ?? 2,timestampSameSizeOnly:try c.decodeIfPresent(Bool.self,forKey:.timestampSameSizeOnly) ?? false)
 }
}
struct SyncSettings:Codable,Equatable {
 var direction:SyncDirection = .upload
 var comparison=SyncComparisonOptions()
 var cleanup=false
 func validated()throws->Self{_ = try comparison.validated(direction:direction);guard !cleanup || (direction != .both && comparison.fileMode != .timestamps) else{throw SFTPError.message("双向或时间戳同步不可清理独有项目")};return self}
 static func load(from defaults:UserDefaults)->Self?{guard let data=defaults.data(forKey:"syncOptions"),let saved=try? JSONDecoder().decode(Self.self,from:data) else{return nil};return try? saved.validated()}
 func save(to defaults:UserDefaults)throws{_ = try validated();defaults.set(try JSONEncoder().encode(self),forKey:"syncOptions")}
}

struct SyncCandidate {
 let relative:String;let local:SyncNode?;let remote:SyncNode?;var upload:Bool?;var selected:Bool;let typeConflict:Bool;var deletion=false;var mirror=false;var timestampOnly=false;var contents:SyncContents?=nil
 var directory:Bool{(deletion ? (upload == true ? remote : local) : (upload == false ? remote : local))?.directory ?? false}
 var size:UInt64{(deletion ? (upload == true ? remote : local) : (upload == false ? remote : local))?.size ?? 0}
 var replacing:Bool{upload == true ? remote != nil : local != nil}
 var executable:Bool{upload != nil && !typeConflict}
 var label:String{if deletion,let contents=contents{return (upload==true ? "删除远程（永久）" : "本地移到废纸篓")+" · 所选内容 · "+contents.summary};if deletion{return upload == true ? "删除远程（永久）"+(directory ? " · 整个目录" : "") : "本地移到废纸篓"+(directory ? " · 整个目录" : "")};if typeConflict{return "类型冲突：请先重命名或移走"};if timestampOnly{guard let up=upload,let source=up ? local : remote else{return "时间戳方向无效"};return (up ? "仅设置远程修改时间" : "仅设置本地修改时间")+" · "+SyncComparison.timeDescription(source.modified)};guard let up=upload else{return "内容冲突：请选择保留哪一侧"};return (up ? "↑ 本地 → 远程" : "↓ 远程 → 本地")+" · "+(replacing ? (mirror ? "镜像替换" : "替换") : "新增")+(contents.map{" · "+$0.summary} ?? "")} 
}
enum SyncComparison {
 static func candidates(local:[String:SyncNode],remote:[String:SyncNode],direction:SyncDirection,deleteExtraneous:Bool=false,allows:((String,Bool)->Bool)?=nil)->[SyncCandidate]{collect(local:local,remote:remote,direction:direction,deleteExtraneous:deleteExtraneous,allows:allows,comparison:nil,differences:[:])}
 private static func collect(local:[String:SyncNode],remote:[String:SyncNode],direction:SyncDirection,deleteExtraneous:Bool,allows:((String,Bool)->Bool)?,comparison:SyncComparisonOptions?,differences:[String:Bool])->[SyncCandidate]{var result=[SyncCandidate](),subtrees=[String](),excluded=[String]();let tolerance=comparison?.timeTolerance ?? 2;func delta(_ a:SyncNode,_ b:SyncNode)->Double{comparison==nil ? a.modified-b.modified : floor(a.modified)-floor(b.modified)};let keys=Set(local.keys).union(remote.keys).sorted();for path in keys{if subtrees.contains(where:{path.hasPrefix($0+"/")}){continue};let l=local[path],r=remote[path];let directory=l?.directory ?? r?.directory ?? false
 if excluded.contains(where:{path.hasPrefix($0+"/")}){continue}
 if allows?(path,directory)==false{if directory{excluded.append(path)};continue}
 if deleteExtraneous,direction != .both,(direction == .upload ? l==nil && r != nil : r==nil && l != nil){
  // A directory containing an excluded descendant must remain; plan only its permitted children.
  let target=direction == .upload ? remote : local
  if directory,let allows=allows,target.contains(where:{$0.key.hasPrefix(path+"/") && !allows($0.key,$0.value.directory)}){continue}
  result.append(SyncCandidate(relative:path,local:l,remote:r,upload:direction == .upload,selected:true,typeConflict:false,deletion:true));if directory{subtrees.append(path)};continue
 }
 if comparison?.existingOnly==true,(l==nil || r==nil){if directory{subtrees.append(path)};continue}
 let mismatch=l != nil && r != nil && l!.directory != r!.directory;if mismatch{result.append(SyncCandidate(relative:path,local:l,remote:r,upload:nil,selected:false,typeConflict:true));subtrees.append(path);continue};if l?.directory==true && r?.directory==true{continue};if let comparison=comparison,direction != .both {
  let source=direction == .upload ? l : r,target=direction == .upload ? r : l
  if source != nil {
   let differs=target==nil || differences[path]==true
   if differs{let item=SyncCandidate(relative:path,local:l,remote:r,upload:direction == .upload,selected:true,typeConflict:false,mirror:comparison.fileMode == .mirror);result.append(item);if item.directory{subtrees.append(path)}}
  };continue
 };if comparison==nil || comparison?.checksum==true{if let lh=l?.checksum,let rh=r?.checksum,lh==rh{continue}};let digestConflict=(comparison==nil || comparison?.checksum==true) && l?.checksum != nil && r?.checksum != nil && l?.checksum != r?.checksum;var up:Bool?;var conflict=false
 switch direction{case .upload:guard let l=l else{continue};if r==nil || (!l.directory && delta(l,r!)>tolerance){up=true}else if digestConflict,let r=r,abs(delta(l,r))<=tolerance{conflict=true}
 case .download:guard let r=r else{continue};if l==nil || (!r.directory && delta(r,l!)>tolerance){up=false}else if digestConflict,let l=l,abs(delta(l,r))<=tolerance{conflict=true}
 case .both:if l==nil{up=false}else if r==nil{up=true}else if delta(l!,r!)>tolerance{up=true}else if delta(r!,l!)>tolerance{up=false}else if l!.size != r!.size || digestConflict{conflict=true}}
 if up != nil || conflict{let item=SyncCandidate(relative:path,local:l,remote:r,upload:up,selected:up != nil,typeConflict:false);result.append(item);if item.directory{subtrees.append(path)}}};return result}
 static func permitted(_ path:String,directory:Bool,allows:((String,Bool)->Bool)?)->Bool {
  guard let allows=allows else{return true};if !allows(path,directory){return false}
  var parent="";for component in path.split(separator:"/").dropLast(){parent=parent.isEmpty ? String(component) : parent+"/"+component;if !allows(parent,true){return false}};return true
 }
 static func checksumPaths(_ snapshot:[String:SyncNode],allows:((String,Bool)->Bool)?)->Set<String>{Set(snapshot.compactMap{path,node in !node.directory && permitted(path,directory:false,allows:allows) ? path : nil})}
 static func timeDescription(_ seconds:TimeInterval)->String{guard seconds.isFinite else{return "无效时间"};let formatter=DateFormatter();formatter.locale=Locale(identifier:"en_US_POSIX");formatter.timeZone = .current;formatter.dateFormat="yyyy/MM/dd HH:mm:ss";return formatter.string(from:Date(timeIntervalSince1970:seconds))}
 private static func timestampCandidates(local:[String:SyncNode],remote:[String:SyncNode],settings:SyncSettings,allows:((String,Bool)->Bool)?=nil)throws->[SyncCandidate] {
  var result=[SyncCandidate]()
  for path in Set(local.keys).intersection(remote.keys).sorted(){
   guard var l=local[path],var r=remote[path],permitted(path,directory:l.directory || r.directory,allows:allows) else{continue}
   if l.directory != r.directory{result.append(SyncCandidate(relative:path,local:l,remote:r,upload:nil,selected:false,typeConflict:true,timestampOnly:true));continue}
   guard !l.directory,!r.directory else{continue}
   guard l.modified.isFinite,r.modified.isFinite else{throw SFTPError.message("时间戳无效："+path)}
   if settings.comparison.timestampSameSizeOnly,l.size != r.size{continue}
   let delta=floor(l.modified)-floor(r.modified);guard abs(delta)>settings.comparison.timeTolerance else{continue}
   let up=settings.direction == .both ? delta>0 : settings.direction == .upload
   let source=up ? l : r;guard floor(source.modified)>=0,floor(source.modified)<=Double(UInt32.max) else{throw SFTPError.message("源时间超出 SFTP v3 范围："+path)}
   // Cached content hashes must not introduce file reads into a metadata-only operation.
   l.checksum=nil;r.checksum=nil
   result.append(SyncCandidate(relative:path,local:l,remote:r,upload:up,selected:true,typeConflict:false,timestampOnly:true))
  };return result
 }
 static func plannedCandidates(local:[String:SyncNode],remote:[String:SyncNode],settings:SyncSettings,allows:((String,Bool)->Bool)?=nil,textDifferences:[String:Bool]=[:])throws->[SyncCandidate] {
  _ = try settings.validated()
  if settings.comparison.fileMode == .timestamps{return try timestampCandidates(local:local,remote:remote,settings:settings,allows:allows)}
  // Never turn a missing/failed checksum into an unchanged file.
  if settings.comparison.checksum {
   for (path,l) in local where !l.directory {guard let r=remote[path],!r.directory else{continue};if !permitted(path,directory:false,allows:allows){continue};guard l.checksum != nil,r.checksum != nil else{throw SFTPError.message("内容比较缺少校验结果："+path)}}
  }
  var differences=[String:Bool]()
  if settings.direction != .both {
   for (path,l) in local where !l.directory{guard let r=remote[path],!r.directory else{continue};if !permitted(path,directory:false,allows:allows){continue};guard l.modified.isFinite,r.modified.isFinite else{throw SFTPError.message("同步文件的时间无效："+path)};differences[path]=try settings.comparison.shouldTransfer(source:settings.direction == .upload ? l : r,target:settings.direction == .upload ? r : l)}
  }
  for (path,value) in textDifferences{if let l=local[path],let r=remote[path],!l.directory,!r.directory,!settings.comparison.modificationTime || abs(floor(l.modified)-floor(r.modified))<=settings.comparison.timeTolerance{differences[path]=value}}
  let rows=collect(local:local,remote:remote,direction:settings.direction,deleteExtraneous:settings.cleanup,allows:allows,comparison:settings.comparison,differences:differences)
  return settings.direction == .both ? rows.filter{!($0.upload==nil && !$0.typeConflict && textDifferences[$0.relative]==false)} : rows
 }
 @discardableResult static func resolve(_ candidate:inout SyncCandidate,upload:Bool)->Bool{
  guard !candidate.deletion,!candidate.typeConflict,let l=candidate.local,let r=candidate.remote else{return false}
  if candidate.timestampOnly{let source=upload ? l : r;guard !l.directory,!r.directory,source.modified.isFinite,floor(source.modified)>=0,floor(source.modified)<=Double(UInt32.max) else{return false}}
  candidate.upload=upload;candidate.selected=true;return true
 }
 static func verify(_ candidate:SyncCandidate,localRoot:String,remoteRoot:String,localSnapshot:[String:SyncNode],remoteSnapshot:[String:SyncNode],client:RemoteFileClient)throws{let path=candidate.relative;let local=URL(fileURLWithPath:localRoot).appendingPathComponent(path).path,remote=(remoteRoot=="/" ? "/" : remoteRoot+"/")+path
 func localNode()throws->SyncNode?{guard let v=try SyncDeletionPlan.localSignature(local) else{return nil};guard v.type != FileAttributeType.typeSymbolicLink.rawValue else{throw SFTPError.message("同步目标或源变成了符号链接")};return SyncNode(directory:v.type==FileAttributeType.typeDirectory.rawValue,size:v.size,modified:v.modified?.timeIntervalSince1970 ?? 0)}
 var currentL=try localNode(),attrs=try client.attributes(remote);if let attrs=attrs,attrs.mode&0o170000 == 0o120000{throw SFTPError.message("同步目标或源变成了符号链接")};var currentR=attrs.map{SyncNode(directory:$0.mode&0o170000 == 0o040000,size:$0.size,modified:Double($0.modified))}
 if candidate.local?.checksum != nil{currentL?.checksum=try StableChecksum.local(local)};if candidate.remote?.checksum != nil{currentR?.checksum=try client.checksum(remote)}
 func matches(_ a:SyncNode?,_ b:SyncNode?)->Bool{guard let a=a,let b=b else{return a==nil && b==nil};return a.directory==b.directory && (a.directory || a.size==b.size) && a.modified==b.modified && (a.checksum==nil && b.checksum==nil || a.checksum==b.checksum)}
 guard matches(currentL,candidate.local),matches(currentR,candidate.remote) else{throw SFTPError.message("预览后文件发生变化，请重新比较：\(path)")}
 if candidate.directory{let localSide=candidate.deletion ? candidate.upload == false : candidate.upload == true;let expected=(localSide ? localSnapshot : remoteSnapshot).filter{$0.key.hasPrefix(path+"/")};var actual=localSide ? try SyncPlanner.local(local,checkpoint:{try client.checkpoint?()}) : try SyncPlanner.remote(remote,client:client);if expected.values.contains(where:{$0.checksum != nil}){let paths=Set(expected.compactMap{key,value in value.checksum != nil ? String(key.dropFirst(path.count+1)) : nil});actual=localSide ? try SyncChecksums.local(actual,root:local,paths:paths) : try SyncChecksums.remote(actual,root:remote,client:client,paths:paths)};let mapped=Dictionary(uniqueKeysWithValues:actual.map{(path+"/"+$0.key,$0.value)});guard expected.count==mapped.count,expected.allSatisfy({key,value in matches(value,mapped[key])}) else{throw SFTPError.message("预览后目录内容发生变化，请重新比较：\(path)")}}
 }
}

// Prepared before the preview; execution never replaces it with a freshly accepted deletion list.
struct SyncDeletionPlan {
 let candidate:SyncCandidate,localRoot:String,remoteRoot:String
 let requestedLocalRoot:String,requestedRemoteRoot:String
 let localSnapshot:[String:SyncNode],remoteSnapshot:[String:SyncNode]
 let localAncestors:[(String,LocalTrashSignature?)],remoteAncestors:[(String,UInt32?)]
 let localItems:[LocalTrashItem];let remoteItems:[RemoteDeleteItem]
 static func localSignature(_ path:String)throws->LocalTrashSignature? {
  do{return try LocalTrashSignature.read(path)}catch let e as NSError{
   if e.domain==NSCocoaErrorDomain && [NSFileNoSuchFileError,NSFileReadNoSuchFileError].contains(e.code) || e.domain==NSPOSIXErrorDomain && e.code==2{return nil};throw e
  }
 }
 static func checkedRelative(_ path:String)throws {
  let parts=path.split(separator:"/",omittingEmptySubsequences:false)
  guard !parts.isEmpty,parts.allSatisfy({!$0.isEmpty && $0 != "." && $0 != ".."}),!path.contains("\0") else{throw SFTPError.message("无效的同步相对路径")}
 }
 static func join(_ root:String,_ relative:String)->String{(root=="/" ? "/" : root+"/")+relative}
 static func prepare(_ candidate:SyncCandidate,localRoot:String,remoteRoot:String,localSnapshot:[String:SyncNode],remoteSnapshot:[String:SyncNode],client:RemoteFileClient)throws->SyncDeletionPlan {
  try checkedRelative(candidate.relative)
  guard candidate.deletion,candidate.executable,candidate.upload == true ? candidate.local==nil && candidate.remote != nil : candidate.remote==nil && candidate.local != nil else{throw SFTPError.message("仅可清理源端不存在的目标项目")}
  let local=try LocalTrashPlan.canonicalDirectory(localRoot),remote=try client.canonical(remoteRoot)
  guard remote.hasPrefix("/"),!remote.contains("\0"),!remote.split(separator:"/").contains("..") else{throw SFTPError.message("无法确认远程同步目录")}
  var localAncestors=[(String,LocalTrashSignature?)](),remoteAncestors=[(String,UInt32?)]()
  // Capture local identities all the way to the volume root, then both relative parent chains.
  var cursor=""
  for part in [""]+local.split(separator:"/").map(String.init){cursor=part.isEmpty ? "/" : join(cursor,part);let node=try LocalTrashSignature.read(cursor);guard node.type==FileAttributeType.typeDirectory.rawValue else{throw SFTPError.message("本地同步路径包含非目录")};localAncestors.append((cursor,node))}
  let rootMode=try client.attributes(remote)?.mode
  guard rootMode.map({$0&0o170000 == 0o040000})==true else{throw SFTPError.message("远程同步目录不可用")};remoteAncestors.append((remote,rootMode))
  var localParent=local,remoteParent=remote
  for component in candidate.relative.split(separator:"/").dropLast(){
   localParent=join(localParent,String(component));remoteParent=join(remoteParent,String(component))
   let l=try localSignature(localParent),r=try client.attributes(remoteParent)
   guard l==nil || l?.type==FileAttributeType.typeDirectory.rawValue,r==nil || r!.mode&0o170000 == 0o040000 else{throw SFTPError.message("同步父路径包含符号链接或非目录")}
   localAncestors.append((localParent,l));remoteAncestors.append((remoteParent,r?.mode))
  }
  try SyncComparison.verify(candidate,localRoot:local,remoteRoot:remote,localSnapshot:localSnapshot,remoteSnapshot:remoteSnapshot,client:client)
  let target=join(candidate.upload == true ? remote : local,candidate.relative)
  var localItems=[LocalTrashItem](),remoteItems=[RemoteDeleteItem]()
  if candidate.upload == true {
   remoteItems=try RemoteOperations.deletionPlan([target],client:client).items
   let expected=Set([target]+(candidate.directory ? remoteSnapshot.keys.filter{$0.hasPrefix(candidate.relative+"/")} : []).map{join(remote,$0)})
   guard Set(remoteItems.map{$0.path})==expected else{throw SFTPError.message("准备清理时目录内容发生变化，请重新比较")}
  }else{
   let keys=[candidate.relative]+(candidate.directory ? localSnapshot.keys.filter{$0.hasPrefix(candidate.relative+"/")}.sorted() : [])
   localItems=try keys.map{let path=join(local,$0);return LocalTrashItem(path:path,signature:try LocalTrashSignature.read(path))}
  }
  let result=SyncDeletionPlan(candidate:candidate,localRoot:local,remoteRoot:remote,requestedLocalRoot:localRoot,requestedRemoteRoot:remoteRoot,localSnapshot:localSnapshot,remoteSnapshot:remoteSnapshot,localAncestors:localAncestors,remoteAncestors:remoteAncestors,localItems:localItems,remoteItems:remoteItems)
  try result.validate(client:client);return result
 }
 func validateParents(client:RemoteFileClient)throws {
  guard try LocalTrashPlan.canonicalDirectory(requestedLocalRoot)==localRoot,try client.canonical(requestedRemoteRoot)==remoteRoot else{throw SFTPError.message("预览后同步根目录被替换，请重新比较")}
  for (path,expected) in localAncestors {try client.checkpoint?();let current=try Self.localSignature(path);guard expected==nil ? current==nil : current.map({expected!.sameDirectory($0)})==true else{throw SFTPError.message("预览后本地父目录发生变化："+path)}}
  for (path,mode) in remoteAncestors {try client.checkpoint?();let current=try client.attributes(path);guard mode==nil ? current==nil : current?.mode==mode else{throw SFTPError.message("预览后远程父目录发生变化："+path)}}
 }
 func validateSourceAbsent(client:RemoteFileClient)throws {
  let path=Self.join(candidate.upload == true ? localRoot : remoteRoot,candidate.relative)
  let absent:Bool
  if candidate.upload == true{absent=try Self.localSignature(path)==nil}else{absent=try client.attributes(path)==nil}
  guard absent else{throw SFTPError.message("源端出现了同名项目，已停止清理："+candidate.relative)}
 }
 func validate(client:RemoteFileClient)throws {
  try validateParents(client:client);try validateSourceAbsent(client:client)
  try SyncComparison.verify(candidate,localRoot:localRoot,remoteRoot:remoteRoot,localSnapshot:localSnapshot,remoteSnapshot:remoteSnapshot,client:client)
  for item in localItems{try client.checkpoint?();guard try Self.localSignature(item.path)==item.signature else{throw SFTPError.message("预览后本地项目被替换："+item.path)}}
  for item in remoteItems{try client.checkpoint?();guard let now=try client.attributes(item.path),now.mode==item.mode,now.size==item.size,now.modified==item.modified else{throw SFTPError.message("预览后远程项目发生变化："+item.path)}}
 }
 func execute(client:RemoteFileClient,checkpoint:()throws->Void,trash:(URL)throws->Void=LocalTrashExecutor.moveToTrash)throws {
  try checkpoint();try validate(client:client);try checkpoint()
  if candidate.upload == false {
   try validateParents(client:client);try validateSourceAbsent(client:client)
   // A single top-level move preserves the directory hierarchy in the recycle bin.
   try trash(URL(fileURLWithPath:Self.join(localRoot,candidate.relative)));return
  }
  for item in remoteItems {
   try checkpoint();try validateParents(client:client);try validateSourceAbsent(client:client)
   guard let now=try client.attributes(item.path),now.mode==item.mode,item.directory || now.size==item.size && now.modified==item.modified else{throw SFTPError.message("清理前远程项目发生变化："+item.path)}
   if item.directory{guard try client.list(item.path,maximumEntries:1).isEmpty else{throw SFTPError.message("目录中出现新项目，已停止清理："+item.path)}}
   try checkpoint();try client.remove(item.path,directory:item.directory)
  }
 }
}
