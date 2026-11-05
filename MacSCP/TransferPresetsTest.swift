import Foundation
@main struct TransferPresetsTests {
 static func check(_ value:Bool,file:StaticString = #file,line:UInt = #line){precondition(value,file:file,line:line)}
 static func refused(_ action:()throws->Void){do{try action();fatalError("invalid preset accepted")}catch{}}
 static func main()throws{
  if CommandLine.arguments.count==4 && CommandLine.arguments[1]=="--read-suite"{let suite=CommandLine.arguments[2];guard suite.hasPrefix("macscp-presets-test-"),let id=UUID(uuidString:CommandLine.arguments[3]),let defaults=UserDefaults(suiteName:suite) else{fatalError("invalid fixture")};let library=try TransferPresetLibrary.load(defaults);check(library.selectedID==id && library.preset(id)?.name=="数据分析" && library.preset(id)?.rule?.enabled==true && library.preset(id)?.rule?.remote=="/srv/project/" && library.automaticSelectionEnabled==false);print("PASS: persisted preset library reopened in fresh process");return}
  let suite="macscp-presets-test-"+UUID().uuidString,defaults=UserDefaults(suiteName:suite)!;defer{defaults.removePersistentDomain(forName:suite)}
  var library=TransferPresetLibrary();check(try TransferPresetLibrary.load(defaults).presets.isEmpty)
  let value=TransferPreferences(concurrency:5,kibibytesPerSecond:128,policy:TransferPolicy(include:"*.csv;**/*.txt",exclude:".git/;*.tmp",verifyChecksum:true))
  let id=try library.add(name:" 数据分析 ",preferences:value,rule:TransferPresetRule(enabled:true,host:"*.invalid",remote:"/srv/project/"));check(library.preset(id)?.name=="数据分析" && library.activeName(value)=="数据分析")
  let second=try library.add(name:"备份",preferences:TransferPreferences());try library.move(second,up:true);check(library.presets[0].id==second)
  try library.rename(second,name:"Backup");let original=library
  refused{_ = try library.add(name:"backup",preferences:value)};check(library==original)
  for name in ["", "\n", "默认设置", "自定义", "bad\0name",String(repeating:"字",count:61)]{refused{_ = try library.add(name:name,preferences:value)}}
  refused{try library.update(id,preferences:TransferPreferences(concurrency:99))};check(library==original)
  library.defaultPreferences=TransferPreferences(concurrency:2);library.selectedID=id
  check(library.activeName(TransferPreferences(concurrency:2))=="默认设置" && library.activeName(TransferPreferences(concurrency:6))=="自定义")
  check(TransferPresetLibrary.equivalent(TransferPreferences(),TransferPreferences(policy:TransferPolicy())))
  library.automaticSelectionEnabled=false
  try library.save(defaults);check(try TransferPresetLibrary.load(defaults)==library)
  if ProcessInfo.processInfo.environment["MACSCP_PRESETS_PERSISTENCE"]=="1"{
  check(defaults.synchronize())
  let process=Process();process.executableURL=URL(fileURLWithPath:CommandLine.arguments[0]);process.arguments=["--read-suite",suite,id.uuidString];try process.run();process.waitUntilExit();check(process.terminationStatus==0)
  }
  let old=defaults.data(forKey:TransferPresetLibrary.key)!
  var bad=library;bad.selectedID=UUID();refused{try bad.save(defaults)};check(defaults.data(forKey:TransferPresetLibrary.key)==old)
  defaults.set(Data("corrupt".utf8),forKey:TransferPresetLibrary.key);refused{_ = try TransferPresetLibrary.load(defaults)};check(defaults.data(forKey:TransferPresetLibrary.key)==Data("corrupt".utf8))
  defaults.set("wrong type",forKey:TransferPresetLibrary.key);refused{_ = try TransferPresetLibrary.load(defaults)}
  defaults.set(Data(repeating:32,count:TransferPresetLibrary.maximumBytes+1),forKey:TransferPresetLibrary.key);refused{_ = try TransferPresetLibrary.load(defaults)}
  var payload=try JSONSerialization.jsonObject(with:old) as! [String:Any];payload["version"]=99;defaults.set(try JSONSerialization.data(withJSONObject:payload),forKey:TransferPresetLibrary.key);refused{_ = try TransferPresetLibrary.load(defaults)}
  var limited=TransferPresetLibrary();for index in 0..<TransferPresetLibrary.maximumCount{_ = try limited.add(name:"预设 \(index)",preferences:value)};let full=limited;refused{_ = try limited.add(name:"超限",preferences:value)};check(limited==full)
  try library.remove(id);check(library.selectedID==nil && library.preset(id)==nil);refused{try library.rename(id,name:"stale")}
  print("PASS: preset CRUD/order/default/effective matching, stable IDs, invalid/duplicate names and values, count/data/schema/corruption refusal without overwriting, JSON persistence; fresh process reopen when MACSCP_PRESETS_PERSISTENCE=1, isolated suite only")
 }
}
