import Cocoa
extension App {
 var transferPresetContext:TransferPresetContext?{guard remoteConnectionReady,let site=session,!local.currentPath.isEmpty,!remote.currentPath.isEmpty else{return nil};return TransferPresetContext(connection:socket,host:site.host,user:site.user,local:local.currentPath,remote:remote.currentPath)}
 var effectiveTransferPreferences:TransferPreferences{automaticTransferPresetID.flatMap{transferPresets.preset($0)?.preferences} ?? preferences}
 func reevaluateTransferPreset(force:Bool=false){let context=transferPresetContext;guard force || context != lastTransferPresetContext else{return};lastTransferPresetContext=context
  let old=automaticTransferPresetID
  do{automaticTransferPresetID=transferPresetReadError==nil ? try context.flatMap{try transferPresets.automaticPreset($0)?.id} : nil}catch{automaticTransferPresetID=nil;status.stringValue="自动匹配条件无效，保留手动传输设置："+error.localizedDescription}
  if old != automaticTransferPresetID || force{refreshTransferRuntime()}
 }
 @objc func toggleAutomaticTransferPresets(){do{var library=transferPresets;guard transferPresetReadError==nil else{throw SFTPError.message("请先修复预设库")};library.automaticSelectionEnabled=library.automaticSelectionEnabled==false;try commitTransferSettings(preferences,library:library);reevaluateTransferPreset(force:true);status.stringValue=library.automaticSelectionEnabled==true ? "自动匹配已开启，按预设列表顺序选择" : "自动匹配已关闭，使用手动设置"}catch{status.stringValue=error.localizedDescription}}

 @objc func selectTransferMode(_ item:NSMenuItem){guard let raw=item.representedObject as? String,let mode=TransferMode(rawValue:raw) else{return};do{var value=effectiveTransferPreferences,policy=value.filePolicy,text=policy.text ?? TextTransferOptions();text.mode=mode;policy.text=text==TextTransferOptions() ? nil : text;value.policy=policy;var library=transferPresets;library.selectedID=nil;try commitTransferSettings(value,library:transferPresetReadError==nil ? library : nil);status.stringValue="传输模式已切换；新任务使用新模式，旧任务保留原设置"}catch{status.stringValue=error.localizedDescription}}
 func rebuildTransferPresetPicker(){
  let mode=effectiveTransferPreferences.filePolicy.text?.mode ?? .binary;transferSettingsControl?.title="传输："+(mode == .binary ? "二进制" : mode == .text ? "文本" : "自动");transferSettingsControl?.toolTip="当前传输模式；点击设置文本掩码、换行、限速和校验"
  let menu=NSMenu();menu.autoenablesItems=false;let title=transferPresetReadError==nil ? automaticTransferPresetID.flatMap{transferPresets.preset($0).map{"自动 · "+$0.name}} ?? transferPresets.activeName(preferences) : "预设不可用"
  menu.addItem(withTitle:"预设："+title,action:nil,keyEquivalent:"")
  let automatic=NSMenuItem(title:"自动匹配服务器与目录",action:#selector(toggleAutomaticTransferPresets),keyEquivalent:"");automatic.target=self;automatic.state=transferPresets.automaticSelectionEnabled != false ? .on : .off;automatic.isEnabled=transferPresetReadError==nil;menu.addItem(automatic);menu.addItem(.separator())
  let standard=NSMenuItem(title:"默认设置",action:#selector(selectTransferPreset),keyEquivalent:"");standard.target=self;standard.representedObject="default";menu.addItem(standard)
  for preset in transferPresets.presets{let item=NSMenuItem(title:preset.name,action:#selector(selectTransferPreset),keyEquivalent:"");item.target=self;item.representedObject=preset.id.uuidString;item.state=(automaticTransferPresetID ?? transferPresets.selectedID)==preset.id && TransferPresetLibrary.equivalent(effectiveTransferPreferences,preset.preferences) ? .on : .off;menu.addItem(item)}
  menu.addItem(.separator());for (title,mode) in [("二进制 · 保持原字节",TransferMode.binary),("文本 · 按设置转换换行",.text),("自动 · 按文本文件掩码",.automatic)]{let item=NSMenuItem(title:title,action:#selector(selectTransferMode),keyEquivalent:"");item.target=self;item.representedObject=mode.rawValue;item.state=(effectiveTransferPreferences.filePolicy.text?.mode ?? .binary)==mode ? .on : .off;menu.addItem(item)}
  menu.addItem(.separator());let manage=NSMenuItem(title:"管理传输预设…",action:#selector(transferSettings),keyEquivalent:"");manage.target=self;menu.addItem(manage);transferPresetPicker.menu=menu
  transferPresetPicker.toolTip="当前："+title+"\n选择后应用并行数与限速；包含/排除规则和校验仅用于新任务。自动匹配开启时，手动选择保留至下一次切换服务器或目录。";transferPresetPicker.setAccessibilityLabel("传输预设："+title)
 }
 @objc func selectTransferPreset(_ sender:NSMenuItem){guard let key=sender.representedObject as? String else{return};do{
  var library=transferPresets;let value:TransferPreferences
  if key=="default"{value=library.defaultPreferences ?? TransferPreferences();library.selectedID=nil}
  else{guard transferPresetReadError==nil,let id=UUID(uuidString:key),let preset=library.preset(id) else{throw SFTPError.message("预设已移除或预设库不可用，请重新选择")};value=preset.preferences;library.selectedID=id}
  try commitTransferSettings(value,library:transferPresetReadError==nil ? library : nil);status.stringValue="已应用传输配置："+transferPresets.activeName(preferences)+"；已有任务保留原规则"
 }catch{status.stringValue=error.localizedDescription;status.toolTip=error.localizedDescription}}
}
