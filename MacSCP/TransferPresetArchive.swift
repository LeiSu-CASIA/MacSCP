import Foundation

struct TransferPresetArchive:Codable {
 var format="MacSCP.TransferPresets",version=1
 var presets:[TransferPreset]
 var defaultPreferences:TransferPreferences?,currentPreferences:TransferPreferences?,automaticSelectionEnabled:Bool?,selectedPresetName:String?
 static let maximumBytes=4*1024*1024,maximumCount=1000
 static func exportData(_ library:TransferPresetLibrary,current:TransferPreferences)throws->Data{
  _ = try library.validated();_ = try current.validated()
  let selected=library.selectedID.flatMap{library.preset($0)}.flatMap{TransferPresetLibrary.equivalent($0.preferences,current) ? $0.name : nil}
  let archive=Self(presets:library.presets,defaultPreferences:library.defaultPreferences,currentPreferences:current,automaticSelectionEnabled:library.automaticSelectionEnabled ?? true,selectedPresetName:selected)
  let encoder=JSONEncoder();encoder.outputFormatting=[.prettyPrinted,.sortedKeys];let data=try encoder.encode(archive);guard data.count<=maximumBytes else{throw SFTPError.message("预设归档超过 4 MiB")};return data
 }
 static func readFile(_ url:URL)throws->Data{let input:FTPUploadSource;do{input=try FTPUploadSource(url)}catch{throw SFTPError.message("无法读取预设文件，请选择可读的普通 JSON/INI 文件")};guard input.size<=maximumBytes else{throw SFTPError.message("预设文件超过 4 MiB")};let data=try input.file.read(upToCount:maximumBytes+1) ?? Data();try input.check();guard data.count<=maximumBytes else{throw SFTPError.message("预设文件超过 4 MiB")};return data}
 static func write(_ data:Data,to destination:URL)throws{
  guard data.count<=maximumBytes else{throw SFTPError.message("预设归档超过 4 MiB")}
  let temp=destination.deletingLastPathComponent().appendingPathComponent(".macscp-resume-"+UUID().uuidString),writer=try FTPDownloadTarget(destination:destination,temporary:temp,overwrite:true,resume:false,retainPartial:false)
  try writer.file.write(contentsOf:data);try writer.publish(expectedSize:UInt64(data.count),modified:UInt32(clamping:Int64(Date().timeIntervalSince1970)),permissions:0o600,preserveExistingPermissions:false)
 }
 static func decode(_ data:Data)throws->Self{
  guard data.count<=maximumBytes else{throw SFTPError.message("预设归档超过 4 MiB")}
  func keys(_ object:Any,_ allowed:Set<String>,_ path:String)throws{guard let dict=object as? [String:Any],Set(dict.keys).isSubset(of:allowed) else{throw SFTPError.message("预设归档包含未知字段或结构："+path)}}
  func preferences(_ object:Any,_ path:String)throws{try keys(object,["concurrency","kibibytesPerSecond","policy"],path);let d=object as! [String:Any];if let p=d["policy"],!(p is NSNull){try keys(p,["include","exclude","verifyChecksum","text"],path+".policy");if let text=(p as! [String:Any])["text"],!(text is NSNull){try keys(text,["mode","mask","remote","local","removeBOM","removeEOF"],path+".text")}}}
  let object=try JSONSerialization.jsonObject(with:data);try keys(object,["format","version","presets","defaultPreferences","currentPreferences","automaticSelectionEnabled","selectedPresetName"],"归档")
  let d=object as! [String:Any];guard let items=d["presets"] as? [Any],items.count<=maximumCount else{throw SFTPError.message("归档预设数量无效")}
  for item in items{try keys(item,["id","name","preferences","rule"],"预设");let row=item as! [String:Any];guard let p=row["preferences"] else{throw SFTPError.message("预设缺少传输设置")};try preferences(p,"预设");if let rule=row["rule"],!(rule is NSNull){try keys(rule,["enabled","host","user","local","remote"],"自动条件")}}
  for key in ["defaultPreferences","currentPreferences"]{if let p=d[key],!(p is NSNull){try preferences(p,key)}}
  let value=try JSONDecoder().decode(Self.self,from:data);guard value.format=="MacSCP.TransferPresets",value.version==1 else{throw SFTPError.message("不是受支持的 MacSCP 预设归档版本")}
  _ = try value.defaultPreferences?.validated();_ = try value.currentPreferences?.validated();if let name=value.selectedPresetName{_ = try TransferPresetLibrary.checkedName(name)};return value
 }
}

struct PresetImportCandidate {
 let id:Int,name:String,preset:TransferPreset?,issue:String?,notes:[String]
 var eligible:Bool{preset != nil && issue==nil}
}
struct PresetImportPlan {
 let format:String,candidates:[PresetImportCandidate],defaultPreferences:TransferPreferences?,currentPreferences:TransferPreferences?,automaticSelectionEnabled:Bool?,selectedPresetName:String?,notes:[String]
 static func read(_ data:Data,fileExtension:String="",fallback:TransferPreferences=TransferPreferences())throws->Self{
  guard data.count<=TransferPresetArchive.maximumBytes else{throw SFTPError.message("预设文件超过 4 MiB")}
  if fileExtension.lowercased()=="ini"{return try WinSCPPresetINI.read(data,fallback:fallback)}
  let archive=try TransferPresetArchive.decode(data);var ids=Set<UUID>(),names=Set<String>()
  let rows=archive.presets.enumerated().map{index,preset -> PresetImportCandidate in
   do{_ = try TransferPresetLibrary.checkedName(preset.name);_ = try preset.preferences.validated();_ = try preset.rule?.validated();guard ids.insert(preset.id).inserted,names.insert(TransferPresetLibrary.nameKey(preset.name)).inserted else{throw SFTPError.message("归档含重复名称或标识")};return PresetImportCandidate(id:index,name:preset.name,preset:preset,issue:nil,notes:[])}catch{return PresetImportCandidate(id:index,name:String(String.UnicodeScalarView(preset.name.unicodeScalars.filter{!CharacterSet.controlCharacters.contains($0)})).prefix(80).description,preset:nil,issue:error.localizedDescription,notes:[])}
  }
  guard !rows.isEmpty || archive.defaultPreferences != nil || archive.currentPreferences != nil || archive.automaticSelectionEnabled != nil else{throw SFTPError.message("预设归档没有可导入的内容")}
  return Self(format:"MacSCP JSON",candidates:rows,defaultPreferences:archive.defaultPreferences,currentPreferences:archive.currentPreferences,automaticSelectionEnabled:archive.automaticSelectionEnabled,selectedPresetName:archive.selectedPresetName,notes:[])
 }
}
enum PresetImportAction:String{case merge,copy}
struct PresetImportResult {let library:TransferPresetLibrary,current:TransferPreferences?,count:Int}
struct PresetImportSelection {
 let plan:PresetImportPlan,baseline:TransferPresetLibrary
 var checked=Set<Int>(),actions=[Int:PresetImportAction](),includeDefaults=false,restoreCurrent=false
 init(plan:PresetImportPlan,library:TransferPresetLibrary){self.plan=plan;baseline=library}
 func existing(_ row:PresetImportCandidate)->TransferPreset?{baseline.presets.first{TransferPresetLibrary.nameKey($0.name)==TransferPresetLibrary.nameKey(row.name)}}
 func label(_ row:PresetImportCandidate)->String{guard row.eligible else{return "不可导入"};return actions[row.id] == .copy ? "另存副本" : existing(row)==nil ? "新增" : "替换同名"}
 mutating func set(_ id:Int,on:Bool){guard let row=plan.candidates.first(where:{$0.id==id}),row.eligible else{return};if on{checked.insert(id)}else{checked.remove(id)}}
 mutating func selectAll(){checked=Set(plan.candidates.filter(\.eligible).map(\.id))}
 func apply(to current:TransferPresetLibrary)throws->PresetImportResult{
  guard current==baseline else{throw SFTPError.message("预设草稿已变化，请取消并重新打开导入预览")};guard !checked.isEmpty || includeDefaults || restoreCurrent else{throw SFTPError.message("请选择预设或要恢复的设置")}
  guard checked.isSubset(of:Set(plan.candidates.filter(\.eligible).map(\.id))) else{throw SFTPError.message("导入选择包含失效项目")}
  var result=current,mapping=[Int:UUID](),replaced=Set<UUID>()
  for row in plan.candidates where checked.contains(row.id){guard let value=row.preset,row.eligible else{throw SFTPError.message("所选预设不兼容")};var incoming=value;let original=existing(row)
   if actions[row.id] == .copy{var suffix=2;while result.presets.contains(where:{TransferPresetLibrary.nameKey($0.name)==TransferPresetLibrary.nameKey(incoming.name)}){let tail=" (\(suffix))";incoming.name=String(value.name.prefix(max(1,60-tail.count)))+tail;suffix+=1};mapping[row.id]=try result.mergePreset(incoming)}
   else{if let original=original{guard replaced.insert(original.id).inserted else{throw SFTPError.message("多个来源试图替换同一个预设")}};mapping[row.id]=try result.mergePreset(incoming,replacing:original?.id)}
  }
  if includeDefaults{if let defaults=plan.defaultPreferences{result.defaultPreferences=defaults};if let automatic=plan.automaticSelectionEnabled{result.automaticSelectionEnabled=automatic}}
  var chosen:TransferPreferences?
  if restoreCurrent{guard let value=plan.currentPreferences else{throw SFTPError.message("此文件未保存当前传输设置")};chosen=value;result.selectedID=nil
   if let name=plan.selectedPresetName,let row=plan.candidates.first(where:{TransferPresetLibrary.nameKey($0.name)==TransferPresetLibrary.nameKey(name)}),let id=mapping[row.id],let preset=result.preset(id),TransferPresetLibrary.equivalent(preset.preferences,value){result.selectedID=id}
  }
  _ = try result.encoded();return PresetImportResult(library:result,current:chosen,count:mapping.count)
 }
}
