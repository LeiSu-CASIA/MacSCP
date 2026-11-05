import Foundation
struct TransferPreset:Codable,Equatable {
 let id:UUID;var name:String;var preferences:TransferPreferences;var rule:TransferPresetRule?
 init(id:UUID=UUID(),name:String,preferences:TransferPreferences,rule:TransferPresetRule?=nil)throws{self.id=id;self.name=try TransferPresetLibrary.checkedName(name);self.preferences=try preferences.validated();self.rule=try rule?.validated()}
}
struct TransferPresetLibrary:Codable,Equatable {
 static let key="transferPresetLibrary",maximumCount=50,maximumBytes=2*1024*1024
 var version=1;private(set) var presets=[TransferPreset]();var selectedID:UUID?;var defaultPreferences:TransferPreferences?;var automaticSelectionEnabled:Bool?
 static func checkedName(_ value:String)throws->String{let name=value.trimmingCharacters(in:.whitespacesAndNewlines);guard !name.isEmpty,name.count<=60,name.utf8.count<=1024,!name.unicodeScalars.contains(where:{CharacterSet.controlCharacters.contains($0)}),!["默认设置","自定义"].contains(name) else{throw SFTPError.message("预设名称应为 1–60 个可见字符，不能使用默认设置或自定义")};return name}
 static func nameKey(_ name:String)->String{name.precomposedStringWithCanonicalMapping.folding(options:.caseInsensitive,locale:Locale(identifier:"en_US_POSIX"))}
 static func equivalent(_ a:TransferPreferences,_ b:TransferPreferences)->Bool{a.concurrency==b.concurrency && a.kibibytesPerSecond==b.kibibytesPerSecond && a.filePolicy==b.filePolicy}
 func validated()throws->Self{guard version==1,presets.count<=Self.maximumCount else{throw SFTPError.message("预设库版本不支持或数量超过 50")};if let value=defaultPreferences{_ = try value.validated()};var ids=Set<UUID>(),names=Set<String>();for preset in presets{guard try Self.checkedName(preset.name)==preset.name,ids.insert(preset.id).inserted,names.insert(Self.nameKey(preset.name)).inserted else{throw SFTPError.message("预设名称或标识重复，请修复预设库")};_ = try preset.preferences.validated();_ = try preset.rule?.validated()};if let selectedID=selectedID,!ids.contains(selectedID){throw SFTPError.message("预设库包含失效的选中项")};return self}
 func encoded()throws->Data{_ = try validated();let data=try JSONEncoder().encode(self);guard data.count<=Self.maximumBytes else{throw SFTPError.message("预设库超过 2 MiB")};return data}
 static func load(_ defaults:UserDefaults)throws->Self{guard defaults.object(forKey:key) != nil else{return Self()};guard let data=defaults.data(forKey:key),data.count<=maximumBytes else{throw SFTPError.message("预设库不是有效数据或超过 2 MiB")};return try JSONDecoder().decode(Self.self,from:data).validated()}
 func save(_ defaults:UserDefaults)throws{defaults.set(try encoded(),forKey:Self.key)}
 private mutating func change(_ edit:(inout Self)throws->Void)throws{var draft=self;try edit(&draft);_ = try draft.encoded();self=draft}
 @discardableResult mutating func add(name:String,preferences:TransferPreferences,rule:TransferPresetRule?=nil)throws->UUID{let preset=try TransferPreset(name:name,preferences:preferences,rule:rule);try change{$0.presets.append(preset);$0.selectedID=preset.id};return preset.id}
 mutating func update(_ id:UUID,preferences:TransferPreferences)throws{let value=try preferences.validated();try change{guard let index=$0.presets.firstIndex(where:{$0.id==id}) else{throw SFTPError.message("预设已经移除")};$0.presets[index].preferences=value;$0.selectedID=id}}
 mutating func setRule(_ id:UUID,rule:TransferPresetRule?)throws{let valid=try rule?.validated();try change{guard let index=$0.presets.firstIndex(where:{$0.id==id}) else{throw SFTPError.message("预设已经移除")};$0.presets[index].rule=valid}}
 func automaticPreset(_ context:TransferPresetContext)throws->TransferPreset?{guard automaticSelectionEnabled != false else{return nil};for preset in presets{if try preset.rule?.matches(context)==true{return preset}};return nil}
 @discardableResult mutating func mergePreset(_ imported:TransferPreset,replacing id:UUID?=nil)throws->UUID{let newID=id ?? UUID(),value=try TransferPreset(id:newID,name:imported.name,preferences:imported.preferences,rule:imported.rule);try change{if let id=id{guard let index=$0.presets.firstIndex(where:{$0.id==id}) else{throw SFTPError.message("要替换的预设已移除")};$0.presets[index]=value}else{$0.presets.append(value)}};return newID}
 mutating func rename(_ id:UUID,name:String)throws{let name=try Self.checkedName(name);try change{guard let index=$0.presets.firstIndex(where:{$0.id==id}) else{throw SFTPError.message("预设已经移除")};$0.presets[index].name=name}}
 mutating func remove(_ id:UUID)throws{try change{guard $0.presets.contains(where:{$0.id==id}) else{throw SFTPError.message("预设已经移除")};$0.presets.removeAll{$0.id==id};if $0.selectedID==id{$0.selectedID=nil}}}
 mutating func move(_ id:UUID,up:Bool)throws{try change{guard let index=$0.presets.firstIndex(where:{$0.id==id}) else{throw SFTPError.message("预设已经移除")};let target=index+(up ? -1 : 1);if $0.presets.indices.contains(target){$0.presets.swapAt(index,target)}}}
 func preset(_ id:UUID)->TransferPreset?{presets.first{$0.id==id}}
 func activeName(_ value:TransferPreferences)->String{if let id=selectedID,let preset=preset(id),Self.equivalent(preset.preferences,value){return preset.name};if Self.equivalent(value,defaultPreferences ?? TransferPreferences()){return "默认设置"};return "自定义"}
}
