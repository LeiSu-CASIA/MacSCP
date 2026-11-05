import Cocoa
final class TransferSettingsView:NSView {
 var textOptions=TextTransferOptions();let modeButton=NSButton(title:"",target:nil,action:nil)
 let concurrency=NSTextField(),speed=NSTextField(),include=NSTextField(),exclude=NSTextField();let verify=NSButton(checkboxWithTitle:"完成前校验 SHA-256",target:nil,action:nil)
 init(preferences:TransferPreferences,includesConcurrency:Bool=true){let height=includesConcurrency ? 225 : 185;super.init(frame:NSRect(x:0,y:0,width:550,height:height));let fields=(includesConcurrency ? [("并行任务数（1–8）",concurrency)] : [])+[("每任务限速（KiB/s）",speed),("包含文件掩码",include),("排除文件/目录掩码",exclude)];for(i,pair) in fields.enumerated(){let y=CGFloat(height-40-i*40);let label=NSTextField(labelWithString:pair.0);label.frame=NSRect(x:0,y:y+3,width:200,height:22);addSubview(label);pair.1.frame=NSRect(x:205,y:y,width:335,height:26);addSubview(pair.1)};load(preferences);include.placeholderString="例如 *.txt;*.csv（空白为全部）";exclude.placeholderString="例如 *.tmp;.git/;node_modules/";verify.frame=NSRect(x:0,y:14,width:330,height:28);verify.toolTip="会额外读取远程文件；文本模式校验转换后字节";modeButton.frame=NSRect(x:350,y:14,width:195,height:28);modeButton.bezelStyle = .rounded;modeButton.target=self;modeButton.action = #selector(editTextOptions);addSubview(modeButton);verify.state=preferences.filePolicy.verifyChecksum ? .on : .off;addSubview(verify)}
 func load(_ preferences:TransferPreferences){textOptions=preferences.filePolicy.text ?? TextTransferOptions();updateModeTitle();concurrency.stringValue=String(preferences.concurrency);speed.stringValue=String(preferences.kibibytesPerSecond);include.stringValue=preferences.filePolicy.include;exclude.stringValue=preferences.filePolicy.exclude;verify.state=preferences.filePolicy.verifyChecksum ? .on : .off}
 private func updateModeTitle(){modeButton.title="传输模式："+(textOptions.mode == .binary ? "二进制…" : textOptions.mode == .text ? "文本…" : "自动…");modeButton.toolTip="设置文本文件掩码、两端换行及可选的 BOM / EOF 移除"}
 @objc func editTextOptions(){let form=TextTransferOptionsView(textOptions),alert=NSAlert();alert.messageText="传输模式与文本换行";alert.informativeText="二进制保持原字节；文本模式仅转换换行。设置保留在主窗口草稿中。";alert.accessoryView=form;alert.addButton(withTitle:"保存到草稿");alert.addButton(withTitle:"取消");while alert.runModal() == .alertFirstButtonReturn{do{textOptions=try form.value();updateModeTitle();return}catch{alert.informativeText=error.localizedDescription}}}
 required init?(coder:NSCoder){fatalError()}
 func value()throws->TransferPreferences{guard let count=Int(concurrency.stringValue),let limit=Int(speed.stringValue) else{throw SFTPError.message("并行数和限速必须为整数")};return try TransferPreferences(concurrency:count,kibibytesPerSecond:limit,policy:TransferPolicy(include:include.stringValue,exclude:exclude.stringValue,verifyChecksum:verify.state == .on,text:textOptions==TextTransferOptions() ? nil : textOptions)).validated()}
}

final class TextTransferOptionsView:NSView {
 let mode=NSPopUpButton(),mask=NSTextField(),remote=NSPopUpButton(),local=NSPopUpButton()
 let bom=NSButton(checkboxWithTitle:"上传时移除 UTF-8 BOM",target:nil,action:nil),eof=NSButton(checkboxWithTitle:"上传时移除末尾 Ctrl-Z",target:nil,action:nil)
 init(_ value:TextTransferOptions){super.init(frame:NSRect(x:0,y:0,width:550,height:275))
  mode.addItems(withTitles:["二进制 · 保持原始字节","文本 · 转换所有文件","自动 · 按文本文件掩码"]);mode.selectItem(at:TransferMode.allCases.firstIndex(of:value.mode)!);mode.target=self;mode.action = #selector(update)
  for (index,item) in [("传输模式",mode as NSView),("文本文件掩码",mask as NSView),("服务器换行",remote as NSView),("本机换行",local as NSView)].enumerated(){let y=CGFloat(235-index*38),label=NSTextField(labelWithString:item.0);label.frame=NSRect(x:0,y:y+3,width:130,height:23);addSubview(label);item.1.frame=NSRect(x:135,y:y,width:410,height:27);addSubview(item.1)}
  mask.stringValue=value.mask;mask.font = .systemFont(ofSize:12);mask.cell?.isScrollable=true;mask.cell?.wraps=false
  for control in [remote,local]{control.addItems(withTitles:["Unix / macOS（LF）","Windows（CRLF）"])};remote.selectItem(at:value.remote == .lf ? 0 : 1);local.selectItem(at:value.local == .lf ? 0 : 1)
  bom.frame=NSRect(x:0,y:73,width:265,height:25);eof.frame=NSRect(x:275,y:73,width:270,height:25);bom.state=value.removeBOM ? .on : .off;eof.state=value.removeEOF ? .on : .off;addSubview(bom);addSubview(eof)
  let help=NSTextField(wrappingLabelWithString:"默认二进制不改内容。文本模式会转换 CRLF、LF 和 CR；不转字符编码。自动模式按文件名匹配，检测到 NUL 或 UTF-16/32 BOM 时保持原字节；强制文本则报错。文本下载失败后重新下载，不按转换后字节偏移续传。FTP/FTPS 同样按所选格式转换换行。")
  help.font = .systemFont(ofSize:11);help.textColor=CommanderPalette.muted;help.frame=NSRect(x:0,y:2,width:545,height:65);addSubview(help);update()
 }
 required init?(coder:NSCoder){fatalError()}
 @objc func update(){let active=mode.indexOfSelectedItem != 0;mask.isEnabled=mode.indexOfSelectedItem==2;for control in [remote,local,bom,eof]{control.isEnabled=active}}
 func value()throws->TextTransferOptions{try TextTransferOptions(mode:TransferMode.allCases[mode.indexOfSelectedItem],mask:mask.stringValue,remote:remote.indexOfSelectedItem==0 ? .lf : .crlf,local:local.indexOfSelectedItem==0 ? .lf : .crlf,removeBOM:bom.state == .on,removeEOF:eof.state == .on).validated()}
}
