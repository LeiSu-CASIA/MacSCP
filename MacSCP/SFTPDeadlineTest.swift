import Foundation
@main struct SFTPDeadlineTests {
 static func check(_ value:Bool){precondition(value)}
 static func main()throws{
  let client=try SFTPClient(command:"/usr/libexec/sftp-server",arguments:[],requestTimeout:0.15);defer{client.close()}
  _ = try client.canonical(".");Thread.sleep(forTimeInterval:0.35)
  check(client.process.isRunning);_ = try client.canonical(".")
  let start=Date();do{_ = try SFTPClient(command:"/bin/sleep",arguments:["5"],requestTimeout:0.15);fatalError("stuck handshake accepted")}catch{};check(Date().timeIntervalSince(start)<2)
  let server="""
import sys,struct,time
header=sys.stdin.buffer.read(4)
length=struct.unpack('>I',header)[0]
sys.stdin.buffer.read(length)
sys.stdout.buffer.write(struct.pack('>I',5)+bytes([2])+struct.pack('>I',3))
sys.stdout.buffer.flush()
while sys.stdin.buffer.read(1):
 time.sleep(5)
"""
  let stuck=try SFTPClient(command:"/usr/bin/python3",arguments:["-c",server],requestTimeout:0.4);defer{stuck.close()}
  let request=Date();do{_ = try stuck.canonical(".");fatalError("stuck request accepted")}catch{};check(Date().timeIntervalSince(request)<2)
  for invalid in [0.0,-1.0,Double.infinity]{do{_ = try SFTPClient(command:"/unused",arguments:[],requestTimeout:invalid);fatalError("invalid timeout accepted")}catch{}}
  print("PASS: completed SFTP responses cancel their timers so local comparison/hash idle time does not kill the channel; blocked handshake and blocked request still terminate within deadline; own stdio processes only")
 }
}
