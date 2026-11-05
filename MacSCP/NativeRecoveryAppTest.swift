import Cocoa
@main struct NativeRecoveryAppTests {
 static func wait(_ condition:()->Bool){let end=Date().addingTimeInterval(8);while !condition() && Date()<end{RunLoop.current.run(until:Date().addingTimeInterval(0.01))};precondition(condition(),"app recovery timeout")}
 static func main()throws{
  NSApplication.shared.setActivationPolicy(.prohibited)
  let fm=FileManager.default,root=fm.temporaryDirectory.appendingPathComponent("native-recovery-"+UUID().uuidString)
  try fm.createDirectory(at:root,withIntermediateDirectories:false);defer{try? fm.removeItem(at:root)}
  let a=Session(name:"fixture A",host:"recovery-a.invalid",user:"fixture",port:22,key:""),b=Session(name:"fixture B",host:"recovery-b.invalid",user:"fixture",port:2222,key:"")
  let suite="macscp-native-profile-"+UUID().uuidString
  let defaults=UserDefaults(suiteName:suite)!
  defer{defaults.removePersistentDomain(forName:suite)}
  let app=App(defaults:defaults,dataDirectory:root.appendingPathComponent("profile"),initialLocalDirectory:root.path,automaticLogin:false,frameAutosaveName:nil,clientProvider:{_,_ in try SFTPClient(command:"/usr/libexec/sftp-server",arguments:[])})
  let progress=SSHConnection(arguments:["60"],helper:"/unused",executable:"/unused",command:"/bin/sleep");defer{progress.stop()}
  let auth=NSWindow(contentRect:NSRect(x:0,y:0,width:200,height:100),styleMask:[.titled],backing:.buffered,defer:false);auth.isReleasedWhenClosed=false
  let socketA=root.appendingPathComponent("socket-a").path,socketB=root.appendingPathComponent("socket-b").path
  fm.createFile(atPath:socketA,contents:Data());fm.createFile(atPath:socketB,contents:Data())
  let tabA=ConnectionTab(a,socketA,progress,auth,root.path),tabB=ConnectionTab(b,socketB,progress,auth,root.path);tabA.connected=true;tabB.connected=true
  app.connections=[tabA,tabB];app.selectedTab=0;app.session=a;app.socket=socketA;app.local.acceptPath(root.path);app.remote.acceptPath(root.path);app.remote.path.isEnabled=true;app.queueTable.dataSource=app
  let journal=try QueueJournal(url:root.appendingPathComponent("queue.json")),relays=try RelayJournal(url:root.appendingPathComponent("relays.json"));app.queueJournal=journal;app.relayJournal=relays
  let bytes=Data(repeating:61,count:120000),src1=root.appendingPathComponent("source-1"),src2=root.appendingPathComponent("source-2"),dst1=root.appendingPathComponent("target-1"),dst2=root.appendingPathComponent("target-2")
  try bytes.write(to:src1);try bytes.write(to:src2)
  let first=TransferRecord(id:UUID(),site:a,up:true,source:src1.path,destination:dst1.path,directory:false,size:UInt64(bytes.count),overwrite:false,resumes:[],completed:[],created:[])
  let second=TransferRecord(id:UUID(),site:a,up:false,source:src2.path,destination:dst2.path,directory:false,size:UInt64(bytes.count),overwrite:false,resumes:[],completed:[],created:[])
  try journal.save(first,force:true);try journal.save(second,force:true)
  var controller=app.makeRecoveryController();precondition(controller.selection.items.count==2 && controller.selection.checked.isEmpty)
  controller.setChecked(.transfer(first.id),true);controller.restoreChecked()
  wait{app.jobs.first(where:{$0.id==first.id})?.finished==true && !app.transfers.contains(first.id) && app.recoveringRecords.isEmpty}
  let actual=try Data(contentsOf:dst1);precondition(actual==bytes && !fm.fileExists(atPath:dst2.path) && journal.list().map{$0.id}==[second.id])

  tabA.connected=false;app.refreshRecoveryWindow();controller.setChecked(.transfer(second.id),true);precondition(!controller.restoreButton.isEnabled && controller.removeButton.isEnabled)
  app.confirmRecoveryRemoval={items in precondition(items.map{$0.key}==[.transfer(second.id)]);return true};controller.removeChecked()
  wait{journal.list().isEmpty && app.recoveringRecords.isEmpty}
  precondition(fm.fileExists(atPath:src2.path) && !fm.fileExists(atPath:dst2.path))

  tabA.connected=true
  let closed=TransferRecord(id:UUID(),site:a,up:true,source:src1.path,destination:root.appendingPathComponent("never-start").path,directory:false,size:UInt64(bytes.count),overwrite:false,resumes:[],completed:[],created:[])
  try journal.save(closed,force:true);app.refreshRecoveryWindow();controller.setChecked(.transfer(closed.id),true);controller.restoreChecked();tabA.connected=false;controller.close()
  wait{app.recoveringRecords.isEmpty}
  controller=app.makeRecoveryController();precondition(controller.details.string.contains("已关闭"))
  precondition(!app.jobs.contains{$0.id==closed.id} && !fm.fileExists(atPath:closed.destination) && journal.list().contains{$0.id==closed.id})

  tabA.connected=true;tabB.connected=true
  let relayTarget=root.appendingPathComponent("relayed")
  let seed=try RelayTransfer(file:DragFile(path:src1.path,directory:false,size:UInt64(bytes.count),connection:socketA),destination:relayTarget.path,sourceSite:a,targetSite:b);seed.enableRecovery();let record=seed.recoveryRecord()!;defer{try? record.discardLocal()};try relays.save(record,force:true)
  app.refreshRecoveryWindow();controller.selectNone();controller.setChecked(.relay(record.id),true);controller.restoreChecked()
  wait{app.relayTransfers.first(where:{$0.id==record.id})?.phase == .completed && app.recoveringRecords.isEmpty && relays.list().isEmpty}
  let relayed=try Data(contentsOf:relayTarget);precondition(relayed==bytes && !fm.fileExists(atPath:record.staging) && journal.list().contains{$0.id==closed.id} && !fm.fileExists(atPath:closed.destination))
  precondition(NSApp.windows.allSatisfy{!$0.isVisible})
  print("PASS: actual hidden App recovers only checked upload with real SFTP, unselected download untouched, selected offline deletion preserves source/target, closed-login race prevents enqueue and preserves journal, checked relay restores both stages without restoring unselected ordinary task; no user window/session touched")
 }
}
