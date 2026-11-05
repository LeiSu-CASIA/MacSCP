import Cocoa
@main struct NativeConnectionFormTests {
 static func main()throws{
  NSApplication.shared.setActivationPolicy(.prohibited)
  let root=FileManager.default.temporaryDirectory.appendingPathComponent("connection-form-"+UUID().uuidString);defer{try? FileManager.default.removeItem(at:root)}
  let store=try SiteStore(url:root.appendingPathComponent("sites.json")),legacy=Session(name:"SFTP",host:"same.example",user:"demo",port:21,key:"")
  let oldData=Data("{\"name\":\"old\",\"host\":\"same.example\",\"user\":\"demo\",\"port\":21,\"key\":\"\"}".utf8)
  let restored=try JSONDecoder().decode(Session.self,from:oldData);precondition(restored.fileProtocol == .sftp && restored.identity=="demo@same.example:21")
  try store.save(legacy)
  let form=ConnectionForm(store:store,selected:nil,localPath:root.path);form.host.stringValue="same.example";form.user.stringValue="demo"
  for kind in FileProtocol.allCases{form.kind.selectItem(at:FileProtocol.allCases.firstIndex(of:kind)!);form.protocolChanged();precondition(Int(form.port.stringValue)==kind.defaultPort);precondition(form.ssh.isHidden == (kind != .sftp));precondition(form.password.isEnabled == (kind != .sftp));precondition(form.key.isEnabled == (kind == .sftp))}
  form.port.stringValue="2121";form.kind.selectItem(at:1);form.protocolChanged();precondition(form.port.stringValue=="2121")
  form.port.stringValue="21";form.password.stringValue="secret-not-exported";form.write.state = .on
  let ftp=try form.value(localPath:root.path);precondition(ftp.fileProtocol == .ftp && ftp.identity != legacy.identity && ftp.key.isEmpty && ftp.options==nil && ftp.ftpSettings.allowNonAtomicWrites)
  try store.save(ftp);precondition(store.sites.count==2);let exported=try store.exportData();precondition(!String(decoding:exported,as:UTF8.self).contains("secret-not-exported"));let loaded=try SiteStore(url:store.url);precondition(loaded.sites==store.sites)
  let plan=try SiteImportPlan.read(exported,fileExtension:"json");precondition(plan.candidates.allSatisfy{$0.eligible} && plan.candidates.contains{$0.protocolName.contains("FTP") && $0.session?.fileProtocol == .ftp})
  var invalid=ftp;invalid.key="/private/key";do{_ = try invalid.validated();fatalError("SSH key accepted for FTP")}catch{}
  do{_ = try SSHArguments.master(ftp,socket:"unused");fatalError("FTP reached SSH")}catch{}
  form.load(ftp);precondition(form.password.stringValue.isEmpty && form.write.state == .on)
  let window=NSWindow(contentRect:form.frame,styleMask:[.titled],backing:.buffered,defer:false);window.isReleasedWhenClosed=false;window.contentView=form;window.appearance=NSAppearance(named:.aqua);form.layoutSubtreeIfNeeded();precondition(!window.isVisible && form.password.frame.maxX<=form.bounds.width && form.host.frame.minY>form.password.frame.minY);if CommandLine.arguments.count>1,let bitmap=form.bitmapImageRepForCachingDisplay(in:form.bounds){form.cacheDisplay(in:form.bounds,to:bitmap);let canvas=NSImage(size:form.bounds.size);canvas.lockFocus();NSColor.windowBackgroundColor.setFill();form.bounds.fill();let snapshot=NSImage(size:form.bounds.size);snapshot.addRepresentation(bitmap);snapshot.draw(in:form.bounds);canvas.unlockFocus();if let tiff=canvas.tiffRepresentation,let png=NSBitmapImageRep(data:tiff)?.representation(using:.png,properties:[:]){try png.write(to:URL(fileURLWithPath:CommandLine.arguments[1]))}};window.close()
  print("PASS: hidden multi-protocol login form, default/custom ports, SSH/FTP controls, no saved/exported password, legacy SFTP identity and cross-protocol separation, FTP JSON preview/persistence, SSH transport refusal; no network or visible authentication")
 }
}
