import Cocoa
final class SSHOptionsView:NSView {
 let jump=NSTextField(),timeout=NSTextField(),interval=NSTextField(),count=NSTextField();let compression=NSButton(checkboxWithTitle:"启用 SSH 压缩",target:nil,action:nil)
 init(){super.init(frame:NSRect(x:0,y:0,width:480,height:180));let labels=["跳板机（可留空）","连接超时（秒）","保活间隔（秒）","保活失败次数"];for(i,field) in [jump,timeout,interval,count].enumerated(){let y=CGFloat(145-i*40);let label=NSTextField(labelWithString:labels[i]);label.frame=NSRect(x:0,y:y+3,width:145,height:22);label.alignment = .right;addSubview(label);field.frame=NSRect(x:155,y:y,width:i==0 ? 315 : 110,height:26);addSubview(field)};jump.placeholderString="user@jump.example.com:22";compression.frame=NSRect(x:285,y:25,width:190,height:26);addSubview(compression);load(SSHOptions())}
 required init?(coder:NSCoder){fatalError()}
 func load(_ options:SSHOptions){jump.stringValue=options.jumpHost;timeout.stringValue=String(options.connectTimeout);interval.stringValue=String(options.keepAliveInterval);count.stringValue=String(options.keepAliveCount);compression.state=options.compression ? .on : .off}
 func value()throws->SSHOptions{guard let timeout=Int(timeout.stringValue),let interval=Int(interval.stringValue),let count=Int(count.stringValue) else{throw SFTPError.message("SSH 时间和次数必须为整数")};return try SSHOptions(jumpHost:jump.stringValue.trimmingCharacters(in:.whitespacesAndNewlines),connectTimeout:timeout,keepAliveInterval:interval,keepAliveCount:count,compression:compression.state == .on).validated()}
}
