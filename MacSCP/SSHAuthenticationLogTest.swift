import Foundation
@main struct SSHAuthenticationLogTests {
 static func check(_ value:Bool){precondition(value)}
 static func main()throws{
  let fm=FileManager.default,root=fm.temporaryDirectory.appendingPathComponent("ssh-report-"+UUID().uuidString);try fm.createDirectory(at:root,withIntermediateDirectories:false);defer{try? fm.removeItem(at:root)}
  let log=try SSHAuthenticationLog(root:root),writer=try FileHandle(forWritingTo:log.url)
  try writer.write(contentsOf:Data("Authenticated to example.invalid ([127.0.0.1]:22) using \"pass".utf8));_ = log.drain();check(!log.passwordAuthenticated)
  try writer.write(contentsOf:Data("word\".\r\n".utf8));check(log.drain().contains("word") && log.passwordAuthenticated)
  try writer.write(contentsOf:Data("Authenticated to example.invalid (via proxy) using \"publickey\".\n".utf8));_ = log.drain();check(!log.passwordAuthenticated)
  try writer.write(contentsOf:Data("debug: using \"password\".\n".utf8));_ = log.drain();check(!log.passwordAuthenticated)
  check((try fm.attributesOfItem(atPath:log.url.path)[.posixPermissions] as? NSNumber)?.intValue==0o600)
  log.unlink();check(!fm.fileExists(atPath:log.url.path));try writer.write(contentsOf:Data("Authenticated to example.invalid (via proxy) using \"password\".\n".utf8));_ = log.drain();check(log.passwordAuthenticated);try writer.close()
  let changed=try SSHAuthenticationLog(root:root),path=changed.url;try fm.removeItem(at:path);try Data("foreign diagnostic".utf8).write(to:path);changed.unlink();check(try Data(contentsOf:path)==Data("foreign diagnostic".utf8))
  print("PASS: private SSH client authentication log, fragmented method report/CRLF, password vs publickey/other logs, descriptor survives unlink, original mode, replaced path preserved; fixture only, no SSH connection")
 }
}
