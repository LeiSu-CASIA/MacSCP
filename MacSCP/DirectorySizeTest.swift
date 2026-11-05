import Foundation
import Darwin
@main struct DirectorySizeTests {
 static func check(_ value:Bool){precondition(value)}
 static func main()throws{
  let fm=FileManager.default,root=fm.temporaryDirectory.appendingPathComponent("directory-size-"+UUID().uuidString),selected=root.appendingPathComponent("selected"),outside=root.appendingPathComponent("outside")
  try fm.createDirectory(at:selected.appendingPathComponent("nested"),withIntermediateDirectories:true);try fm.createDirectory(at:selected.appendingPathComponent("empty"),withIntermediateDirectories:true);try fm.createDirectory(at:outside,withIntermediateDirectories:true)
  defer{try? fm.removeItem(at:root)}
  for (name,count) in [("a.txt",3),(".hidden",4),("nested/数据.csv",5)]{try Data(repeating:1,count:count).write(to:selected.appendingPathComponent(name))}
  try Data(repeating:2,count:1000).write(to:outside.appendingPathComponent("unselected"))
  try fm.createSymbolicLink(atPath:selected.appendingPathComponent("outside-link").path,withDestinationPath:outside.path)
  try fm.createSymbolicLink(atPath:selected.appendingPathComponent("cycle").path,withDestinationPath:selected.path)
  try fm.createSymbolicLink(atPath:selected.appendingPathComponent("broken").path,withDestinationPath:root.appendingPathComponent("missing").path)
  check(mkfifo(selected.appendingPathComponent("fifo").path,0o600)==0)
  let paths=[selected.path,selected.appendingPathComponent("a.txt").path,selected.path+"/./nested",selected.path]
  let local=try DirectorySizeScanner.local(paths:paths,cancellation:DirectorySizeCancellation())
  check(local.complete && local.bytes==12 && local.files==3 && local.directories==3 && local.links==3 && local.other==1 && local.scanned==10)
  let c=try SFTPClient(command:"/usr/libexec/sftp-server",arguments:[]);defer{c.close()}
  let remote=try DirectorySizeScanner.remote(paths:paths,client:c,cancellation:DirectorySizeCancellation())
  check(remote.complete && remote.bytes==local.bytes && remote.files==local.files && remote.links==local.links && remote.other==1 && remote.directories==local.directories)
  do{_ = try c.list(selected.path,maximumEntries:2);fatalError("must enforce listing bound")}catch{}
  check(try c.attributes(selected.path) != nil) // Listing limit keeps the SFTP request stream synchronized.
  let link=try DirectorySizeScanner.local(paths:[selected.appendingPathComponent("outside-link").path],cancellation:DirectorySizeCancellation());check(link.bytes==0 && link.links==1 && link.directories==0)
  let limited=try DirectorySizeScanner.local(paths:[selected.path],cancellation:DirectorySizeCancellation(),limits:.init(entries:3,depth:256));check(limited.limited && !limited.complete && limited.scanned<=3)
  let depth=try DirectorySizeScanner.local(paths:[selected.path],cancellation:DirectorySizeCancellation(),limits:.init(entries:100,depth:1));check(depth.limited && depth.bytes==7)
  let before=DirectorySizeCancellation();before.cancel();do{_ = try DirectorySizeScanner.local(paths:[selected.path],cancellation:before);fatalError("must cancel")}catch{}
  let during=DirectorySizeCancellation();do{_ = try DirectorySizeScanner.remote(paths:paths,client:c,cancellation:during,progress:{_,_ in during.cancel()});fatalError("must cancel traversal")}catch{}
  var calls=0
  let changed=try DirectorySizeScanner.scan(paths:["/changed"],cancellation:DirectorySizeCancellation(),metadata:{_ in calls+=1;return .init(kind:.directory,bytes:0,signature:String(calls))},list:{_ in ["not-visited"]});check(!changed.complete && changed.scanned==1 && changed.warningCount==1 && calls==2)
  let warnings=try DirectorySizeScanner.scan(paths:(0..<150).map{"/denied\($0)"},cancellation:DirectorySizeCancellation(),metadata:{_ in throw SFTPError.message("denied")},list:{_ in fatalError()});check(warnings.warningCount==150 && warnings.warnings.count==100 && !warnings.complete)
  let overflow=try DirectorySizeScanner.scan(paths:["/a","/b"],cancellation:DirectorySizeCancellation(),metadata:{_ in .init(kind:.file,bytes:UInt64.max,signature:"")},list:{_ in []});check(overflow.bytes==UInt64.max && overflow.files==1 && overflow.warningCount==1 && !overflow.complete)
  for bad in ["relative","/a/../b","/bad\0path"]{do{_ = try DirectorySizeScanner.path(bad);fatalError("invalid root accepted")}catch{}}
  let after=try Data(contentsOf:outside.appendingPathComponent("unselected"));check(after==Data(repeating:2,count:1000))
  print("PASS: real local/SFTP logical sizes and counts, hidden files, empty/Unicode directories, overlapping roots, no symlink/cycle/FIFO traversal, cancellation, entry/depth bounds, bounded SFTP listing and stream reuse, changing directories, capped warnings and overflow; fixture only")
 }
}
