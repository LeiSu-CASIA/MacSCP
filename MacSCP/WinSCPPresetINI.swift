import Foundation

// Only named CopyParam sections are retained. Session/credential sections are never parsed into presets.
enum WinSCPPresetINI {
 private static let base="configuration\\interface\\copyparam"
 private struct Section {var values=[String:String]();var duplicate=false}
 static func read(_ data:Data,fallback:TransferPreferences=TransferPreferences())throws->PresetImportPlan{
  let text=try WinSCPSiteINI.text(data);var sections=[String:Section](),section=""
  for line in text.split(whereSeparator:\.isNewline){let row=line.trimmingCharacters(in:.whitespaces);if row.isEmpty || row.hasPrefix(";") || row.hasPrefix("#"){continue}
   if row.hasPrefix("["),row.hasSuffix("]"){section=String(row.dropFirst().dropLast()).lowercased();if section==base || section.hasPrefix(base+"\\"){if sections[section] != nil{sections[section]!.duplicate=true}else{sections[section]=Section()}};continue}
   guard section==base || section.hasPrefix(base+"\\") else{continue};guard let equal=row.firstIndex(of:"=") else{throw SFTPError.message("预设 INI 含无效行")};let key=row[..<equal].trimmingCharacters(in:.whitespaces).lowercased(),value=String(row[row.index(after:equal)...]);if sections[section]!.values[key] != nil{sections[section]!.duplicate=true};sections[section]!.values[key]=value
  }
  guard let parent=sections[base],!parent.duplicate,let count=Int(parent.values["copyparamlist"] ?? ""),(1...TransferPresetArchive.maximumCount).contains(count) else{throw SFTPError.message("未找到可迁移的命名预设列表；内置预设或无 CopyParamList 的片段不作推测")}
  let rows=(0..<count).map{index -> PresetImportCandidate in
   var name="预设 \(index+1)",notes=["WinSCP 的站点换行、时间/权限、加密及全局续传选项不随命名预设迁移；在本机使用前请核对。"]
   do{guard let entry=sections[base+"\\"+String(index)],!entry.duplicate else{throw SFTPError.message("预设段缺失或含重复字段")};name=try string(entry.values,"name",name);let preset=try convert(entry.values,name:name,fallback:fallback,notes:&notes);return PresetImportCandidate(id:index,name:preset.name,preset:preset,issue:nil,notes:notes)}catch{return PresetImportCandidate(id:index,name:String(name.prefix(80)),preset:nil,issue:error.localizedDescription,notes:notes)}
  }
  return PresetImportPlan(format:"WinSCP INI",candidates:rows,defaultPreferences:nil,currentPreferences:nil,automaticSelectionEnabled:nil,selectedPresetName:nil,notes:["仅迁移命名传输预设，不读取站点、密码、私钥或命令。默认配置和当前选择由本机保留。"])
 }
 private static func integer(_ values:[String:String],_ key:String,_ fallback:Int)throws->Int{guard let raw=values[key] else{return fallback};guard let value=Int(raw.trimmingCharacters(in:.whitespaces)) else{throw SFTPError.message("字段 \(key) 不是整数")};return value}
 private static func boolean(_ values:[String:String],_ key:String,_ fallback:Bool)throws->Bool{let value=try integer(values,key,fallback ? 1 : 0);guard value==0 || value==1 else{throw SFTPError.message("字段 \(key) 不是 0/1")};return value==1}
 private static func string(_ values:[String:String],_ key:String,_ fallback:String="")throws->String{try values[key].map{try WinSCPSiteINI.decode($0)} ?? fallback}
 private static func mask(_ raw:String)throws->String{guard !raw.contains(where:{"[],<>".contains($0)}) else{throw SFTPError.message("此文件掩码含当前不能准确迁移的字符组、逗号或大小/时间条件")};let text=raw.replacingOccurrences(of:"\\",with:"/");return try text.split(separator:";",omittingEmptySubsequences:false).map{part in let item=part.trimmingCharacters(in:.whitespaces);if item=="*.*"{return "*"};guard item != "*." else{throw SFTPError.message("无扩展名掩码不能准确迁移")};if item.hasPrefix("./"){return String(item.dropFirst(2))};guard !String(item.hasSuffix("/") ? item.dropLast() : Substring(item)).contains("/") else{throw SFTPError.message("路径掩码需明确使用 ./ 相对根目录，不能推测绝对路径")};return item}.joined(separator:";")}
 private static func convert(_ values:[String:String],name:String,fallback:TransferPreferences,notes:inout[String])throws->TransferPreset{
  let known:Set<String>=["name","addxtodirectories","masks","filenamecase","preservereadonly","preservetime","preservetimedirs","preserverights","ignorepermerrors","text","transfermode","resumesupport","resumethreshold","replaceinvalidchars","localinvalidchars","calculatesize","includefilemask","excludefilemask","negativeexclude","cleararchive","removectrlz","removebom","cpslimit","neweronly","encryptnewfiles","excludehiddenfiles","excludeemptydirectories","hasrule","hostname","username","remotedirectory","localdirectory"]
  guard Set(values.keys).isSubset(of:known) else{throw SFTPError.message("此预设含未支持字段，未静默忽略")}
  for key in ["preservereadonly","preservetimedirs","preserverights","ignorepermerrors","cleararchive","neweronly","excludehiddenfiles","excludeemptydirectories"]{guard try !boolean(values,key,false) else{throw SFTPError.message("设置 \(key) 尚不能迁移")}}
  guard try integer(values,"filenamecase",0)==0 else{throw SFTPError.message("文件名大小写转换尚不能迁移")}
  guard try boolean(values,"preservetime",true),try boolean(values,"calculatesize",true) else{throw SFTPError.message("此预设关闭了保留时间或总量计算，当前不能准确迁移")}
  let modeNumber=try integer(values,"transfermode",0);guard (0...2).contains(modeNumber) else{throw SFTPError.message("未知传输模式")}
  let speed=try integer(values,"cpslimit",0);guard speed>=0,speed%1024==0,speed/1024<=1048576 else{throw SFTPError.message("源限速不能按当前 KiB/s 精度表示")}
  var include="",exclude=""
  if let _=values["includefilemask"]{let raw=try string(values,"includefilemask"),parts=raw.split(separator:"|",omittingEmptySubsequences:false);guard parts.count<=2 else{throw SFTPError.message("复杂包含/排除掩码不能准确迁移")};include=try mask(String(parts[0]));if parts.count==2{exclude=try mask(String(parts[1]))}}
  else if values["excludefilemask"] != nil{let old=try mask(string(values,"excludefilemask"));if try boolean(values,"negativeexclude",false){include=old}else{exclude=old}}
  var text=TextTransferOptions(mode:TransferMode.allCases[modeNumber],remote:.lf,local:.lf,removeBOM:try boolean(values,"removebom",false),removeEOF:try boolean(values,"removectrlz",false))
  if values["masks"] != nil{text.mask=try mask(string(values,"masks"))}else{text.mask="*.*html;*.htm;*.txt;*.php;*.php3;*.cgi;*.c;*.cpp;*.h;*.pas;*.bas;*.tex;*.pl;*.js;.htaccess;*.xtml;*.css;*.cfg;*.ini;*.sh;*.xml"}
  var rule:TransferPresetRule?
  if try boolean(values,"hasrule",false){var r=TransferPresetRule(enabled:true,host:try string(values,"hostname"),user:try string(values,"username"),local:try string(values,"localdirectory"),remote:try string(values,"remotedirectory"));guard ![r.host,r.user,r.local,r.remote].contains(where:{$0.contains("<") || $0.contains(">")}) else{throw SFTPError.message("自动规则含未支持的约束")}
   if r.local.contains("\\") || r.local.dropFirst().hasPrefix(":") || r.remote.contains("\\"){r.enabled=false;notes.append("Windows 风格目录条件已原样保留，自动规则暂时关闭；请在主设置中修改为本机/服务器路径后启用。")};rule=try r.validated()
  }
  if name.contains("&"){notes.append("名称中的 WinSCP 菜单助记符 & 按普通字符保留。") }
  notes.append("文本换行初始为 LF；WinSCP 的远程换行取决于站点环境，请核对。并行数保留本机值 \(fallback.concurrency)。")
  let policy=try TransferPolicy(include:include,exclude:exclude,verifyChecksum:false,text:text).validated(),preferences=TransferPreferences(concurrency:fallback.concurrency,kibibytesPerSecond:speed/1024,policy:policy)
  return try TransferPreset(name:name,preferences:preferences,rule:rule)
 }
}
