import Foundation
@main struct TransferPresetRulesTests {
 static func check(_ value:Bool,file:StaticString = #file,line:UInt = #line){precondition(value,file:file,line:line)}
 static func refused(_ action:()throws->Void){do{try action();fatalError("invalid mask accepted")}catch{}}
 static func main()throws {
  let context=TransferPresetContext(connection:"fixture",host:"Data01.example.invalid",user:"Alice",local:"/Users/alice/分析",remote:"/srv/project/data")
  let rule=TransferPresetRule(enabled:true,host:"data[0-9]?.example.invalid;backup.invalid | old*",user:"alice",local:"*/分析",remote:"/srv/project/")
  check(try rule.matches(context))
  check(try !TransferPresetRule(enabled:false).matches(context))
  for key in 0..<4{var bad=rule;switch key{case 0:bad.host="other.invalid";case 1:bad.user="bob";case 2:bad.local="/nope";default:bad.remote="/elsewhere/"};check(try !bad.matches(context))}
  check(try TransferPresetMask(" | temp*,build*").matches("result") && !TransferPresetMask(" | temp*,build*").matches("Temp01"))
  check(try TransferPresetMask("*.invalid | data*").matches("backup.invalid") && !TransferPresetMask("*.invalid | data*").matches(context.host))
  check(try TransferPresetMask("/srv/project/",directory:true).matches("/srv/project") && !TransferPresetMask("/srv/project/",directory:true).matches("/srv/projectile"))
  check(try TransferPresetMask("/srv/project",directory:true).matches("/srv/project") && !TransferPresetMask("/srv/project",directory:true).matches("/srv/project/data"))
  check(try TransferPresetMask("/",directory:true).matches("/srv/project/data"))
  for value in ["[::1]","a*b?c[d];e,f|g", "  spaces  ","/Users/项目 资料/中文[*]?; ,|"]{check(try TransferPresetMask(TransferPresetMask.literal(value)).matches(value))}
  check(try TransferPresetMask("[*][?][[]").matches("*?["))
  for invalid in ["[abc", "[]", "[z-a]", "*|x|y", "a\n", String(repeating:"a",count:2049),Array(repeating:"x",count:33).joined(separator:";")]{refused{_ = try TransferPresetMask(invalid)}}
  var library=TransferPresetLibrary();let a=try library.add(name:"优先",preferences:TransferPreferences(concurrency:2),rule:rule),b=try library.add(name:"兜底",preferences:TransferPreferences(),rule:TransferPresetRule(enabled:true))
  check(try library.automaticPreset(context)?.id==a);try library.move(b,up:true);check(try library.automaticPreset(context)?.id==b)
  library.automaticSelectionEnabled=false;check(try library.automaticPreset(context)==nil);library.automaticSelectionEnabled=true
  try library.setRule(b,rule:TransferPresetRule());check(try library.automaticPreset(context)?.id==a)
  let before=library;refused{try library.setRule(a,rule:TransferPresetRule(enabled:true,host:"["))};check(library==before)
  let data=try library.encoded();check(try JSONDecoder().decode(TransferPresetLibrary.self,from:data)==library)
  var object=try JSONSerialization.jsonObject(with:data) as! [String:Any];object.removeValue(forKey:"automaticSelectionEnabled");object["presets"]=(object["presets"] as! [[String:Any]]).map{item in var copy=item;copy.removeValue(forKey:"rule");return copy}
  let old=try JSONDecoder().decode(TransferPresetLibrary.self,from:JSONSerialization.data(withJSONObject:object));check(try old.validated().presets.allSatisfy{$0.rule==nil} && old.automaticSelectionEnabled==nil)
  check(try TransferPresetMask("*/café").matches("/tmp/cafe\u{301}"))
  let pattern=try TransferPresetMask(String(repeating:"*a",count:300)+"b");check(!pattern.matches(String(repeating:"a",count:3000)))
  print("PASS: all four conditions, ordered first match, global/per-rule enable, wildcard sets/ranges/Unicode/case/exclusions/escaped delimiters, directory subtree boundaries, malformed/oversized refusal, rollback, persistence/legacy JSON and bounded non-regex wildcard matching")
 }
}
