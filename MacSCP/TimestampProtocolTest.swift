import Foundation
@main struct TimestampProtocolTests {
 static func check(_ value:Bool,file:StaticString = #file,line:UInt = #line){precondition(value,file:file,line:line)}
 static func refused(_ action:()throws->Void){do{try action();fatalError("unsafe metadata mutation accepted")}catch{}}
 static func main()throws {
  let fm=FileManager.default,root=fm.temporaryDirectory.appendingPathComponent("timestamp-protocol-"+UUID().uuidString);try fm.createDirectory(at:root,withIntermediateDirectories:true);defer{try? fm.removeItem(at:root)}
  func run(_ flags:[String],expectMutation:Bool,interrupt:Bool=false)throws {
   let audit=root.appendingPathComponent(UUID().uuidString+".json"),script=fm.currentDirectoryPath+"/MacSCP/TimestampProtocolFixture.py"
   let c=try SFTPClient(command:"/usr/bin/env",arguments:["python3",script,"--audit",audit.path]+flags);defer{c.close()}
   check(c.capabilities.contains(.timestampOnly) && !c.capabilities.contains(.atomicOverwrite))
   let expected=try c.attributes("/fixture/file")!;var progress:UInt64=0,auxiliary:UInt64=0
   c.progress={progress+=$0};c.auxiliaryProgress={auxiliary+=$0}
   let action={try c.setModificationTime("/fixture/file",to:1700000010,expected:expected,beforeCommit:{if interrupt{c.checkpoint={throw SFTPError.message("fixture cancellation")}}})}
   if expectMutation{try action()}else{refused(action)}
   let object=try JSONSerialization.jsonObject(with:Data(contentsOf:audit)) as! [String:Any],events=object["events"] as! [Int]
   check(progress==0 && auxiliary==0 && !events.contains(5) && !events.contains(6) && !events.contains(13) && !events.contains(15))
   check(object["accessed"] as? Int==1600000000)
   if expectMutation{check(object["modified"] as? Int==1700000010);check(events.contains(flags.contains("--open-denied") ? 9 : 10))}
   else{check(object["modified"] as? Int==1700000000);if !flags.contains("--deny"){check(!events.contains(9) && !events.contains(10))}}
  }
  try run([],expectMutation:true)
  try run(["--open-denied"],expectMutation:true)
  try run(["--deny"],expectMutation:false)
  try run(["--missing-times"],expectMutation:false)
  try run(["--link"],expectMutation:false)
  try run([],expectMutation:false,interrupt:true)
  print("PASS: standard SFTP FSETSTAT and permission-only SETSTAT fallback preserve reported access time, require complete metadata and refuse links/denial/cancellation; packet audit proves no file READ/WRITE/REMOVE/RMDIR, stdio fixture only")
 }
}
