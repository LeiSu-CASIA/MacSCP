import Foundation
@main struct LocalTrashTests {
 static func check(_ value:Bool){precondition(value)}
 static func main()throws{
  let fm=FileManager.default,root=fm.temporaryDirectory.appendingPathComponent("local-trash-"+UUID().uuidString),source=root.appendingPathComponent("source"),bin=root.appendingPathComponent("test-recycle"),outside=root.appendingPathComponent("outside")
  for dir in [source,bin,outside]{try fm.createDirectory(at:dir,withIntermediateDirectories:true)};defer{try? fm.removeItem(at:root)}
  try Data("outside".utf8).write(to:outside.appendingPathComponent("keep"))
  func put(_ name:String,_ data:String="old")throws{try Data(data.utf8).write(to:source.appendingPathComponent(name))}
  for name in ["a.txt","b.txt","newline\nname"]{try put(name)};try fm.createDirectory(at:source.appendingPathComponent("folder"),withIntermediateDirectories:false);try Data("nested".utf8).write(to:source.appendingPathComponent("folder/child"))
  try fm.createSymbolicLink(atPath:source.appendingPathComponent("alias").path,withDestinationPath:outside.path);try fm.createSymbolicLink(atPath:source.appendingPathComponent("broken").path,withDestinationPath:root.appendingPathComponent("missing").path)
  let plan=try LocalTrashPlan.prepare(directory:source.path,names:["a.txt","b.txt","folder","alias","broken","newline\nname","a.txt"])
  check(plan.items.count==6 && plan.preview.contains("newline\\nname") && fm.fileExists(atPath:source.appendingPathComponent("a.txt").path))
  var moves=0
  let report=try LocalTrashExecutor.execute(plan,cancellation:LocalTrashCancellation(),trash:{url in if url.lastPathComponent=="b.txt"{throw SFTPError.message("fixture denial")};moves+=1;try fm.moveItem(at:url,to:bin.appendingPathComponent(url.lastPathComponent))})
  check(report.moved.count==5 && report.failures.count==1 && moves==5 && fm.fileExists(atPath:source.appendingPathComponent("b.txt").path))
  check(try Data(contentsOf:outside.appendingPathComponent("keep"))==Data("outside".utf8));check(try fm.destinationOfSymbolicLink(atPath:bin.appendingPathComponent("alias").path)==outside.path)
  check(try Data(contentsOf:bin.appendingPathComponent("folder/child"))==Data("nested".utf8))
  try put("a.txt");let changed=try LocalTrashPlan.prepare(directory:source.path,names:["a.txt","b.txt"]);try put("b.txt","changed")
  var attempted=0;do{_ = try LocalTrashExecutor.execute(changed,cancellation:LocalTrashCancellation(),trash:{_ in attempted+=1});fatalError("stale selection accepted")}catch{};check(attempted==0)
  let replaced=try LocalTrashPlan.prepare(directory:source.path,names:["a.txt"]);try put("replacement");try fm.moveItem(at:source.appendingPathComponent("a.txt"),to:root.appendingPathComponent("held-a"));try fm.moveItem(at:source.appendingPathComponent("replacement"),to:source.appendingPathComponent("a.txt"));try fm.setAttributes([.modificationDate:replaced.items[0].signature.modified!],ofItemAtPath:source.appendingPathComponent("a.txt").path)
  do{_ = try LocalTrashExecutor.execute(replaced,cancellation:LocalTrashCancellation(),trash:{_ in attempted+=1});fatalError("replaced inode accepted")}catch{};check(attempted==0)
  for name in ["one","two","three"]{try put(name)}
  let interrupted=try LocalTrashPlan.prepare(directory:source.path,names:["one","two","three"]),token=LocalTrashCancellation()
  let stopped=try LocalTrashExecutor.execute(interrupted,cancellation:token,trash:{url in try fm.moveItem(at:url,to:bin.appendingPathComponent(url.lastPathComponent));token.cancel()});check(stopped.cancelled && stopped.moved.count==1 && fm.fileExists(atPath:source.appendingPathComponent("two").path))
  let cancelled=LocalTrashCancellation();cancelled.cancel();let before=try LocalTrashExecutor.execute(interrupted,cancellation:cancelled,trash:{_ in fatalError()});check(before.cancelled && before.moved.isEmpty)
  let inFlight=try LocalTrashPlan.prepare(directory:source.path,names:["two","three"])
  let changedLater=try LocalTrashExecutor.execute(inFlight,cancellation:LocalTrashCancellation(),trash:{url in try fm.moveItem(at:url,to:bin.appendingPathComponent(url.lastPathComponent));try put("three","changed after first move")})
  check(changedLater.moved.count==1 && changedLater.failures.count==1 && fm.fileExists(atPath:source.appendingPathComponent("three").path))
  let ancestor=try LocalTrashPlan.prepare(directory:source.path,names:["three"]);try fm.moveItem(at:source,to:root.appendingPathComponent("held-directory"));try fm.createSymbolicLink(atPath:source.path,withDestinationPath:outside.path)
  do{_ = try LocalTrashExecutor.execute(ancestor,cancellation:LocalTrashCancellation(),trash:{_ in attempted+=1});fatalError("changed ancestor accepted")}catch{};check(attempted==0)
  for names in [[".."],["."],["/"],["a/b"],["\0"],[]]{do{_ = try LocalTrashPlan.prepare(directory:outside.path,names:names);fatalError("bad name accepted")}catch{}}
  check(try Data(contentsOf:outside.appendingPathComponent("keep"))==Data("outside".utf8))
  print("PASS: full batch recycle plan, deduplicated/escaped paths, directory and symlink moves without following, partial errors, all-before-write validation, inode replacement and ancestor substitution rejection, cancellation before/during batch; injected fixture recycler only")
 }
}
