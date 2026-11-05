import Foundation
@main struct SiteImportTests {
 static func verify(_ condition:@autoclosure ()throws->Bool){do{let value=try condition();precondition(value)}catch{fatalError("unexpected import error: \(error)")}}
 static func rejected(_ block:()throws->Void){do{try block();fatalError("expected import rejection")}catch{}}
 static func main()throws {
  let fm=FileManager.default,root=fm.temporaryDirectory.appendingPathComponent("site-import-"+UUID().uuidString)
  try fm.createDirectory(at:root,withIntermediateDirectories:true);defer{try? fm.removeItem(at:root)}
  let store=try SiteStore(url:root.appendingPathComponent("sites.json"))
  let old=Session(name:"old",host:"one.example",user:"alice",port:2222,key:"");try store.save(old)
  let fixture="""
  [Configuration\\Interface]
  Random=ignored
  [Sessions\\Default%20Settings]
  FSProtocol=2
  PortNumber=2222
  Compression=1
  Timeout=15
  PingType=1
  PingIntervalSecs=12
  [Sessions\\%EF%BB%BF%E5%B7%A5%E4%BD%9C%2Fserver%20one]
  HostName=one.example
  UserName=alice
  LocalDirectory=C:%5CUsers%5Calice%5CDocuments
  RemoteDirectory=%EF%BB%BF%2Fhome%2Falice%2F%E6%95%B0%E6%8D%AE%2520
  PublicKeyFile=C:%5Ckeys%5Cprivate.ppk
  PasswordPlain=DO-NOT-KEEP-SECRET%GG
  Password=012345ABCDEF
  PostLoginCommands=DO-NOT-EXECUTE-THIS
  [Sessions\\alias%20same%20endpoint]
  HostName=one.example
  UserName=alice
  RemoteDirectory=/different
  [Sessions\\two]
  HostName=bob@two.example
  PublicKeyFile=~/.ssh/id_ed25519
  LocalDirectory=~/Downloads
  FSProtocol=1
  [Sessions\\ftp]
  HostName=ftp.example
  FSProtocol=5
  [Sessions\\proxy]
  HostName=proxy.example
  ProxyMethod=Cmd
  ProxyLocalCommand=DO-NOT-EXECUTE-THIS
  [Sessions\\tunnel]
  HostName=tunnel.example
  Tunnel=1
  [Sessions\\custom]
  HostName=custom.example
  SftpServer=custom%20command
  [Sessions\\broken]
  HostName=-oProxyCommand=bad
  [Sessions\\two\\Bookmarks]
  HostName=must-not-import.example
  """
  let data=Data(fixture.utf8),plan=try SiteImportPlan.read(data,fileExtension:"ini")
  precondition(plan.format == .winSCPINI && plan.candidates.count==8)
  let first=plan.candidates[0],two=plan.candidates[2]
  precondition(first.name=="工作/server one" && first.eligible && first.session!.key.isEmpty && first.session!.localPath==nil)
  precondition(first.session!.remotePath=="/home/alice/数据%20" && first.notes.count==3)
  precondition(first.session!.sshOptions==SSHOptions(jumpHost:"",connectTimeout:15,keepAliveInterval:12,keepAliveCount:3,compression:true))
  precondition(two.session!.host=="two.example" && two.session!.user=="bob" && two.session!.key=="~/.ssh/id_ed25519")
  precondition(two.session!.localPath==NSHomeDirectory()+"/Downloads" && two.notes.count==2)
  precondition(plan.candidates[3].session?.fileProtocol == .ftp && plan.candidates.dropFirst(4).allSatisfy{!$0.eligible})
  precondition(!plan.candidates.map(\.detail).joined().contains("DO-NOT-KEEP") && !plan.candidates.map(\.detail).joined().contains("DO-NOT-EXECUTE"))
  let selection=SiteImportSelection(plan:plan,existing:store.sites)
  precondition(selection.checked.isEmpty && selection.action(first)=="更新已有")
  selection.selectAllEligible();precondition(selection.checked==[0,2,3])
  selection.setChecked(1,true);precondition(selection.checked==[1,2,3])
  selection.setChecked(3,true);precondition(selection.checked==[1,2,3])
  selection.selectNone();selection.setChecked(0,true)
  verify(try selection.apply(to:store)==1)
  precondition(store.sites.count==1 && store.sites[0].name==first.name && store.sites[0].remotePath==first.session!.remotePath)
  let serialized=try store.exportData(),text=String(decoding:serialized,as:UTF8.self)
  precondition(!text.contains("Password") && !text.contains("DO-NOT") && !text.contains("ppk"))
  verify((try fm.attributesOfItem(atPath:store.url.path)[.posixPermissions] as! NSNumber).intValue==0o600)
  let stale=SiteImportSelection(plan:plan,existing:store.sites);stale.setChecked(0,true)
  var changed=store.sites[0];changed.name="changed after preview";try store.save(changed)
  let before=try Data(contentsOf:store.url)
  rejected{_ = try stale.apply(to:store)};verify(try Data(contentsOf:store.url)==before)
  stale.refreshExisting(store.sites);verify(try stale.apply(to:store)==1)
  let json=try SiteImportPlan.read(store.exportData());precondition(json.format == .macSCPJSON && json.candidates.count==1)
  let utf8BOM=Data([0xEF,0xBB,0xBF])+data;verify(try SiteImportPlan.read(utf8BOM).candidates[0].name==first.name)
  for encoding in [String.Encoding.utf16LittleEndian,.utf16BigEndian] {
   let bom=encoding == .utf16LittleEndian ? Data([0xFF,0xFE]) : Data([0xFE,0xFF])
   verify(try SiteImportPlan.read(bom+fixture.data(using:encoding)!,fileExtension:"ini").candidates[0].name==first.name)
  }
  rejected{_ = try SiteImportPlan.read(Data(repeating:65,count:SiteImportPlan.maximumBytes+1),fileExtension:"ini")}
  rejected{_ = try SiteImportPlan.read(Data("[Sessions\\a\nHostName=x".utf8),fileExtension:"ini")}
  rejected{_ = try SiteImportPlan.read(Data("[Sessions\\a]\nHostName=x\n[Sessions\\a]\nHostName=y".utf8),fileExtension:"ini")}
  rejected{_ = try SiteImportPlan.read(Data("[Sessions\\Default%20Settings]\nFSProtocol=1\n[Sessions\\%44efault%20Settings]\nFSProtocol=2\n[Sessions\\a]\nHostName=x".utf8),fileExtension:"ini")}
  for line in ["HostName=x%0Acommand","HostName=x%GG","HostName=%D6%D0","PortNumber=0","PortNumber=no","Timeout=999","HostName=alice@x\nUserName=bob","HostName=x\nHostName=y"] {
   let p=try SiteImportPlan.read(Data(("[Sessions\\a]\n"+line).utf8),fileExtension:"ini");precondition(p.candidates.count==1 && !p.candidates[0].eligible)
  }
  let factory=try SiteImportPlan.read(Data("[Sessions\\factory]\nHostName=default.example".utf8),fileExtension:"ini").candidates[0].session!
  precondition(factory.sshOptions.connectTimeout==15 && factory.sshOptions.keepAliveInterval==0)
  for (settings,interval) in [("PingInterval=2\nPingIntervalSecs=5",125),("PingInterval=2",150),("PingInterval=2\nPingIntervalSecs=-1\nPingIntervalSec=7",127),("PingInterval=0\nPingIntervalSecs=0",30)] {
   let p=try SiteImportPlan.read(Data(("[Sessions\\keepalive]\nHostName=x\nPingType=1\n"+settings).utf8),fileExtension:"ini")
   precondition(p.candidates[0].session!.sshOptions.keepAliveInterval==interval)
  }
  var bulk=[Session]();for i in 0..<2000{bulk.append(Session(name:"row \(i)",host:"host\(i).example",user:"test",port:22,key:""))}
  _ = try store.importSessions(bulk);var replacement=bulk[20];replacement.name="last duplicate wins";_ = try store.importSessions([bulk[20],replacement])
  precondition(store.sites.count==2001 && store.sites.last?.name=="last duplicate wins")
  print("PASS: real WinSCP field/escaped Unicode/default mappings, Windows path/PPK notices, unsupported protocol/proxy/tunnel/custom command rows blocked, passwords/commands excluded, duplicate endpoint selection, selected-only atomic merge, stale preview rejection, JSON/UTF8/BOM/UTF16, malformed/oversize rejection, private persistence and linear bulk replacement; no network")
 }
}
