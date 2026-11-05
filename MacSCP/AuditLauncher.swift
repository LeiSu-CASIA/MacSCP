import Cocoa
// Dedicated entry point for visible acceptance. Never load the production profile.
if CommandLine.arguments.dropFirst().first == "--ssh-askpass" {
 exit(SSHLoginEnvironment.answer(prompt:CommandLine.arguments.dropFirst(2).first ?? "SSH authentication"))
}
let auditRoot=FileManager.default.temporaryDirectory.appendingPathComponent("macscp-visible-audit-"+UUID().uuidString)
let fixture=auditRoot.appendingPathComponent("files")
try FileManager.default.createDirectory(at:fixture.appendingPathComponent("项目/数据/结果"),withIntermediateDirectories:true)
try Data("MacSCP isolated UI acceptance\n".utf8).write(to:fixture.appendingPathComponent("单个文件.txt"))
try Data("hidden\n".utf8).write(to:fixture.appendingPathComponent(".隐藏文件"))
let suite="local.macscp.audit."+UUID().uuidString
let defaults=UserDefaults(suiteName:suite)!
let app=NSApplication.shared
let delegate=App(defaults:defaults,dataDirectory:auditRoot.appendingPathComponent("profile"),initialLocalDirectory:fixture.path,frameAutosaveName:nil,mainWindowTitle:"MacSCP · 界面验收（独立测试文件）",masterArgumentsProvider:{_,_ in throw SFTPError.message("界面验收版不建立网络连接，请在正式版连接服务器。")})
app.delegate=delegate
app.setActivationPolicy(.regular)
fputs("Audit fixture: \(auditRoot.path)\n",stderr)
let cleanup=NotificationCenter.default.addObserver(forName:NSApplication.willTerminateNotification,object:app,queue:nil){_ in
 defaults.removePersistentDomain(forName:suite)
 try? FileManager.default.removeItem(at:auditRoot)
}
app.run()
