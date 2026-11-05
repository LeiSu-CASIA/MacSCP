import Cocoa
@main struct NativeNavigationTests {
 static func main(){NSApplication.shared.setActivationPolicy(.prohibited);let pane=Pane("本地文件");pane.acceptPath("/tmp/displayed");pane.entries=[Entry(name:"file.txt",size:1,dir:false)];pane.reload();pane.togglePathEdit();pane.path.stringValue="/tmp/not-submitted";pane.controlTextDidChange(Notification(name:NSControl.textDidChangeNotification,object:pane.path));precondition(pane.currentPath=="/tmp/displayed" && pane.location.draft=="/tmp/not-submitted");precondition(pane.location.child("file.txt")=="/tmp/displayed/file.txt");pane.updateBreadcrumbs();precondition(pane.breadcrumbs.pathItems.map{$0.title}==["/","tmp","displayed"]);pane.togglePathEdit();pane.path.stringValue="/tmp/another";pane.togglePathEdit();precondition(pane.path.stringValue==pane.currentPath);pane.togglePathEdit();pane.path.stringValue="/tmp/cancelled";precondition(pane.control(pane.path,textView:NSTextView(),doCommandBy:#selector(NSResponder.cancelOperation(_:))));precondition(!pane.isEditingPath && pane.path.stringValue==pane.currentPath);checkBreadcrumbNavigation();pane.acceptPath("/tmp/successful");precondition(pane.currentPath=="/tmp/successful");pane.frame=NSRect(x:0,y:0,width:590,height:500);if pane.treeVisible{pane.toggleTree()};pane.layoutSubtreeIfNeeded();let fullWidth=pane.table.enclosingScrollView!.frame.width;pane.toggleTree();pane.layoutSubtreeIfNeeded();precondition(pane.directoryTree.frame.width>=180 && pane.table.enclosingScrollView!.frame.width>100 && pane.table.enclosingScrollView!.frame.width<fullWidth);pane.toggleTree();print("PASS: real pane keeps displayed operation path separate from draft address, breadcrumbs use committed path, cancel edit restores path, successful navigation commits")}
 static func checkBreadcrumbNavigation(){
  // No visible windows or existing user directories are used.
  let fm=FileManager.default
  let root=fm.temporaryDirectory.appendingPathComponent("breadcrumb-"+UUID().uuidString)
  let leaf=root.appendingPathComponent("中文 空格/带%20和#号/leaf")
  try! fm.createDirectory(at:leaf,withIntermediateDirectories:true)
  defer{try? fm.removeItem(at:root)}
  let pane=Pane("面包屑测试")
  pane.acceptPath(leaf.path);pane.reload()
  let ancestor=leaf.deletingLastPathComponent().path
  var requests=[String]()
  pane.go={
   requests.append(pane.path.stringValue)
   precondition(pane.currentPath==leaf.path) // Only successful listing commits.
   pane.entries=try! LocalListing.entries(pane.path.stringValue)
   pane.acceptPath(pane.path.stringValue);pane.reload()
  }
  let clicked=pane.breadcrumbs.pathItems[pane.breadcrumbs.pathItems.count-2]
  precondition(clicked.title=="带%20和#号")
  pane.navigateBreadcrumb(clicked)
  precondition(requests==[ancestor] && pane.currentPath==ancestor)
  precondition(pane.entries.map{$0.name}.contains("leaf"))
  pane.navigateBreadcrumb(pane.breadcrumbs.pathItems.last!)
  pane.navigateBreadcrumb(clicked) // A stale component must never navigate.
  precondition(requests.count==1)
  let remote=Pane("远程文件 · 面包屑测试")
  remote.acceptPath("/home/ps/sulei/datarun/DISTIALL");remote.reload()
  remote.go={requests.append(remote.path.stringValue)}
  remote.navigateBreadcrumb(remote.breadcrumbs.pathItems[4])
  precondition(requests.count==1) // Disconnected remote pane is disabled.
  remote.path.isEnabled=true;remote.updateBreadcrumbs()
  remote.navigateBreadcrumb(remote.breadcrumbs.pathItems[4])
  precondition(requests.last=="/home/ps/sulei/datarun")
  precondition(remote.currentPath=="/home/ps/sulei/datarun/DISTIALL")
  remote.navigateBreadcrumb(remote.breadcrumbs.pathItems[0])
  precondition(requests.last=="/")
  print("PASS: pane breadcrumb routes to ancestor and root, refreshes real fixture listing, preserves Unicode/literal percent/hash, ignores current/stale/disabled items, waits for successful remote navigation")
 }
}
