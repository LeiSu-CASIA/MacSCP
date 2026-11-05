import Cocoa

final class TransferPresetRuleController:NSWindowController,NSWindowDelegate {
 let enabled=NSButton(checkboxWithTitle:"自动选择此预设",target:nil,action:nil)
 let host=NSTextField(),user=NSTextField(),local=NSTextField(),remote=NSTextField()
 let notice=NSTextField(wrappingLabelWithString:"")
 let currentButton=NSButton(title:"使用当前服务器与目录",target:nil,action:nil),saveButton=NSButton(title:"保存到预设草稿",target:nil,action:nil)
 let context:TransferPresetContext?;var onApply:((TransferPresetRule)throws->Void)?,onClosed:(()->Void)?
 init(name:String,rule:TransferPresetRule,context:TransferPresetContext?){self.context=context
  let window=NSWindow(contentRect:NSRect(x:0,y:0,width:650,height:390),styleMask:[.titled,.closable],backing:.buffered,defer:false);window.title="自动匹配 · "+name;window.isReleasedWhenClosed=false;window.appearance=NSAppearance(named:.aqua);super.init(window:window);window.delegate=self
  let content=window.contentView!
  enabled.frame=NSRect(x:20,y:345,width:600,height:26);enabled.state=rule.enabled ? .on : .off;enabled.target=self;enabled.action = #selector(toggle);content.addSubview(enabled)
  for (i,item) in [("服务器地址",host),("用户名",user),("本地目录",local),("远程目录",remote)].enumerated(){let y=CGFloat(303-i*38);let label=NSTextField(labelWithString:item.0);label.frame=NSRect(x:22,y:y+3,width:95,height:22);content.addSubview(label);item.1.frame=NSRect(x:120,y:y,width:505,height:26);item.1.font = .systemFont(ofSize:12);item.1.cell?.wraps=false;item.1.cell?.isScrollable=true;item.1.maximumNumberOfLines=1;item.1.placeholderString="留空表示不限";content.addSubview(item.1)}
  host.stringValue=rule.host;user.stringValue=rule.user;local.stringValue=rule.local;remote.stringValue=rule.remote
  let help=NSTextField(wrappingLabelWithString:"四项条件同时满足才匹配；多个预设命中时按列表顺序取第一项。支持 *、?、[abc]、[a-z]，; 或 , 分隔，| 后为排除规则。大小写不敏感；目录以 / 结尾可匹配子目录。切换服务器或目录时重评；手动选择保留到下一次切换。")
  help.font = .systemFont(ofSize:11.5);help.textColor=CommanderPalette.muted;help.frame=NSRect(x:22,y:106,width:603,height:66);content.addSubview(help)
  notice.font = .systemFont(ofSize:11.5);notice.frame=NSRect(x:22,y:49,width:603,height:52);notice.maximumNumberOfLines=3;content.addSubview(notice)
  currentButton.frame=NSRect(x:18,y:12,width:185,height:30);currentButton.target=self;currentButton.action = #selector(useCurrent);currentButton.bezelStyle = .rounded;content.addSubview(currentButton)
  let cancel=NSButton(title:"取消",target:self,action:#selector(cancel));cancel.frame=NSRect(x:360,y:12,width:90,height:30);cancel.bezelStyle = .rounded;cancel.keyEquivalent="\u{1b}";content.addSubview(cancel)
  saveButton.frame=NSRect(x:453,y:12,width:180,height:30);saveButton.bezelStyle = .rounded;saveButton.target=self;saveButton.action = #selector(apply);saveButton.keyEquivalent="\r";content.addSubview(saveButton);toggle()
 }
 required init?(coder:NSCoder){fatalError()}
 @objc func toggle(){for field in [host,user,local,remote]{field.isEnabled=enabled.state == .on};currentButton.isEnabled=enabled.state == .on && context != nil;notice.stringValue="条件与预设一起保存在本机；不会建立连接。保存草稿后，仍需在主设置中点击“应用并保存”。";notice.textColor=CommanderPalette.muted}
 @objc func useCurrent(){guard let context=context else{return};host.stringValue=TransferPresetMask.literal(context.host);user.stringValue=TransferPresetMask.literal(context.user);local.stringValue=TransferPresetMask.literal(context.local);remote.stringValue=TransferPresetMask.literal(context.remote)}
 func value()throws->TransferPresetRule{try TransferPresetRule(enabled:enabled.state == .on,host:host.stringValue,user:user.stringValue,local:local.stringValue,remote:remote.stringValue).validated()}
 @objc func apply(){do{try onApply?(value());close()}catch{notice.stringValue=error.localizedDescription;notice.toolTip=error.localizedDescription;notice.textColor = .systemRed}}
 @objc func cancel(){close()}
 override func close(){if let window=window,let parent=window.sheetParent{parent.endSheet(window)};super.close()}
 func windowWillClose(_ notification:Notification){onClosed?()}
}
