import Foundation
@main struct FTPSiteImportTests {
 static func check(_ value:Bool){precondition(value)}
 static func row(_ settings:String)throws->SiteImportCandidate{try SiteImportPlan.read(Data(("[Sessions\\FTP]\nHostName=ftp.example\nUserName=alice\nFSProtocol=5\n"+settings).utf8),fileExtension:"ini").candidates[0]}
 static func main()throws{
  for (encryption,kind,port) in [(0,FileProtocol.ftp,21),(1,.ftpsImplicit,990),(2,.ftpsExplicit,21),(3,.ftpsExplicit,21)]{let value=try row("Ftps=\(encryption)");precondition(value.eligible && value.session!.fileProtocol==kind && value.session!.port==port && !value.session!.ftpSettings.allowNonAtomicWrites && value.session!.ftpSettings.prefersSSLAuth == (encryption==2))}
  let inherited=try SiteImportPlan.read(Data("[Sessions\\Default%20Settings]\nFSProtocol=5\nFtps=1\nTimeout=37\nFtpUseMlsd=1\nPortNumber=2121\n[Sessions\\%EF%BB%BF%E6%B5%8B%E8%AF%95]\nHostName=alice@ftp.example\nRemoteDirectory=/data%2520\nLocalDirectory=C:%5Cdata\nPasswordPlain=KEEP-THIS-OUT%GG\nPassword=NOT-EXPORTED\n".utf8),fileExtension:"ini").candidates[0]
  precondition(inherited.name=="测试" && inherited.session!.fileProtocol == .ftpsImplicit && inherited.session!.port==2121 && inherited.session!.user=="alice" && inherited.session!.ftpSettings.connectTimeout==37 && inherited.session!.ftpSettings.listingMode == .legacy && inherited.session!.remotePath=="/data%20" && inherited.session!.localPath==nil && inherited.session!.options==nil)
  for (raw,mode) in [("0",FTPListingMode.machineOnly),("on",.machineOnly),("1",.legacy),("off",.legacy),("2",.automatic),("auto",.automatic)]{check(try row("FtpUseMlsd=\(raw)").session!.ftpSettings.listingMode==mode)}
  for unsupported in ["Ftps=99","Ftps=unknown","FtpSecure=3","FtpPasvMode=0","FtpAccount=account","FtpProxyLogonType=1","PostLoginCommands=DO-NOT-EXECUTE%0ASITE%20COMMAND","Utf=0","Utf=bad","FtpForcePasvIp2=off","FtpListAll=on","FtpUseMlsd=bad","Timeout=0","Timeout=601","Timeout=no","Ftps=3\nSshHostKey=pinned-fingerprint","Ftps=3\nTlsCertificateFile=C:%5Ccert.pem","Ftps=3\nMinTlsVersion=13","Ftps=3\nMaxTlsVersion=12","Ftps=3\nSslSessionReuse=off","Ftps=1\nFtps=3"]{let value=try row(unsupported);precondition(!value.eligible && value.issue != nil && !value.detail.contains("DO-NOT-EXECUTE"))}
  for utf in ["1","2","on","auto"]{check(try row("Utf=\(utf)").eligible)}
  let upgraded=try row("Ftps=2\nMinTlsVersion=10");precondition(upgraded.eligible && upgraded.notes.contains{$0.contains("1.2")} && upgraded.detail.contains("AUTH SSL"))
  let root=FileManager.default.temporaryDirectory.appendingPathComponent("ftp-site-import-"+UUID().uuidString);defer{try? FileManager.default.removeItem(at:root)}
  let store=try SiteStore(url:root.appendingPathComponent("sites.json"));try store.save(Session(name:"SSH on 21",host:"ftp.example",user:"alice",port:21,key:""))
  var old=try row("Ftps=3").session!;old.ftpOptions=FTPSiteOptions(allowNonAtomicWrites:true);try store.save(old)
  let incoming=try SiteImportPlan.read(Data("[Sessions\\FTP]\nHostName=ftp.example\nUserName=alice\nFSProtocol=5\nFtps=3\nFtpUseMlsd=off\nTimeout=23\nPasswordPlain=KEEP-THIS-OUT\n".utf8),fileExtension:"ini"),selection=SiteImportSelection(plan:incoming,existing:store.sites)
  precondition(selection.action(incoming.candidates[0])=="更新已有" && selection.changes(incoming.candidates[0]).contains{$0.0=="FTP 非原子写入" && $0.1=="true" && $0.2=="false"})
  selection.setChecked(0,true);check(try selection.apply(to:store)==1);precondition(store.sites.count==2 && store.sites.contains{$0.fileProtocol == .sftp} && store.sites.contains{$0.fileProtocol == .ftpsExplicit && $0.ftpSettings.listingMode == .legacy && !$0.ftpSettings.allowNonAtomicWrites})
  try store.save(inherited.session!);let exported=try store.exportData();precondition(!String(decoding:exported,as:UTF8.self).contains("KEEP-THIS-OUT"));check(try SiteStore(url:store.url).sites==store.sites)
  let legacy=Data("{\"allowNonAtomicWrites\":false,\"preserveTime\":false,\"preservePermissions\":false}".utf8);let options=try JSONDecoder().decode(FTPSiteOptions.self,from:legacy);precondition(options.connectTimeout==15 && options.listingMode == .automatic && !options.prefersSSLAuth)
  print("PASS: official WinSCP Ftps 0/1/2/3 mapping/default and custom ports, inherited Unicode/paths, MLSD on/off/auto, timeout and SSL command order, unsupported settings blocked, no plaintext passwords/commands, cross-protocol identity, explicit read-only update preview, persistence and legacy FTP JSON; no network")
 }
}
