import Foundation
@main struct DirectoryHistoryTests {
 static func main(){
  var history=DirectoryHistory();for path in ["/a","/b","/c","/d"]{history.visit(path)}
  precondition(history.back==["/a","/b","/c"] && history.forward.isEmpty)
  let jump=history.request(.back,steps:2)!,copy=history
  precondition(history.accepts(jump) && history==copy) // Requesting or a failed read does not consume anything.
  precondition(history.commit("/b",request:jump) && history.back==["/a"] && history.forward==["/d","/c"])
  precondition(!history.commit("/b",request:jump))
  let forward=history.request(.forward,steps:2)!
  precondition(history.commit("/d",request:forward) && history.back==["/a","/b","/c"] && history.forward.isEmpty)
  let back=history.request(.back)!;precondition(history.commit("/c",request:back));let revision=history.revision
  history.visit("/c");precondition(history.revision==revision && history.forward==["/d"])
  history.visit("/新目录 % #");precondition(history.forward.isEmpty && history.back.last=="/c")
  let stale=history.request(.back)!;history.visit("/another");precondition(!history.accepts(stale) && !history.commit(stale.target,request:stale))
  precondition(history.request(.back,steps:0)==nil && history.request(.forward)==nil)
  for i in 0..<1000{history.visit("/\(i)")};precondition(history.back.count==200 && history.back.last=="/998")
  let oldest=history.request(.back,steps:200)!;precondition(history.commit(oldest.target,request:oldest) && history.forward.count==200 && history.back.isEmpty)
  print("PASS: transactional back/forward and multi-step jumps, failure/request leaves stacks intact, stale ticket refusal, refresh preserves forward, new branch clears forward, Unicode names and bounded stacks")
 }
}
