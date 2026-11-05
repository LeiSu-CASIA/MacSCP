import Cocoa
import UniformTypeIdentifiers

enum CommanderAppearance {
 struct Style {let symbol:String;let help:String;let tint:NSColor}
 static func style(_ raw:String,local:Bool?=nil)->Style? {
  let key=String(raw.split(separator:".").last ?? Substring(raw))
  let blue=NSColor.systemBlue,green=NSColor.systemGreen,gray=NSColor.secondaryLabelColor
  switch key {
  case "sortName","sortSize","sortDate","sortExtension","sortPermissions":return Style(symbol:"arrow.up.arrow.down",help:"对当前文件列表排序；再次选择反转顺序（⌘⌥1–5）",tint:blue)
  case "filterFocus":return Style(symbol:"line.3.horizontal.decrease",help:"筛选当前目录（⌘F）",tint:blue)
  case "root":return Style(symbol:"internaldrive",help:"进入根目录（⌘\\）",tint:blue)
  case "selectMask","deselectMask":return Style(symbol:"line.3.horizontal.decrease.circle",help:"按文件名规则批量选择或取消选择",tint:blue)
  case "invertSelection":return Style(symbol:"arrow.triangle.swap",help:"反选当前列表（⌘⇧I）",tint:blue)
  case "selectAllFiles","selectNone":return Style(symbol:"checkmark.circle",help:"更改当前面板的文件选择",tint:blue)
  case "connect":return Style(symbol:"network",help:"连接服务器（⌘N）",tint:blue)
  case "disconnect","close":return Style(symbol:"xmark.circle",help:"关闭当前服务器连接",tint:gray)
  case "reconnect":return Style(symbol:"arrow.triangle.2.circlepath",help:"重新连接当前服务器",tint:blue)
  case "connectionProgress":return Style(symbol:"ellipsis.circle",help:"查看当前 SSH 连接进度",tint:blue)
  case "sites":return Style(symbol:"square.and.arrow.down",help:"导入或导出站点配置",tint:blue)
  case "find":return Style(symbol:"magnifyingglass",help:"查找服务器上的文件",tint:blue)
  case "keepUpdated":return Style(symbol:"arrow.clockwise.circle",help:"监控本地文件变化，保持远程目录更新",tint:green)
  case "sync":return Style(symbol:"arrow.triangle.2.circlepath",help:"比较并同步两侧目录",tint:green)
  case "refresh":return Style(symbol:"arrow.clockwise",help:"刷新目录（⌘R）",tint:green)
  case "pause","pauseSelected":return Style(symbol:"pause.fill",help:"暂停传输队列",tint:blue)
  case "resume":return Style(symbol:"play.fill",help:"继续传输队列",tint:green)
  case "cancelTargetProbe":return Style(symbol:"xmark.circle",help:"取消尚未加入队列的目标核对（Esc）",tint:gray)
  case "cancel":return Style(symbol:"stop.circle",help:"取消选中的传输任务",tint:.systemRed)
  case "retrySync":return Style(symbol:"arrow.triangle.2.circlepath",help:"重新读取原同步范围，确认新预览后再执行；不会自动登录",tint:green)
  case "retry":return Style(symbol:"arrow.clockwise",help:"普通任务重试或续传；同步任务重新比较并预览",tint:green)
  case "clear":return Style(symbol:"trash",help:"清除已结束的队列记录",tint:gray)
  case "recover":return Style(symbol:"clock.arrow.circlepath",help:"选择并恢复上次未完成的任务",tint:blue)
  case "queueUp":return Style(symbol:"arrow.up",help:"上移选中的等待任务",tint:blue)
  case "queueDown":return Style(symbol:"arrow.down",help:"下移选中的等待任务",tint:blue)
  case "queueFirst":return Style(symbol:"arrow.up.to.line",help:"优先执行选中的等待任务",tint:blue)
  case "details":return Style(symbol:"list.bullet",help:"查看任务完整信息",tint:blue)
  case "confirmTransfer","confirmDragTransfer":return Style(symbol:"checkmark.rectangle",help:"切换传输前的目标与选项确认",tint:blue)
  case "settings":return Style(symbol:"slider.horizontal.3",help:"设置传输方式、限速和校验",tint:gray)
  case "linkedBrowsing":return Style(symbol:"link",help:"让另一侧跟随相对目录变化，不传输文件",tint:blue)
  case "forward":return Style(symbol:"chevron.right",help:"前进到下一个浏览目录（⌘]）",tint:blue)
  case "history":return Style(symbol:"clock.arrow.circlepath",help:"打开目录浏览历史",tint:blue)
  case "back","previousTab":return Style(symbol:"chevron.left",help:key=="back" ? "返回上一浏览目录（⌘[）" : "上一个会话",tint:blue)
  case "nextTab":return Style(symbol:"chevron.right",help:"下一个会话",tint:blue)
  case "up":return Style(symbol:"arrow.up",help:"进入上级目录（⌫）",tint:blue)
  case "home":return Style(symbol:"house",help:"进入首页目录",tint:blue)
  case "bookmarks":return Style(symbol:"star",help:"打开目录书签",tint:.systemOrange)
  case "tree":return Style(symbol:"sidebar.left",help:"显示或隐藏目录树",tint:blue)
  case "path","pathEdit":return Style(symbol:"pencil",help:"编辑完整路径（⌘L）",tint:blue)
  case "hidden":return Style(symbol:"eye",help:"显示或隐藏隐藏文件（⌘⇧.）",tint:gray)
  case "transfer":return Style(symbol:local.map{$0 ? "arrow.up.doc" : "arrow.down.doc"} ?? "arrow.up.arrow.down",help:local.map{$0 ? "上传选中的文件或目录（F5）" : "下载选中的文件或目录（F5）"} ?? "上传或下载选中项（F5）",tint:blue)
  case "edit":return Style(symbol:"pencil",help:"打开或编辑选中文件（F4）",tint:blue)
  case "rename":return Style(symbol:"character.cursor.ibeam",help:"重命名选中项（F2）",tint:blue)
  case "delete":return Style(symbol:"trash",help:"删除选中项（F8）",tint:.systemRed)
  case "properties":return Style(symbol:"info.circle",help:"查看选中项的属性（F9 / ⌥Return）",tint:blue)
  case "mkdir":return Style(symbol:"folder.badge.plus",help:"新建文件夹（F7）",tint:.systemOrange)
  case "chmod":return Style(symbol:"lock",help:"修改选中项的权限",tint:gray)
  case "checksum":return Style(symbol:"checkmark.shield",help:"计算 SHA-256 校验和",tint:green)
  case "copyFiles":return Style(symbol:"doc.on.doc",help:"复制选中的文件（⌘C）",tint:blue)
  case "pasteFiles":return Style(symbol:"doc.on.clipboard",help:"粘贴文件到当前目录（⌘V）",tint:blue)
  case "copyPath":return Style(symbol:"doc.on.clipboard",help:"复制选中项的完整路径（⌘⇧C）",tint:blue)
  case "selectAll":return Style(symbol:"checkmark.circle",help:"选择所有条目（⌘A）",tint:blue)
  case "remoteCopy":return Style(symbol:"doc.on.doc",help:"复制到服务器上的其他目录",tint:blue)
  case "remoteMove":return Style(symbol:"arrow.right",help:"移动到服务器上的其他目录",tint:blue)
  case "symlink":return Style(symbol:"link",help:"创建符号链接",tint:blue)
  case "terminal":return Style(symbol:"terminal",help:"在当前目录打开 SSH 终端",tint:gray)
  case "help":return Style(symbol:"questionmark.circle",help:"查看操作说明",tint:blue)
  case "about":return Style(symbol:"info.circle",help:"查看 MacSCP 版本",tint:blue)
  default:return nil
  }
 }
 static func image(_ key:String,local:Bool?=nil)->NSImage?{guard let value=style(key,local:local) else{return nil};let image=NSImage(systemSymbolName:value.symbol,accessibilityDescription:nil);image?.size=NSSize(width:14,height:14);return image}
 static func button(_ button:NSButton,key:String,local:Bool?=nil,iconOnly:Bool=false,label:String?=nil){
  guard let value=style(key,local:local),let image=image(key,local:local) else{return}
  if let chrome=button as? CommanderChromeButton{chrome.role=key=="connect" ? .primary : key=="transfer" ? .transfer : .normal;chrome.isBordered=false}
  button.image=image.withSymbolConfiguration(.init(paletteColors:[(button as? CommanderChromeButton)?.role == .primary ? .white : value.tint])) ?? image;button.imagePosition=iconOnly ? .imageOnly : .imageLeading;button.imageScaling = .scaleProportionallyDown;button.contentTintColor=(button as? CommanderChromeButton)?.role == .primary ? .white : nil;button.toolTip=value.help
  button.setAccessibilityLabel(label ?? (iconOnly ? value.help : button.title))
 }
 static func menu(_ item:NSMenuItem,key:String,local:Bool?=nil){item.image=image(key,local:local)}
 static func fileImage(_ entry:Entry)->NSImage? {
  let ext=(entry.name as NSString).pathExtension.lowercased(),type=UTType(filenameExtension:(entry.name as NSString).pathExtension)
  let symbol:String,color:NSColor
  if entry.dir{symbol="folder.fill";color = NSColor(calibratedRed:0.94,green:0.66,blue:0.16,alpha:1)}
  else if ["csv","tsv","xls","xlsx","numbers"].contains(ext){symbol="tablecells";color = .systemGreen}
  else if ext=="pdf"{symbol="doc.richtext";color = .systemRed}
  else if type?.conforms(to:.image)==true{symbol="photo";color = .systemPurple}
  else if type?.conforms(to:.movie)==true{symbol="film";color = .systemPurple}
  else if type?.conforms(to:.audio)==true{symbol="music.note";color = .systemPink}
  else if type?.conforms(to:.archive)==true || ["zip","gz","tar","7z","rar","bz2","xz"].contains(ext){symbol="archivebox";color = .systemBrown}
  else if type?.conforms(to:.text)==true || ["txt","md","log","json","yaml","yml","xml","ini","swift","py","js","sh"].contains(ext){symbol="doc.text";color = .secondaryLabelColor}
  else{symbol="doc";color = .secondaryLabelColor}
  let image=NSImage(systemSymbolName:symbol,accessibilityDescription:nil)?.withSymbolConfiguration(.init(paletteColors:[color]));image?.size=NSSize(width:16,height:16);return image
 }
}

final class CommanderFileCell:NSTableCellView {
 private static var icons=[String:NSImage]();private var unavailable=false;private var normalIcon:NSImage?
 override var backgroundStyle:NSView.BackgroundStyle{didSet{updateTextColor()}}
 private func updateTextColor(){textField?.textColor=backgroundStyle == .emphasized ? .alternateSelectedControlTextColor : unavailable ? .systemRed : .labelColor;imageView?.image=backgroundStyle == .emphasized ? normalIcon?.withSymbolConfiguration(.init(paletteColors:[.white])) : normalIcon}
 override init(frame frameRect:NSRect){super.init(frame:frameRect);identifier = .init("commander.fileName")
  let image=NSImageView(),label=NSTextField(labelWithString:"");label.font = .systemFont(ofSize:12.5,weight:.regular);image.imageScaling = .scaleProportionallyDown;image.setAccessibilityElement(false);label.lineBreakMode = .byTruncatingMiddle
  image.translatesAutoresizingMaskIntoConstraints=false;label.translatesAutoresizingMaskIntoConstraints=false;addSubview(image);addSubview(label);imageView=image;textField=label
  NSLayoutConstraint.activate([image.leadingAnchor.constraint(equalTo:leadingAnchor,constant:4),image.widthAnchor.constraint(equalToConstant:16),image.heightAnchor.constraint(equalToConstant:16),image.centerYAnchor.constraint(equalTo:centerYAnchor),label.leadingAnchor.constraint(equalTo:image.trailingAnchor,constant:6),label.trailingAnchor.constraint(equalTo:trailingAnchor,constant:-4),label.centerYAnchor.constraint(equalTo:centerYAnchor)])
 }
 required init?(coder:NSCoder){fatalError()}
 func configure(_ entry:Entry){
  let key=entry.dir ? "folder" : "file:"+(entry.name as NSString).pathExtension.lowercased()
  if let cached=Self.icons[key]{imageView?.image=cached}else{
   let icon=CommanderAppearance.fileImage(entry);if let icon=icon,Self.icons.count<128{Self.icons[key]=icon};imageView?.image=icon
  }
  normalIcon=imageView?.image;textField?.stringValue=(entry.symbolicLink ? "↗ " : "")+entry.name;unavailable=entry.linkUnavailable;updateTextColor()
  toolTip=entry.symbolicLink ? "链接 → "+(entry.linkTarget ?? "未知目标")+(entry.linkUnavailable ? "（目标不存在或无法访问）" : "") : entry.name
  textField?.toolTip=toolTip;setAccessibilityLabel(entry.name)
 }
}

final class CommanderTextCell:NSTableCellView {
 private var normalColor:NSColor = .labelColor
 override var backgroundStyle:NSView.BackgroundStyle{didSet{updateTextColor()}}
 private func updateTextColor(){textField?.textColor=backgroundStyle == .emphasized ? .alternateSelectedControlTextColor : normalColor}
 override init(frame:NSRect){
  super.init(frame:frame)
  let label=NSTextField(labelWithString:"");label.font = .systemFont(ofSize:12);label.lineBreakMode = .byTruncatingMiddle
  label.translatesAutoresizingMaskIntoConstraints=false;addSubview(label);textField=label
  NSLayoutConstraint.activate([label.leadingAnchor.constraint(equalTo:leadingAnchor,constant:5),label.trailingAnchor.constraint(equalTo:trailingAnchor,constant:-5),label.centerYAnchor.constraint(equalTo:centerYAnchor)])
 }
 required init?(coder:NSCoder){fatalError()}
 func configure(_ value:String,alignment:NSTextAlignment = .left,color:NSColor = .labelColor){textField?.stringValue=value;textField?.alignment=alignment;normalColor=color;updateTextColor();toolTip=value}
}
