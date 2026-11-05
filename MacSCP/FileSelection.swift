import Cocoa

struct FileSelectionRule:Codable,Equatable {
 enum Kind:String,Codable{case files,directories,all}
 enum Mode:String,Codable{case replace,add,remove}
 var include="*",exclude="";var caseSensitive=false;var kind:Kind = .files;var mode:Mode = .add
 private func patterns(_ value:String)throws->[[Character]]{
  guard value.count<=2048,!value.unicodeScalars.contains(where:{CharacterSet.controlCharacters.contains($0)}),!value.contains("/"),!value.contains("|") else{throw SFTPError.message("规则只匹配当前目录名称，长度不超过 2048 字符；不使用 /、| 或控制字符")}
  let parts=value.split(separator:";").map{String($0).trimmingCharacters(in:.whitespaces)}.filter{!$0.isEmpty}
  guard parts.count<=64 else{throw SFTPError.message("每栏最多 64 条规则，以分号分隔")}
  return parts.map{Array(caseSensitive ? $0 : $0.folding(options:.caseInsensitive,locale:Locale(identifier:"en_US_POSIX")))}
 }
 private static func match(_ pattern:[Character],_ name:[Character])->Bool{
  var p=0,n=0,star:Int?,restart=0
  while n<name.count{
   if p<pattern.count,pattern[p] != "*",pattern[p]=="?" || pattern[p]==name[n]{p+=1;n+=1}
   else if p<pattern.count,pattern[p]=="*"{star=p;p+=1;restart=n}
   else if let s=star{restart+=1;n=restart;p=s+1}
   else{return false}
  }
  while p<pattern.count,pattern[p]=="*"{p+=1};return p==pattern.count
 }
 func matching(_ entries:[Entry])throws->IndexSet{
  let includes=try patterns(include),excludes=try patterns(exclude)
  return IndexSet(entries.indices.filter{index in
   let entry=entries[index];guard entry.name != "..",entry.name != ".",kind == .all || (kind == .directories ? entry.dir : !entry.dir) else{return false}
   let name=Array(caseSensitive ? entry.name : entry.name.folding(options:.caseInsensitive,locale:Locale(identifier:"en_US_POSIX")))
   return (includes.isEmpty || includes.contains{Self.match($0,name)}) && !excludes.contains{Self.match($0,name)}
  })
 }
 func selection(_ entries:[Entry],current:IndexSet)throws->IndexSet{
  let valid=IndexSet(entries.indices.filter{entries[$0].name != ".." && entries[$0].name != "."}),matched=try matching(entries),existing=current.intersection(valid)
  switch mode{case .replace:return matched;case .add:return existing.union(matched);case .remove:return existing.subtracting(matched)}
 }
}

final class FileSelectionForm:NSView,NSTextFieldDelegate {
 let include=NSTextField(),exclude=NSTextField(),caseSensitive=NSButton(checkboxWithTitle:"区分大小写",target:nil,action:nil),kind=NSPopUpButton(),mode=NSPopUpButton(),preview=NSTextField(wrappingLabelWithString:"")
 let entries:[Entry],current:IndexSet;var onValidity:((Bool)->Void)?
 init(rule:FileSelectionRule,entries:[Entry],current:IndexSet){
  self.entries=entries;self.current=current;super.init(frame:NSRect(x:0,y:0,width:480,height:245))
  let stack=NSStackView();stack.orientation = .vertical;stack.alignment = .leading;stack.spacing=9;stack.translatesAutoresizingMaskIntoConstraints=false;addSubview(stack)
  NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo:leadingAnchor),stack.trailingAnchor.constraint(equalTo:trailingAnchor),stack.topAnchor.constraint(equalTo:topAnchor),stack.bottomAnchor.constraint(lessThanOrEqualTo:bottomAnchor)])
  for (label,field,value) in [("包含名称",include,rule.include),("排除名称",exclude,rule.exclude)]{
   let text=NSTextField(labelWithString:label);let row=NSStackView(views:[text,field]);row.spacing=10;text.widthAnchor.constraint(equalToConstant:65).isActive=true;field.stringValue=value;field.delegate=self;field.placeholderString=label=="包含名称" ? "例如：*.csv;*.txt" : "例如：*_backup.csv";field.setAccessibilityLabel(label);stack.addArrangedSubview(row);row.widthAnchor.constraint(equalTo:stack.widthAnchor).isActive=true
  }
  kind.addItems(withTitles:["仅文件","仅目录","文件和目录"]);kind.selectItem(at:rule.kind == .files ? 0 : rule.kind == .directories ? 1 : 2)
  mode.addItems(withTitles:["替换当前选择","加入当前选择","从当前选择移除"]);mode.selectItem(at:rule.mode == .replace ? 0 : rule.mode == .add ? 1 : 2)
  kind.setAccessibilityLabel("匹配类型");mode.setAccessibilityLabel("选择方式")
  caseSensitive.state=rule.caseSensitive ? .on : .off
  for control in [kind,mode,caseSensitive] as [NSControl]{control.target=self;control.action = #selector(changed)}
  stack.addArrangedSubview(NSStackView(views:[kind,mode,caseSensitive]))
  let help=NSTextField(wrappingLabelWithString:"* 匹配任意名称字符，? 匹配一个字符；多条规则用分号分隔。只处理当前列表中可见的项目，不进入子目录；上级目录不参与选择。");help.font = .systemFont(ofSize:11);help.textColor = .secondaryLabelColor;stack.addArrangedSubview(help);help.widthAnchor.constraint(equalTo:stack.widthAnchor).isActive=true
  preview.font = .systemFont(ofSize:12,weight:.medium);stack.addArrangedSubview(preview);preview.widthAnchor.constraint(equalTo:stack.widthAnchor).isActive=true;updatePreview()
 }
 required init?(coder:NSCoder){fatalError()}
 func value()->FileSelectionRule{FileSelectionRule(include:include.stringValue,exclude:exclude.stringValue,caseSensitive:caseSensitive.state == .on,kind:kind.indexOfSelectedItem==0 ? .files : kind.indexOfSelectedItem==1 ? .directories : .all,mode:mode.indexOfSelectedItem==0 ? .replace : mode.indexOfSelectedItem==1 ? .add : .remove)}
 @objc func changed(){updatePreview()}
 func controlTextDidChange(_ notification:Notification){updatePreview()}
 func updatePreview(){do{let rule=value(),matched=try rule.matching(entries),result=try rule.selection(entries,current:current);preview.stringValue="匹配 \(matched.count) 项 · 应用后选中 \(result.count) 项";preview.textColor = .labelColor;onValidity?(true)}catch{preview.stringValue=error.localizedDescription;preview.textColor = .systemRed;onValidity?(false)}}
}
