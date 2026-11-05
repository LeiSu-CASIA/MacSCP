import Cocoa
@main struct NativeLocalTrashTests {
 static func wait(_ predicate:()->Bool){let end=Date().addingTimeInterval(10);while !predicate() && Date()<end{RunLoop.current.run(until:Date().addingTimeInterval(0.01))};precondition(predicate(),"local trash timeout")}
 static func main()throws{
  NSApplication.shared.setActivationPolicy(.prohibited)
  let fm=FileManager.default,root=fm.temporaryDirectory.appendingPathComponent("native-trash-"+UUID().uuidString),source=root.appendingPathComponent("source"),bin=root.appendingPathComponent("fixture-bin"),suite="macscp-trash-"+UUID().uuidString
  for dir in [source,bin]{try fm.createDirectory(at:dir,withIntermediateDirectories:true)}
  defer{try? fm.removeItem(at:root)}
  for name in ["a.txt","bad.txt","c.txt"]{try Data("file".utf8).write(to:source.appendingPathComponent(name))}
  let defaults=UserDefaults(suiteName:suite)!;defer{defaults.removePersistentDomain(forName:suite)}
  let app=App(defaults:defaults,dataDirectory:root.appendingPathComponent("profile"),initialLocalDirectory:source.path,automaticLogin:false,showsMainWindow:false,frameAutosaveName:nil,clientProvider:{_,_ in fatalError("unexpected server")})
  app.applicationDidFinishLaunching(Notification(name:NSApplication.didFinishLaunchingNotification));defer{app.window.close()}
  let lock=NSLock();var moves=0;var presented:LocalTrashController?
  app.localTrashHandler={url in if url.lastPathComponent=="bad.txt"{throw SFTPError.message("fixture permission denied")};lock.lock();moves+=1;lock.unlock();try fm.moveItem(at:url,to:bin.appendingPathComponent(url.lastPathComponent))}
  app.localTrashPresenter={controller in presented=controller;precondition(!controller.window!.isVisible)}
  app.local.table.selectAll(nil);app.paneCommand(true,"delete");wait{presented != nil}
  let controller=presented!;precondition(controller.plan.items.count==3 && moves==0 && !controller.started && !controller.busy)
  for size in [NSSize(width:700,height:480),NSSize(width:560,height:400)]{controller.window!.setContentSize(size);controller.window!.contentView!.layoutSubtreeIfNeeded();precondition(controller.output.enclosingScrollView!.frame.height>=160 && controller.startButton.frame.width>60 && controller.window!.contentView!.frame.width<=size.width+1)}
  controller.start();controller.start();wait{!controller.busy};precondition(controller.report?.moved.count==2 && controller.report?.failures.count==1 && moves==2 && controller.output.string.contains("bad.txt") && controller.output.string.contains("fixture permission denied"))
  precondition(app.local.entries.filter{$0.name != ".."}.map{$0.name}==["bad.txt"] && fm.fileExists(atPath:source.appendingPathComponent("bad.txt").path));controller.close();precondition(app.localTrashWindows.isEmpty)
  // Changing an item after preview prevents all writes in that preview.
  let stalePlan=try LocalTrashPlan.prepare(directory:source.path,names:["bad.txt"]);try Data("changed".utf8).write(to:source.appendingPathComponent("bad.txt"))
  let stale=app.makeLocalTrashController(stalePlan);stale.start();wait{!stale.busy};precondition(stale.report==nil && moves==2 && stale.message.stringValue.contains("未开始移动"));stale.close()
  // Closing a running window keeps it tracked until the current item finishes, so Quit cannot cut off a batch.
  for name in ["one","two","three"]{try Data("pending".utf8).write(to:source.appendingPathComponent(name))}
  let entered=DispatchSemaphore(value:0),release=DispatchSemaphore(value:0)
  app.localTrashHandler={url in entered.signal();release.wait();try fm.moveItem(at:url,to:bin.appendingPathComponent(url.lastPathComponent))}
  let running=app.makeLocalTrashController(try LocalTrashPlan.prepare(directory:source.path,names:["one","two","three"]));running.start();precondition(entered.wait(timeout:.now()+5) == .success)
  precondition(app.applicationShouldTerminate(NSApp) == .terminateCancel);running.close();precondition(app.localTrashWindows.contains{$0 === running} && running.busy)
  release.signal();wait{!running.busy};precondition(running.report?.cancelled==true && running.report?.moved.count==1 && fm.fileExists(atPath:source.appendingPathComponent("two").path) && fm.fileExists(atPath:source.appendingPathComponent("three").path) && app.localTrashWindows.isEmpty)
  running.start();precondition(!running.busy && !app.window.isVisible)
  print("PASS: real App multi-select delete routing and explicit preview, all selected items and partial result display, 560/700 point layout, single execution, stale preview refuses writes, main listing refresh, close stops remaining while retaining quit protection and cleans controller; hidden fixture recycler, no actual Trash/server/user files")
 }
}
