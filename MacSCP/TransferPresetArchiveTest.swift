import Foundation
@main struct TransferPresetArchiveTests {
 static func check(_ value:Bool,file:StaticString = #file,line:UInt = #line){precondition(value,file:file,line:line)}
 static func refused(_ action:()throws->Void){do{try action();fatalError("invalid import accepted")}catch{}}
 static func main()throws{
  let root=FileManager.default.temporaryDirectory.appendingPathComponent("preset-archive-"+UUID().uuidString);try FileManager.default.createDirectory(at:root,withIntermediateDirectories:false);defer{try? FileManager.default.removeItem(at:root)}
  let current=TransferPreferences(concurrency:2),incoming=TransferPreferences(concurrency:5,kibibytesPerSecond:128,policy:TransferPolicy(include:"*.txt",exclude:"*.tmp",verifyChecksum:true,text:TextTransferOptions(mode:.automatic,remote:.crlf,removeBOM:true)))
  var local=TransferPresetLibrary();let original=try local.add(name:"代码",preferences:current),untouched=try local.add(name:"图片",preferences:TransferPreferences());local.selectedID=original;local.defaultPreferences=current
  var source=TransferPresetLibrary();let sourceID=try source.add(name:"代码",preferences:incoming,rule:TransferPresetRule(enabled:true,host:"*.fixture.invalid",remote:"/srv/project/"));_ = try source.add(name:"数据",preferences:TransferPreferences(concurrency:4));source.selectedID=sourceID;source.defaultPreferences=TransferPreferences(concurrency:6);source.automaticSelectionEnabled=false
  let data=try TransferPresetArchive.exportData(source,current:incoming),archive=try TransferPresetArchive.decode(data);check(archive.presets==source.presets && archive.currentPreferences==incoming && archive.selectedPresetName=="代码")
  let plan=try PresetImportPlan.read(data),base=local
  var selection=PresetImportSelection(plan:plan,library:local);check(selection.checked.isEmpty);selection.selectAll();let result=try selection.apply(to:local)
  check(result.library.presets.map(\.name)==["代码","图片","数据"] && result.library.preset(original)?.preferences==incoming && result.library.preset(untouched)==local.preset(untouched));check(result.current==nil && result.library.selectedID==original && result.library.defaultPreferences==current)
  check(result.library.presets.last!.id != source.presets.last!.id && result.library.presets[0].id==original)
  selection.includeDefaults=true;selection.restoreCurrent=true;let full=try selection.apply(to:local);check(full.library.defaultPreferences==source.defaultPreferences && full.library.automaticSelectionEnabled==false && full.current==incoming && full.library.selectedID==original)
  var copied=PresetImportSelection(plan:plan,library:local);copied.set(0,on:true);copied.actions[0] = .copy;copied.restoreCurrent=true;let copy=try copied.apply(to:local);check(copy.library.presets.map(\.name)==["代码","图片","代码 (2)"] && copy.library.preset(original)?.preferences==current && copy.library.selectedID==copy.library.presets.last!.id)
  try local.rename(untouched,name:"另一个名字");refused{_ = try selection.apply(to:local)};check(base.presets[1].name=="图片")
  copied.checked=[999];refused{_ = try copied.apply(to:base)}
  var fullLibrary=TransferPresetLibrary();for i in 0..<50{_ = try fullLibrary.add(name:"项目 \(i)",preferences:current)};var over=PresetImportSelection(plan:plan,library:fullLibrary);over.set(0,on:true);let before=fullLibrary;refused{_ = try over.apply(to:fullLibrary)};check(fullLibrary==before)
  let file=root.appendingPathComponent("presets.json");try TransferPresetArchive.write(data,to:file);check(try TransferPresetArchive.readFile(file)==data);check((try FileManager.default.attributesOfItem(atPath:file.path)[.posixPermissions] as! NSNumber).intValue==0o600)
  try FileManager.default.setAttributes([.posixPermissions:0o644],ofItemAtPath:file.path);try TransferPresetArchive.write(data,to:file);check((try FileManager.default.attributesOfItem(atPath:file.path)[.posixPermissions] as! NSNumber).intValue==0o600)
  let link=root.appendingPathComponent("link.json");try FileManager.default.createSymbolicLink(at:link,withDestinationURL:file);refused{_ = try TransferPresetArchive.readFile(link)};refused{try TransferPresetArchive.write(Data("changed".utf8),to:link)};check(try Data(contentsOf:file)==data)
  var json=try JSONSerialization.jsonObject(with:data) as! [String:Any];json["password"]="not-a-supported-field";refused{_ = try PresetImportPlan.read(JSONSerialization.data(withJSONObject:json))};json.removeValue(forKey:"password");json["version"]=99;refused{_ = try PresetImportPlan.read(JSONSerialization.data(withJSONObject:json))}
  refused{_ = try PresetImportPlan.read(Data(repeating:32,count:TransferPresetArchive.maximumBytes+1))}
  // Official CopyParamList / numbered sections and transfer enum fields.
  let ini="""
  [Configuration\\Interface\\CopyParam]
  CopyParamList=6
  [Configuration\\Interface\\CopyParam\\0]
  Name=%EF%BB%BF%E6%96%87%E6%9C%AC
  TransferMode=2
  Masks=*.txt;*.csv
  IncludeFileMask=*.* | *.tmp
  RemoveBOM=1
  RemoveCtrlZ=1
  CPSLimit=2048
  HasRule=1
  HostName=*.fixture.invalid
  UserName=fixture
  LocalDirectory=C:%5CData%5C*
  RemoteDirectory=/srv/project/
  [Configuration\\Interface\\CopyParam\\1]
  Name=rights
  PreserveRights=1
  [Configuration\\Interface\\CopyParam\\2]
  Name=limit
  CPSLimit=1500
  [Configuration\\Interface\\CopyParam\\3]
  Name=unknown-mode
  TransferMode=9
  [Configuration\\Interface\\CopyParam\\4]
  Name=unknown-command
  PostLoginCommands=do-not-execute
  [Configuration\\Interface\\CopyParam\\5]
  Name=legacy
  TransferMode=1
  ExcludeFileMask=*.bak
  NegativeExclude=0
  [Sessions\\private]
  Password=fixture-secret-must-not-export
  RemoteCommand=fixture-command-must-not-execute
  """
  let migrated=try PresetImportPlan.read(Data(ini.utf8),fileExtension:"ini",fallback:TransferPreferences(concurrency:7))
  check(migrated.candidates.count==6 && migrated.candidates.filter(\.eligible).count==2)
  let text=migrated.candidates[0].preset!;check(text.name=="文本" && text.preferences.concurrency==7 && text.preferences.kibibytesPerSecond==2 && text.preferences.filePolicy.include=="*" && text.preferences.filePolicy.exclude=="*.tmp")
  check(text.preferences.filePolicy.text?.mode == .automatic && text.preferences.filePolicy.text?.removeBOM==true && text.rule?.enabled==false && text.rule?.local=="C:\\Data\\*")
  var migrate=PresetImportSelection(plan:migrated,library:TransferPresetLibrary());migrate.selectAll();let imported=try migrate.apply(to:migrate.baseline);check(imported.count==2 && imported.library.presets[1].preferences.filePolicy.exclude=="*.bak")
  let exported=try TransferPresetArchive.exportData(imported.library,current:current);check(!String(decoding:exported,as:UTF8.self).contains("fixture-secret"))
  refused{_ = try PresetImportPlan.read(Data("[Configuration\\Interface\\CopyParam]\nCopyParamList=-1".utf8),fileExtension:"ini")}
  let duplicated=ini.replacingOccurrences(of:"TransferMode=2",with:"TransferMode=2\nTransferMode=1");let badRows=try PresetImportPlan.read(Data(duplicated.utf8),fileExtension:"ini");check(!badRows.candidates[0].eligible)
  let utf16=Data([255,254])+ini.data(using:.utf16LittleEndian)!;check(try PresetImportPlan.read(utf16,fileExtension:"ini").candidates[0].name=="文本")
  print("PASS: preset archive/order/mode/rule/default/current roundtrip, opt-in restore, name-based merge with stable local IDs, copy naming, capacity/stale/unknown refusal and rollback; private atomic file export/read/symlink refusal; WinSCP numbered INI/UTF-8/UTF-16/modes/masks/limit/BOM/EOF and incompatible rows; session secrets not exported")
 }
}
