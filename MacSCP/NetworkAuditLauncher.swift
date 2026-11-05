import Cocoa
if CommandLine.arguments.dropFirst().first == "--ssh-askpass" {
 exit(SSHLoginEnvironment.answer(prompt:CommandLine.arguments.dropFirst(2).first ?? "SSH authentication"))
}
struct NetworkAuditFixture:Decodable {
 let root:String;let port:Int;let user:String;let key:String;let config:String
 func validate(_ site:Session)throws {
  guard site.host=="127.0.0.1",site.port==port,site.user==user,site.key==key,site.sshOptions.jumpHost.isEmpty else {
   throw SFTPError.message("此验收实例仅允许指定的本机临时服务器。")
  }
 }
}
let resource=Bundle.main.resourceURL!.appendingPathComponent("gui-network-fixture.json")
let fixture=try JSONDecoder().decode(NetworkAuditFixture.self,from:Data(contentsOf:resource))
let root=URL(fileURLWithPath:fixture.root)
let profile=root.appendingPathComponent("profile")
let sites=try SiteStore(url:profile.appendingPathComponent("sites.json"))
try sites.save(Session(name:"独立本机 GUI 验收",host:"127.0.0.1",user:fixture.user,port:fixture.port,key:fixture.key,localPath:root.appendingPathComponent("local").path,remotePath:root.appendingPathComponent("remote").path))
let suite="local.macscp.networkaudit."+UUID().uuidString
let defaults=UserDefaults(suiteName:suite)!
let app=NSApplication.shared
let delegate=App(defaults:defaults,dataDirectory:profile,initialLocalDirectory:root.appendingPathComponent("local").path,frameAutosaveName:nil,mainWindowTitle:"MacSCP · 本机网络验收（独立测试文件）",masterArgumentsProvider:{site,socket in
 try fixture.validate(site)
 return ["-F",fixture.config]+(try SSHArguments.master(site,socket:socket))
},clientProvider:{site,socket in
 try fixture.validate(site)
 return try SFTPClient(arguments:["-F",fixture.config]+SSHArguments.sftp(site,socket:socket))
})
app.delegate=delegate
app.setActivationPolicy(.regular)
let cleanup=NotificationCenter.default.addObserver(forName:NSApplication.willTerminateNotification,object:app,queue:nil){_ in defaults.removePersistentDomain(forName:suite)}
app.run()
