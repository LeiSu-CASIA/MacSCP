import Cocoa
@main struct NativeFileSelectionTests {
 static func check(_ value:Bool){precondition(value)}
 static func main()throws{
  NSApplication.shared.setActivationPolicy(.prohibited)
  let entries=[Entry(name:"..",size:0,dir:true),Entry(name:"folder.csv",size:0,dir:true),Entry(name:"a.csv",size:1,dir:false),Entry(name:"b_backup.csv",size:2,dir:false),Entry(name:"数据.CSV",size:3,dir:false),Entry(name:"a[1].txt",size:4,dir:false),Entry(name:"*literal.csv",size:5,dir:false),Entry(name:"👨‍👩‍👧‍👦.csv",size:5,dir:false)]
  let rule=FileSelectionRule(include:"*.csv",exclude:"*_backup.csv",mode:.replace)
  let matched=try rule.matching(entries);check(matched==IndexSet([2,4,6,7]))
  var sensitive=rule;sensitive.caseSensitive=true;check(try sensitive.matching(entries)==IndexSet([2,6,7]))
  var directories=rule;directories.kind = .directories;check(try directories.matching(entries)==IndexSet(integer:1))
  var all=rule;all.kind = .all;check(try all.matching(entries)==IndexSet([1,2,4,6,7]))
  let literal=FileSelectionRule(include:"a[1].txt;?.CSV",mode:.replace);check(try literal.matching(entries)==IndexSet([2,5,7]))
  let empty=FileSelectionRule(include:" ",exclude:"",kind:.all,mode:.replace);check(try empty.matching(entries)==IndexSet(integersIn:1..<entries.count))
  var add=rule;add.mode = .add;check(try add.selection(entries,current:IndexSet([0,3,99]))==IndexSet([2,3,4,6,7]))
  var remove=rule;remove.mode = .remove;check(try remove.selection(entries,current:IndexSet(integersIn:0..<entries.count))==IndexSet([1,3,5]))
  for pattern in ["/abs","dir/*.csv","a|b","bad\nname",String(repeating:"x",count:2049),Array(repeating:"x",count:65).joined(separator:";")]{do{_ = try FileSelectionRule(include:pattern).matching(entries);fatalError("invalid pattern accepted")}catch{}}
  let adversarial=FileSelectionRule(include:String(repeating:"*a",count:500)+"b");check(try adversarial.matching([Entry(name:String(repeating:"a",count:255),size:0,dir:false)]).isEmpty)
  let fm=FileManager.default,root=fm.temporaryDirectory.appendingPathComponent("native-file-selection-"+UUID().uuidString),suite="macscp-selection-"+UUID().uuidString
  try fm.createDirectory(at:root,withIntermediateDirectories:true);let defaults=UserDefaults(suiteName:suite)!
  defer{try? fm.removeItem(at:root);defaults.removePersistentDomain(forName:suite)}
  let app=App(defaults:defaults,dataDirectory:root.appendingPathComponent("profile"),initialLocalDirectory:root.path,automaticLogin:false,showsMainWindow:false,frameAutosaveName:nil,clientProvider:{_,_ in fatalError("unexpected network")})
  app.applicationDidFinishLaunching(Notification(name:NSApplication.didFinishLaunchingNotification));defer{app.window.close()}
  for pane in [app.local,app.remote]{pane.setConnectionState(.connected);pane.acceptPath(root.path);pane.entries=entries;pane.reload();try pane.applySelection(rule);check(Set(pane.selected.map{$0.name})==Set(["a.csv","数据.CSV","*literal.csv","👨‍👩‍👧‍👦.csv"]));check(pane.selectionRule==rule);pane.invertSelection();check(pane.selected.count==3 && !pane.selected.contains{$0.name==".."});pane.selectAllFiles();check(pane.selected.count==entries.count-1)}
  let local=app.local;local.table.selectAll(nil);check(local.selected.count==entries.count-1 && !local.selected.contains{$0.name==".."});local.table.deselectAll(nil);var prompts=0
  app.selectionRulePrompt={pane,initial in prompts+=1;check(pane === local && initial.mode == .replace);return rule};app.paneCommand(true,"selectMask");check(prompts==1 && local.selected.count==4)
  app.selectionRulePrompt={pane,initial in check(initial.mode == .remove);return remove};app.paneCommand(true,"deselectMask");check(local.selected.isEmpty)
  app.selectionRulePrompt={pane,_ in pane.filter.stringValue="a.csv";pane.applyFilter();return rule};app.selectByPattern(local);check(local.selected.isEmpty && app.status.stringValue.contains("列表已变化"))
  local.filter.stringValue="";local.entries=entries;local.reload();let item=local.table.menu!.items.first{$0.identifier?.rawValue=="invertSelection"}!;local.contextAction(item);check(local.selected.count==entries.count-1)
  local.hiddenToggle.state = .off;local.allEntries=entries+[Entry(name:".hidden.csv",size:1,dir:false)];local.applyFilter();try local.applySelection(rule);check(!local.selected.contains{$0.name.hasPrefix(".")})
  app.remote.setConnectionState(.disconnected);var offlinePrompt=false;app.selectionRulePrompt={_,_ in offlinePrompt=true;return rule};app.selectByPattern(app.remote);check(!offlinePrompt)
  let form=FileSelectionForm(rule:rule,entries:entries,current:IndexSet(integer:3));let host=NSWindow(contentRect:NSRect(x:0,y:0,width:500,height:265),styleMask:[.titled],backing:.buffered,defer:false);host.isReleasedWhenClosed=false;host.contentView!.addSubview(form);host.contentView!.layoutSubtreeIfNeeded()
  check(form.include.frame.width>250 && form.preview.stringValue.contains("匹配 4 项") && !host.isVisible)
  var valid=true;form.onValidity={valid=$0};form.include.stringValue="/invalid";form.changed();check(!valid && form.preview.textColor == .systemRed)
  form.include.stringValue="*.txt";form.changed();check(valid && form.preview.stringValue.contains("匹配 1 项"));host.close()
  check(FileKeyAction.resolve(code:0,command:true,shift:false,option:false)=="selectAllFiles")
  check(FileKeyAction.resolve(code:34,command:true,shift:true,option:false)=="invertSelection" && FileKeyAction.resolve(code:34,command:true,shift:false,option:false)==nil && !app.window.isVisible)
  print("PASS: Unicode/literal wildcard selection, include/exclude and case/type rules, bounded non-regex matcher, add/remove/replace and parent exclusion, real two-pane menu/context routing, visible-only selection, stale-list/offline refusal, preference persistence and live preview validation; no network/window/login")
 }
}
