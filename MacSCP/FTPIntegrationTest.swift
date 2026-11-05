import Cocoa
@main struct FTPIntegrationTests {
 final class MemoryVault:PasswordVault {
  enum Failure:Error{case fixture}
  var values=[PasswordEndpoint:String](),reads=0,writes=0,removals=0,failRead=false,failWrite=false
  func password(for endpoint:PasswordEndpoint)throws->String?{reads+=1;if failRead{throw Failure.fixture};return values[endpoint]}
  func save(_ password:String,for endpoint:PasswordEndpoint)throws{if failWrite{throw Failure.fixture};writes+=1;values[endpoint]=password}
  func forget(_ endpoint:PasswordEndpoint)throws{removals+=1;values.removeValue(forKey:endpoint)}
 }

 final class Fixture {
  let process=Process(),port:Int
  init(root:URL,workspace:URL,security:String,certificate:URL?,key:URL?,unsupportedMLSD:Bool=false,deniedMLSD:Bool=false,noMetadata:Bool=false,unsupportedMDTM:Bool=false,unsupportedMFMT:Bool=false,failUploadOnce:Bool=false,noPermissions:Bool=false,denyPublishOnce:Bool=false,authLog:URL?=nil,greetingDelay:Double=0,sizeDelay:Double=0)throws{
   let info=workspace.appendingPathComponent("port-"+UUID().uuidString+".json"),errors=Pipe()
   process.executableURL=URL(fileURLWithPath:"/usr/bin/env");process.arguments=["python3",FileManager.default.currentDirectoryPath+"/MacSCP/FTPFixture.py","--root",root.path,"--port-file",info.path,"--security",security]
   if let certificate=certificate,let key=key{process.arguments! += ["--cert",certificate.path,"--key",key.path]}
   if let authLog=authLog{process.arguments! += ["--auth-log",authLog.path]}
   if sizeDelay>0{process.arguments! += ["--size-delay",String(sizeDelay)]}
   if greetingDelay>0{process.arguments! += ["--greeting-delay",String(greetingDelay)]}
   if denyPublishOnce{process.arguments!.append("--deny-publish-once")}
   if noPermissions{process.arguments!.append("--mlsd-no-permissions")}
   if failUploadOnce{process.arguments!.append("--fail-upload-once")}
   if noMetadata{process.arguments!.append("--mlsd-no-metadata")}
   if unsupportedMFMT{process.arguments!.append("--mfmt-unsupported")}
   if unsupportedMDTM{process.arguments!.append("--mdtm-unsupported")}
   if deniedMLSD{process.arguments!.append("--mlsd-denied")}
   if unsupportedMLSD{process.arguments!.append("--mlsd-unsupported")}
   process.standardOutput=FileHandle.nullDevice;process.standardError=errors;try process.run()
   let deadline=Date().addingTimeInterval(10);var selected:Int?
   while selected==nil,Date()<deadline,process.isRunning{if let data=try? Data(contentsOf:info),let object=(try? JSONSerialization.jsonObject(with:data)) as? [String:Int]{selected=object["port"]};Thread.sleep(forTimeInterval:0.02)}
   guard let selected=selected else{if process.isRunning{process.terminate()};process.waitUntilExit();let error=String(decoding:errors.fileHandleForReading.readDataToEndOfFile(),as:UTF8.self);throw SFTPError.message("FTP fixture did not start: "+error)};port=selected
  }
  func stop(){if process.isRunning{process.terminate();process.waitUntilExit()}}
  deinit{stop()}
 }
 static func check(_ v:Bool,line:UInt=#line){precondition(v,"assertion at line \(line)")}
 static func wait(line:UInt=#line,_ condition:()->Bool){let end=Date().addingTimeInterval(12);while !condition(),Date()<end{RunLoop.current.run(until:Date().addingTimeInterval(0.01))};precondition(condition(),"hidden FTP App operation timed out at line \(line)")}
 static func main()throws{
  NSApplication.shared.setActivationPolicy(.prohibited)
  let fm=FileManager.default,workspace=fm.temporaryDirectory.appendingPathComponent("ftp-integration-"+UUID().uuidString),root=workspace.appendingPathComponent("server")
  try fm.createDirectory(at:root,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700]);defer{try? fm.removeItem(at:workspace)}
  let data=Data((0..<150000).map{UInt8($0%251)}),name="中文 ' [%] #?;type=a.bin",source=workspace.appendingPathComponent("source.bin")
  try data.write(to:source);try data.write(to:root.appendingPathComponent(name));try Data().write(to:root.appendingPathComponent("empty"));try fm.createDirectory(at:root.appendingPathComponent("folder"),withIntermediateDirectories:false)
  try fm.createDirectory(at:root.appendingPathComponent("download-tree/nested"),withIntermediateDirectories:true);try data.write(to:root.appendingPathComponent("download-tree/nested/data.bin"));try Data().write(to:root.appendingPathComponent("download-tree/empty"))
  let certificate=workspace.appendingPathComponent("certificate.pem"),key=workspace.appendingPathComponent("key.pem"),config=workspace.appendingPathComponent("certificate.cnf")
  try Data("[req]\nprompt=no\ndistinguished_name=dn\nx509_extensions=ext\n[dn]\nCN=FTP loopback fixture\n[ext]\nsubjectAltName=IP:127.0.0.1\nbasicConstraints=critical,CA:TRUE\nkeyUsage=critical,digitalSignature,keyEncipherment,keyCertSign\nextendedKeyUsage=serverAuth\n".utf8).write(to:config)
  let openssl=Process();openssl.executableURL=URL(fileURLWithPath:"/usr/bin/openssl");openssl.arguments=["req","-x509","-newkey","rsa:2048","-nodes","-days","1","-keyout",key.path,"-out",certificate.path,"-config",config.path];openssl.standardOutput=FileHandle.nullDevice;openssl.standardError=FileHandle.nullDevice;try openssl.run();openssl.waitUntilExit();check(openssl.terminationStatus==0)
  for (mode,security) in [("plain",FTPConnection.Security.plain),("explicit",.explicitTLS),("implicit",.implicitTLS)]{
   let fixture=try Fixture(root:root,workspace:workspace,security:mode,certificate:mode=="plain" ? nil : certificate,key:mode=="plain" ? nil : key);defer{fixture.stop()}
   if mode != "plain"{
    let untrusted=try FTPCurlTransport(FTPConnection(host:"127.0.0.1",user:"fixture",password:"macscp-test-only",port:fixture.port,security:security));defer{untrusted.close()}
    do{_ = try untrusted.perform(.machineList("/"));fatalError("untrusted certificate accepted")}catch let error as FTPCurlFailure{check([51,60].contains(error.code))}
    let wrongHost=try FTPCurlTransport(FTPConnection(host:"localhost",user:"fixture",password:"macscp-test-only",port:fixture.port,security:security,caCertificate:certificate));defer{wrongHost.close()}
    do{_ = try wrongHost.perform(.machineList("/"));fatalError("wrong-host certificate accepted")}catch let error as FTPCurlFailure{check([51,60].contains(error.code))}
   }
   let connection=try FTPConnection(host:"127.0.0.1",user:"fixture",password:"macscp-test-only",port:fixture.port,security:security,caCertificate:mode=="plain" ? nil : certificate),transport=try FTPCurlTransport(connection);defer{transport.close()}
   let entry=try transport.perform(.entryDirectory);check(entry.entryDirectory=="/")
   let reader=FTPDirectoryReader(transport:transport);check(try reader.canonical(".")=="/")
   let list=try FTPListing.mlsd(transport.perform(.machineList("/")).data);check(list.contains{$0.name==name && $0.size==UInt64(data.count)} && list.contains{$0.name=="folder" && $0.directory})
   let legacy=try FTPListing.list(transport.perform(.legacyList("/")).data);check(legacy.contains{$0.name==name})
   let received=try transport.perform(.retrieve("/"+name));check(received.data==data)
   check(try transport.perform(.retrieve("/empty")).data.isEmpty)
   var streamed=Data();_ = try transport.perform(.retrieve("/"+name),maximumBytes:UInt64(data.count),sink:{streamed.append($0)});check(streamed==data)
   do{_ = try transport.perform(.retrieve("/"+name),maximumBytes:4);fatalError("byte bound ignored")}catch{}
   _ = try transport.perform(.storeTemporary("/.macscp-fixture-staging",source));check(try Data(contentsOf:root.appendingPathComponent(".macscp-fixture-staging"))==data)
   _ = try transport.perform(.commands([.makeDirectory("/made"),.rename("/.macscp-fixture-staging","/made/moved.bin")]));check(try Data(contentsOf:root.appendingPathComponent("made/moved.bin"))==data)
   _ = try transport.perform(.commands([.removeFile("/made/moved.bin"),.removeDirectory("/made")]));check(!fm.fileExists(atPath:root.appendingPathComponent("made").path))
   do{_ = try transport.perform(.commands([.makeDirectory("/invalid\r\nDELE /empty")]));fatalError("command injection accepted")}catch{};check(fm.fileExists(atPath:root.appendingPathComponent("empty").path))
   let client=try FTPClient(connection);defer{client.close()}
   let probe=TransferDestinationProbe(),probeResult=try probe.read("/download-tree",factory:{try FTPClient(connection)})
   check(probeResult.0=="/download-tree" && probeResult.1.count==2)
   let rootProbe=try TransferDestinationProbe().read("/",factory:{try FTPClient(connection)});check(rootProbe.0=="/" && rootProbe.1.contains(name))
   do{_ = try TransferDestinationProbe().read("/"+name,factory:{try FTPClient(connection)});fatalError("file accepted as destination directory")}catch{}

   let snapshot=try RemoteDirectoryRead.read("/download-tree",client:client);check(snapshot.entries.count==2 && client.capabilities.contains(.downloadResume) && !client.capabilities.contains(.atomicOverwrite))
   let search=try RemoteSearch.find(root:"/download-tree",query:"*.bin",client:client,cancellation:SearchCancellation());check(search.hits.count==1)
   let sync=try SyncPlanner.remote("/download-tree",client:client);check(sync["nested/data.bin"]?.size==UInt64(data.count))
   let statistics=try DirectorySizeScanner.remote(paths:["/download-tree"],client:client,cancellation:DirectorySizeCancellation());check(statistics.complete && statistics.bytes==UInt64(data.count) && statistics.files==2)
   let downloadRoot=workspace.appendingPathComponent("download-"+mode),job=TransferJob(up:false,source:"/download-tree",destination:downloadRoot.path,directory:true,size:0);job.policy=TransferPolicy(verifyChecksum:true);job.policyConfigured=true;job.factory={try FTPClient(connection)};job.execute({});check(try job.finished && !job.failed && Data(contentsOf:downloadRoot.appendingPathComponent("nested/data.bin"))==data)
   let resumeTarget=workspace.appendingPathComponent("resumed-"+mode),remoteSource="/download-tree/nested/data.bin";try Data("original target".utf8).write(to:resumeTarget)
   let state=TransferResume(source:remoteSource,destination:resumeTarget.path,upload:false);var transferred:UInt64=0
   client.progress={transferred+=$0};client.checkpoint={if transferred>=32768{throw SFTPError.message("fixture interruption")}}
   do{try client.downloadResumable(remoteSource,to:resumeTarget,state:state,overwrite:true,verifyChecksum:true);fatalError("download must stop")}catch{}
   check(try Data(contentsOf:resumeTarget)==Data("original target".utf8));check(FileManager.default.fileExists(atPath:state.temporaryPath))
   let sourceOnDisk=root.appendingPathComponent("download-tree/nested/data.bin"),oldDate=(try fm.attributesOfItem(atPath:sourceOnDisk.path)[.modificationDate]) as! Date
   try fm.setAttributes([.modificationDate:oldDate.addingTimeInterval(120)],ofItemAtPath:sourceOnDisk.path)
   let changedSource=try FTPClient(connection);defer{changedSource.close()};do{try changedSource.downloadResumable(remoteSource,to:resumeTarget,state:state,overwrite:true,verifyChecksum:true);fatalError("changed source accepted")}catch{};check(try Data(contentsOf:resumeTarget)==Data("original target".utf8));try fm.setAttributes([.modificationDate:oldDate],ofItemAtPath:sourceOnDisk.path)
   let corrupt=try FileHandle(forUpdating:URL(fileURLWithPath:state.temporaryPath));try corrupt.seek(toOffset:0);try corrupt.write(contentsOf:Data([255]));try corrupt.close()
   let badPrefix=try FTPClient(connection);defer{badPrefix.close()};do{try badPrefix.downloadResumable(remoteSource,to:resumeTarget,state:state,overwrite:true,verifyChecksum:true);fatalError("corrupt prefix accepted")}catch{};check(try Data(contentsOf:resumeTarget)==Data("original target".utf8))
   let restored=try FileHandle(forUpdating:URL(fileURLWithPath:state.temporaryPath));try restored.seek(toOffset:0);try restored.write(contentsOf:data.prefix(1));try restored.close()
   let resumed=try FTPClient(connection);defer{resumed.close()};var reused:UInt64=0,newBytes:UInt64=0;resumed.resumedProgress={reused+=$0};resumed.progress={newBytes+=$0}
   try resumed.downloadResumable(remoteSource,to:resumeTarget,state:TransferResume(record:state.record()),overwrite:true,verifyChecksum:true)
   check(try reused>=32768 && newBytes<UInt64(data.count) && Data(contentsOf:resumeTarget)==data)
   let changedTarget=workspace.appendingPathComponent("concurrent-"+mode);try Data("old".utf8).write(to:changedTarget);let concurrent=try FTPClient(connection);defer{concurrent.close()};var changed=false
   concurrent.progress={_ in if !changed{changed=true;try! Data("changed target".utf8).write(to:changedTarget)}}
   do{try concurrent.download("/"+name,to:changedTarget,maximumBytes:nil);fatalError("concurrent target overwritten")}catch{}
   check(try Data(contentsOf:changedTarget)==Data("changed target".utf8))
   do{try resumed.upload(source,to:"/unapproved-upload",overwrite:false,permissions:nil,beforeCommit:nil);fatalError("incomplete upload path must stay disabled")}catch{};check(!fm.fileExists(atPath:root.appendingPathComponent("unapproved-upload").path))
   let writer=try FTPClient(connection,publicationPolicy:.allowNonAtomic);defer{writer.close()}
   check(!writer.capabilities.contains(.timestampOnly))
   let emptyDate=try fm.attributesOfItem(atPath:root.appendingPathComponent("empty").path)[.modificationDate] as! Date
   do{try writer.setModificationTime("/empty",to:1700000000,expected:(0,0o100644,0),beforeCommit:nil);fatalError("FTP metadata-only timestamp enabled")}catch{}
   check(try fm.attributesOfItem(atPath:root.appendingPathComponent("empty").path)[.modificationDate] as? Date==emptyDate)
   let ftpSyncOptions=SyncOptionsView(permitsUpload:true,settings:SyncSettings(comparison:SyncComparisonOptions(fileMode:.timestamps,timestampSameSizeOnly:true)),permitsTimestamps:false)
   check(ftpSyncOptions.operation.numberOfItems==2 && ftpSyncOptions.fileMode == .synchronize)

   // Sync cleanup uses the same common interface, but retains FTP's explicit write opt-in.
   let syncDisk=root.appendingPathComponent("sync-"+mode),syncLocal=workspace.appendingPathComponent("sync-local-"+mode),syncRoot="/sync-"+mode
   try fm.createDirectory(at:syncDisk.appendingPathComponent("obsolete/nested"),withIntermediateDirectories:true);try fm.createDirectory(at:syncLocal,withIntermediateDirectories:true)
   try Data("remove fixture only".utf8).write(to:syncDisk.appendingPathComponent("obsolete/nested/file"))
   let syncL=try SyncPlanner.local(syncLocal.path),syncR=try SyncPlanner.remote(syncRoot,client:writer)
   let syncActions=SyncComparison.candidates(local:syncL,remote:syncR,direction:.upload,deleteExtraneous:true)
   check(syncActions.count==1 && syncActions[0].deletion && syncActions[0].directory)
   let syncPlan=try SyncDeletionPlan.prepare(syncActions[0],localRoot:syncLocal.path,remoteRoot:syncRoot,localSnapshot:syncL,remoteSnapshot:syncR,client:writer)
   do{try syncPlan.execute(client:resumed,checkpoint:{},trash:{_ in fatalError("no real recycle bin")});fatalError("readonly FTP cleanup accepted")}catch{}
   check(fm.fileExists(atPath:syncDisk.appendingPathComponent("obsolete/nested/file").path))
   try syncPlan.execute(client:writer,checkpoint:{},trash:{_ in fatalError("no real recycle bin")});check(!fm.fileExists(atPath:syncDisk.appendingPathComponent("obsolete").path))
   try fm.createDirectory(at:syncDisk.appendingPathComponent("changed"),withIntermediateDirectories:true);try Data("keep".utf8).write(to:syncDisk.appendingPathComponent("changed/old"))
   let driftL=try SyncPlanner.local(syncLocal.path),driftR=try SyncPlanner.remote(syncRoot,client:writer)
   let driftAction=SyncComparison.candidates(local:driftL,remote:driftR,direction:.upload,deleteExtraneous:true)[0]
   let driftPlan=try SyncDeletionPlan.prepare(driftAction,localRoot:syncLocal.path,remoteRoot:syncRoot,localSnapshot:driftL,remoteSnapshot:driftR,client:writer)
   try Data("new child".utf8).write(to:syncDisk.appendingPathComponent("changed/new"))
   do{try driftPlan.execute(client:writer,checkpoint:{},trash:{_ in fatalError()});fatalError("FTP changed tree accepted")}catch{}
   check(fm.fileExists(atPath:syncDisk.appendingPathComponent("changed/old").path))
   print("PASS: "+mode+" FTP sync cleanup: grouped recursive plan, read-only refusal before DELE, explicit writer cleanup, new child rejected before mutation")
   let uploadRoot="/upload-tree-"+mode;let uploadJob=TransferJob(up:true,source:downloadRoot.path,destination:uploadRoot,directory:true,size:0);uploadJob.policy=TransferPolicy(verifyChecksum:true);uploadJob.policyConfigured=true;uploadJob.factory={try FTPClient(connection,publicationPolicy:.allowNonAtomic)};uploadJob.execute({});check(uploadJob.finished && !uploadJob.failed)
   check(try Data(contentsOf:root.appendingPathComponent("upload-tree-"+mode+"/nested/data.bin"))==data)
   let textInput=workspace.appendingPathComponent("text-input-"+mode+".txt"),textRemote="/text-mode-"+mode+".txt",textDownload=workspace.appendingPathComponent("text-output-"+mode+".txt")
   let textBytes=Data([239,187,191])+Data("中文\r\nline\rlast\n".utf8)+Data([26]),textExpected=Data("中文\nline\nlast\n".utf8)
   try textBytes.write(to:textInput)
   let textOptions=TextTransferOptions(mode:.text,remote:.lf,local:.crlf,removeBOM:true,removeEOF:true),textPolicy=TransferPolicy(verifyChecksum:true,text:textOptions)
   let textUpload=TransferJob(up:true,source:textInput.path,destination:textRemote,directory:false,size:UInt64(textBytes.count));textUpload.policy=textPolicy;textUpload.factory={try FTPClient(connection,publicationPolicy:.allowNonAtomic)};textUpload.execute({});check(!textUpload.failed && textUpload.progressSnapshot().total==UInt64(textExpected.count) && textUpload.transferredBytes==UInt64(textExpected.count))
   check(try Data(contentsOf:root.appendingPathComponent(String(textRemote.dropFirst())))==textExpected && Data(contentsOf:textInput)==textBytes)
   let textJob=TransferJob(up:false,source:textRemote,destination:textDownload.path,directory:false,size:UInt64(textExpected.count));textJob.policy=textPolicy;textJob.factory={try FTPClient(connection)};textJob.execute({});check(!textJob.failed && textJob.progressSnapshot().total==UInt64(textExpected.count) && textJob.transferredBytes==UInt64(textExpected.count))
   check(try Data(contentsOf:textDownload)==Data("中文\r\nline\r\nlast\r\n".utf8))
   print("PASS: "+mode+" actual converted text upload/download, SHA-256 of wire bytes, original upload source preserved; client conversion over TYPE I")
   let overwritePath="/overwrite-"+mode;let overwriteDisk=root.appendingPathComponent(String(overwritePath.dropFirst()));try Data("old target".utf8).write(to:overwriteDisk);try fm.setAttributes([.posixPermissions:0o640],ofItemAtPath:overwriteDisk.path)
   try writer.upload(source,to:overwritePath,overwrite:true,permissions:nil,beforeCommit:nil);check(try Data(contentsOf:overwriteDisk)==data);check((try fm.attributesOfItem(atPath:overwriteDisk.path)[.posixPermissions] as? NSNumber)?.intValue==0o640)
   let refused="/beforecommit-"+mode,refusedDisk=root.appendingPathComponent(String(refused.dropFirst()));try Data("original before commit".utf8).write(to:refusedDisk)
   do{try writer.upload(source,to:refused,overwrite:true,permissions:nil,beforeCommit:{throw SFTPError.message("fixture conflict")});fatalError("beforeCommit ignored")}catch{};check(try Data(contentsOf:refusedDisk)==Data("original before commit".utf8))
   check(try fm.contentsOfDirectory(atPath:root.path).allSatisfy{!$0.hasPrefix(String(refused.dropFirst())+".macscp-resume-")})
   let cancelPath="/cancel-upload-"+mode,cancelDisk=root.appendingPathComponent(String(cancelPath.dropFirst()));try Data("old cancel target".utf8).write(to:cancelDisk)
   let cancelledWriter=try FTPClient(connection,publicationPolicy:.allowNonAtomic);defer{cancelledWriter.close()};var sent:UInt64=0;cancelledWriter.progress={sent+=$0};cancelledWriter.checkpoint={if sent>0{throw SFTPError.message("fixture upload cancellation")}}
   do{try cancelledWriter.upload(source,to:cancelPath,overwrite:true,permissions:nil,beforeCommit:nil);fatalError("upload cancellation ignored")}catch{}
   check(try sent>0 && Data(contentsOf:cancelDisk)==Data("old cancel target".utf8));check(try fm.contentsOfDirectory(atPath:root.path).allSatisfy{!$0.hasPrefix(String(cancelPath.dropFirst())+".macscp-resume-")})
   let copied="/copied-"+mode;try writer.copyRemoteFile(overwritePath,to:copied);check(try Data(contentsOf:root.appendingPathComponent(String(copied.dropFirst())))==data)
   print("PASS: "+mode+" FTP upload adapter, recursive/empty uploads, verified overwrite with permission preservation, precommit refusal and stream copy")
   print("PASS: "+mode+" FTP client through shared browsing/recursive queue, SHA and validated REST download resume; original/concurrent targets protected")
   if mode=="plain"{
    let requireTLS=try FTPCurlTransport(FTPConnection(host:"127.0.0.1",user:"fixture",password:"macscp-test-only",port:fixture.port,security:.explicitTLS));defer{requireTLS.close()};do{_ = try requireTLS.perform(.machineList("/"));fatalError("TLS silently downgraded")}catch{}
    let bad=try FTPCurlTransport(FTPConnection(host:"127.0.0.1",user:"fixture",password:"wrong",port:fixture.port,security:.plain));defer{bad.close()};do{_ = try bad.perform(.machineList("/"));fatalError("bad password accepted")}catch let e as FTPCurlFailure{check(e.code==67 && !e.localizedDescription.contains("wrong"))}
    try Data(repeating:1,count:2*1024*1024).write(to:root.appendingPathComponent("slow.bin"));let cancelled=try FTPCurlTransport(connection);defer{cancelled.close()};cancelled.progress={received,_ in if received>0{cancelled.interrupt()}};let began=Date();do{_ = try cancelled.perform(.retrieve("/slow.bin"));fatalError("cancel ignored")}catch{};check(Date().timeIntervalSince(began)<5)
   }
   print("PASS: loopback "+mode+" FTP transport, binary/empty/Unicode/special paths, MLSD/LIST, stream bound, raw temporary upload and typed commands")
   let localRoot=workspace.appendingPathComponent("ui-local-"+mode);try fm.createDirectory(at:localRoot,withIntermediateDirectories:false);let uiName="ui-source-"+mode+".txt";try data.write(to:localRoot.appendingPathComponent(uiName))
   let suite="ftp-ui-"+UUID().uuidString,defaults=UserDefaults(suiteName:suite)!;defer{defaults.removePersistentDomain(forName:suite)}
   let app=App(defaults:defaults,dataDirectory:workspace.appendingPathComponent("ui-profile-"+mode),initialLocalDirectory:localRoot.path,automaticLogin:false,showsMainWindow:false,transferOptionsEnabled:false,frameAutosaveName:nil)
   app.applicationDidFinishLaunching(Notification(name:NSApplication.didFinishLaunchingNotification));let proto:FileProtocol=security == .plain ? .ftp : security == .explicitTLS ? .ftpsExplicit : .ftpsImplicit
   let site=Session(name:"FTP UI fixture",host:"127.0.0.1",user:"fixture",port:fixture.port,key:"",protocolKind:proto,ftpOptions:FTPSiteOptions(allowNonAtomicWrites:true))
   try app.startFTP(site,password:"macscp-test-only",caCertificate:mode=="plain" ? nil : certificate);wait{app.remoteConnectionReady && !app.browsing && app.remote.currentPath=="/"};let tab=app.currentConnection!,token=app.socket
   check(tab.usable && tab.terminal==nil && app.auth?.isVisible != true && !app.window.isVisible);check(app.protocolBadge.stringValue.contains(proto.title));check(app.remote.entries.contains{$0.name==name});check(app.recoveryConnections()[site.identity]?.socket==token)
   app.local.table.selectRowIndexes(IndexSet(integer:app.local.entries.firstIndex{$0.name==uiName}!),byExtendingSelection:false);app.enqueue(true);wait{app.jobs.count==1 && app.jobs[0].finished};check(!app.jobs[0].failed);check(try Data(contentsOf:root.appendingPathComponent(uiName))==data);check(app.queueJournal!.list().isEmpty)
   let journal=app.queueJournal;app.queueJournal=nil;let blockedName="ui-journal-blocked-"+mode;try data.write(to:localRoot.appendingPathComponent(blockedName));app.local.path.stringValue=localRoot.path;app.loadLocal(origin:.passive);app.local.table.selectRowIndexes(IndexSet(integer:app.local.entries.firstIndex{$0.name==blockedName}!),byExtendingSelection:false);app.enqueue(true);wait{app.jobs.count==2 && app.jobs[1].finished};check(app.jobs[1].failed && !fm.fileExists(atPath:root.appendingPathComponent(blockedName).path));app.queueJournal=journal
   var readOnly=site;readOnly.ftpOptions=FTPSiteOptions();try app.startFTP(readOnly,password:"macscp-test-only",caCertificate:mode=="plain" ? nil : certificate);wait{app.remoteConnectionReady && !app.browsing && app.remote.currentPath=="/"};let readTab=app.currentConnection!
   check(!app.local.transferControl!.isEnabled);app.remote.menuNeedsUpdate(app.remote.table.menu!);check(app.remote.table.menu!.items.first{$0.identifier?.rawValue=="mkdir"}?.isEnabled==false)
   check(!app.handleDrop([DragFile(path:localRoot.appendingPathComponent(uiName).path,directory:false,size:UInt64(data.count),connection:nil)],toRemote:true));check(app.jobs.count==2)
   let passiveDirectory="/directed-"+mode,passiveName="inactive-"+mode+".txt",passiveSource=localRoot.appendingPathComponent(passiveName)
   try writer.mkdir(passiveDirectory);try data.write(to:passiveSource);tab.remotePath=passiveDirectory;app.rebuildTabs()
   let currentToken=app.socket,currentGeneration=app.generation,targetIndex=app.connections.firstIndex{$0 === tab}!,dropButton=app.tabBar.arrangedSubviews.compactMap{$0 as? SessionTabButton}[targetIndex]
   check(dropButton.acceptsDrop?()==true)
   check(dropButton.receiveDrop?([DragFile(path:passiveSource.path,directory:false,size:UInt64(data.count),connection:nil)])==true)
   wait{app.jobs.count==3 && app.jobs.last!.finished};check(!app.jobs.last!.failed && app.jobs.last!.recoverySite?.ftpSettings.allowNonAtomicWrites==true)
   check(try Data(contentsOf:root.appendingPathComponent(String(passiveDirectory.dropFirst())).appendingPathComponent(passiveName))==data)
   check(app.socket==currentToken && app.currentConnection === readTab && app.generation==currentGeneration && app.remote.currentPath=="/")
   check(app.tabBar.arrangedSubviews.compactMap{$0 as? SessionTabButton}[app.connections.firstIndex{$0 === readTab}!].acceptsDrop?()==false)
   tab.remotePath="/"
   print("PASS: "+mode+" inactive writable FTP tab receives directed upload while active read-only tab/path/generation stay unchanged; exact bytes and per-token write policy")

   let mirrorLocal=workspace.appendingPathComponent("mirror-local-"+mode),mirrorDisk=root.appendingPathComponent("mirror-"+mode),mirrorRemote="/mirror-"+mode
   try fm.createDirectory(at:mirrorLocal,withIntermediateDirectories:true);try fm.createDirectory(at:mirrorDisk,withIntermediateDirectories:true)
   let older=mirrorLocal.appendingPathComponent("file.txt"),newer=mirrorDisk.appendingPathComponent("file.txt")
   try Data("older source".utf8).write(to:older);try Data("newer target".utf8).write(to:newer)
   try fm.setAttributes([.modificationDate:Date(timeIntervalSince1970:1700000000)],ofItemAtPath:older.path);try fm.setAttributes([.modificationDate:Date(timeIntervalSince1970:1800000000)],ofItemAtPath:newer.path)
   let mirrorL=try SyncPlanner.local(mirrorLocal.path),mirrorR=try SyncPlanner.remote(mirrorRemote,client:writer),mirrorSettings=SyncSettings(comparison:SyncComparisonOptions(fileMode:.mirror,timeTolerance:0))
   check(try SyncComparison.plannedCandidates(local:mirrorL,remote:mirrorR,settings:SyncSettings()).isEmpty)
   let mirrorActions=try SyncComparison.plannedCandidates(local:mirrorL,remote:mirrorR,settings:mirrorSettings)
   let mirrorPreview=app.makeSyncPreview(mirrorActions,localRoot:mirrorLocal.path,remoteRoot:mirrorRemote,localSnapshot:mirrorL,remoteSnapshot:mirrorR,deletions:[:],site:site,socket:token,policy:TransferPolicy(verifyChecksum:true),comparisonSummary:mirrorSettings.comparison.summary,requireUploadTimestamp:true)
   mirrorPreview.apply();wait{app.jobs.last!.finished};check(!app.jobs.last!.failed)
   check(try Data(contentsOf:newer)==Data("older source".utf8) && writer.attributes(mirrorRemote+"/file.txt")?.modified==1700000000)
   check(!site.ftpSettings.preserveTime)
   let convergedL=try SyncPlanner.local(mirrorLocal.path),convergedR=try SyncPlanner.remote(mirrorRemote,client:writer)
   check(try SyncComparison.plannedCandidates(local:convergedL,remote:convergedR,settings:mirrorSettings).isEmpty)
   print("PASS: "+mode+" hidden App mirror overwrites newer target using original authenticated tab; forces source timestamp for time comparison, converges on recompare and preserves ordinary FTP settings")
   app.keepRemoteUpdated();check(app.continuousWindows.isEmpty) // Current read-only FTP tab refuses monitoring writes.
   app.activateTab(app.connections.firstIndex(where:{$0 === tab})!);wait{!app.browsing && app.remoteConnectionReady}
   let watchLocal=workspace.appendingPathComponent("watch-local-"+mode),watchDisk=root.appendingPathComponent("watch-"+mode),watchRemote="/watch-"+mode
   try fm.createDirectory(at:watchLocal,withIntermediateDirectories:true);try fm.createDirectory(at:watchDisk,withIntermediateDirectories:true)
   app.local.acceptPath(watchLocal.path);app.remote.acceptPath(watchRemote);app.keepRemoteUpdated();check(app.continuousWindows.count==1)
   let watch=app.continuousWindows[0];watch.usesNativeEvents=false;watch.initial.state = .off;watch.interval.stringValue="0.5";watch.settle.stringValue="0.5";watch.start();wait{watch.engine?.state == .watching}
   let watchSource=watchLocal.appendingPathComponent("saved.txt");try Data("watched FTP edit".utf8).write(to:watchSource);try fm.setAttributes([.modificationDate:Date(timeIntervalSince1970:1700000005)],ofItemAtPath:watchSource.path)
   wait{app.jobs.last?.customAction=="持续更新" && app.jobs.last!.finished && watch.engine?.state == .watching}
   check(!app.jobs.last!.failed);check(try Data(contentsOf:watchDisk.appendingPathComponent("saved.txt"))==Data("watched FTP edit".utf8));check(try writer.attributes(watchRemote+"/saved.txt")?.modified==1700000005)
   check(!tab.session.ftpSettings.preserveTime);watch.stop();wait{watch.engine!.state.terminal};watch.close();wait{app.continuousWindows.isEmpty}
   try fm.createDirectory(at:watchLocal.appendingPathComponent("tree/sub"),withIntermediateDirectories:true)
   try Data("chosen FTP subset".utf8).write(to:watchLocal.appendingPathComponent("tree/sub/keep.txt"));try Data("not selected".utf8).write(to:watchLocal.appendingPathComponent("tree/sub/skip.txt"))
   let subsetLocal=try SyncPlanner.local(watchLocal.path),subsetRemote=try SyncPlanner.remote(watchRemote,client:writer),subsetRows=try SyncComparison.plannedCandidates(local:subsetLocal,remote:subsetRemote,settings:SyncSettings()).filter{$0.relative=="tree"}
   check(subsetRows.count==1)
   let subsetPreview=app.makeSyncPreview(subsetRows,localRoot:watchLocal.path,remoteRoot:watchRemote,localSnapshot:subsetLocal,remoteSnapshot:subsetRemote,deletions:[:],site:site,socket:token,policy:TransferPolicy(),requireUploadTimestamp:true)
   let subsetWindow=subsetPreview.showContents(row:0)!;subsetWindow.selectNone();subsetWindow.set("tree/sub/keep.txt",on:true);subsetWindow.apply();subsetPreview.apply()
   wait{app.jobs.last!.finished};check(!app.jobs.last!.failed && !app.jobs.last!.retryAllowed)
   check(try Data(contentsOf:watchDisk.appendingPathComponent("tree/sub/keep.txt"))==Data("chosen FTP subset".utf8));check(!fm.fileExists(atPath:watchDisk.appendingPathComponent("tree/sub/skip.txt").path))
   try fm.createDirectory(at:watchDisk.appendingPathComponent("cleanup/sub"),withIntermediateDirectories:true);try Data("delete only this".utf8).write(to:watchDisk.appendingPathComponent("cleanup/sub/drop"));try Data("keep this".utf8).write(to:watchDisk.appendingPathComponent("cleanup/sub/keep"))
   let cleanLocal=try SyncPlanner.local(watchLocal.path),cleanRemote=try SyncPlanner.remote(watchRemote,client:writer),cleanRows=SyncComparison.candidates(local:cleanLocal,remote:cleanRemote,direction:.upload,deleteExtraneous:true).filter{$0.deletion && $0.relative=="cleanup"}
   check(cleanRows.count==1);let cleanPlan=try SyncDeletionPlan.prepare(cleanRows[0],localRoot:watchLocal.path,remoteRoot:watchRemote,localSnapshot:cleanLocal,remoteSnapshot:cleanRemote,client:writer)
   let cleanPreview=app.makeSyncPreview(cleanRows,localRoot:watchLocal.path,remoteRoot:watchRemote,localSnapshot:cleanLocal,remoteSnapshot:cleanRemote,deletions:["cleanup":cleanPlan],site:site,socket:token,policy:TransferPolicy())
   let cleanWindow=cleanPreview.showContents(row:0)!;cleanWindow.selectNone();cleanWindow.set("cleanup/sub/drop",on:true);cleanWindow.apply();check(cleanPreview.deletionLines(cleanPreview.candidates)==["远程永久删除：\"cleanup/sub/drop\""])
   cleanPreview.confirmDeletion={_ in true};cleanPreview.apply();wait{app.jobs.last!.finished};check(!app.jobs.last!.failed && app.jobs.last!.transferredBytes==0)
   check(!fm.fileExists(atPath:watchDisk.appendingPathComponent("cleanup/sub/drop").path) && fm.fileExists(atPath:watchDisk.appendingPathComponent("cleanup/sub/keep").path))
   print("PASS: "+mode+" hidden App partial directory cleanup deletes only confirmed nested file and retains unchecked sibling/parent")
   print("PASS: "+mode+" hidden App directory content checkbox selection uploads selected nested file only through authenticated FTP session")
   print("PASS: "+mode+" hidden App continuous update queues file using original FTP session, preserves chosen time without changing site settings, read-only entry refused and monitor stops")
   let retrySource=watchLocal.appendingPathComponent("retry.txt");try Data("old".utf8).write(to:retrySource)
   let retryLocal=try SyncPlanner.local(watchLocal.path),retryRemote=try SyncPlanner.remote(watchRemote,client:writer),retryContext=try SyncRetryContext(site:site,socket:token,settings:SyncSettings(),policy:TransferPolicy(),local:watchLocal.path,remote:watchRemote,client:writer)
   let retryAction=SyncCandidate(relative:"retry.txt",local:retryLocal["retry.txt"],remote:nil,upload:true,selected:true,typeConflict:false)
   app.togglePause();let retryJob=try app.enqueueSync([retryAction],localRoot:watchLocal.path,remoteRoot:watchRemote,localSnapshot:retryLocal,remoteSnapshot:retryRemote,deletions:[:],site:site,socket:token,policy:TransferPolicy(),retryContext:retryContext)[0]
   try Data("new source after failed preview".utf8).write(to:retrySource);app.togglePause();wait{retryJob.finished && !retryJob.isExecuting && !app.transfers.contains(retryJob.id)};check(retryJob.failed)
   let originalCount=app.jobs.count;app.queueTable.selectRowIndexes(IndexSet(integer:originalCount-1),byExtendingSelection:false);app.retrySelected();wait{app.syncRecomparePreviews[retryContext.id] != nil}
   check(app.jobs.count==originalCount && !fm.fileExists(atPath:watchDisk.appendingPathComponent("retry.txt").path))
   let retryPreview=app.syncRecomparePreviews[retryContext.id]!;check(retryPreview.candidates.map{$0.relative}==["retry.txt"]);retryPreview.apply();wait{app.jobs.count==originalCount+1 && app.jobs.last!.finished}
   check(!app.jobs.last!.failed && app.syncRetrySuperseded.contains(retryJob.id));check(try Data(contentsOf:watchDisk.appendingPathComponent("retry.txt"))==Data("new source after failed preview".utf8))
   try Data("not sent".utf8).write(to:watchLocal.appendingPathComponent("not-sent.txt"));let notSentLocal=try SyncPlanner.local(watchLocal.path),notSentAction=SyncCandidate(relative:"not-sent.txt",local:notSentLocal["not-sent.txt"],remote:nil,upload:true,selected:true,typeConflict:false)
   app.togglePause();let notSent=try app.enqueueSync([notSentAction],localRoot:watchLocal.path,remoteRoot:watchRemote,localSnapshot:notSentLocal,remoteSnapshot:try SyncPlanner.remote(watchRemote,client:writer),deletions:[:],site:site,socket:token,policy:TransferPolicy(),retryContext:retryContext)[0];notSent.cancel();app.transfers.refresh();app.togglePause();wait{notSent.finished && !notSent.isExecuting}
   print("PASS: "+mode+" failed synchronization re-compares via original FTP session, does not write before confirmation, creates fresh successful task and marks old failure handled")
   check(app.closeConnection(tab));check(readTab.usable && app.remoteConnectionReady);app.queueTable.selectRowIndexes(IndexSet(integer:app.jobs.count-1),byExtendingSelection:false);app.recompareSelectedSync();check(app.syncRecompareOperations.isEmpty && app.status.stringValue.contains("明确允许写入") && !fm.fileExists(atPath:watchDisk.appendingPathComponent("not-sent.txt").path));do{_ = try app.client(site,token);fatalError("closed FTP session reused credentials")}catch{}
   check(app.closeConnection(readTab));try app.startFTP(site,password:"wrong",caCertificate:mode=="plain" ? nil : certificate);let failed=app.currentConnection!;wait{if case .failed=failed.presentation{return true};return false};check(!app.remoteConnectionReady && failed.auth?.isVisible != true);check(app.closeConnection(failed))
   try app.startFTP(site,password:"macscp-test-only",caCertificate:mode=="plain" ? nil : certificate);let cancelledTab=app.currentConnection!;check(app.closeConnection(cancelledTab));check(cancelledTab.presentation == .cancelled && !app.remoteConnectionReady);RunLoop.current.run(until:Date().addingTimeInterval(0.1));check(app.connections.isEmpty && app.session==nil)
   let export=try app.siteStore!.exportData();check(!String(decoding:export,as:UTF8.self).contains("macscp-test-only"));app.window.close()
   let credentialVault=MemoryVault(),credentialSuite="credential-ftp-"+UUID().uuidString,credentialDefaults=UserDefaults(suiteName:credentialSuite)!;defer{credentialDefaults.removePersistentDomain(forName:credentialSuite)}
   let credentialApp=App(defaults:credentialDefaults,dataDirectory:workspace.appendingPathComponent("credentials-"+mode),initialLocalDirectory:localRoot.path,automaticLogin:false,showsMainWindow:false,transferOptionsEnabled:false,frameAutosaveName:nil,vault:credentialVault);credentialApp.applicationDidFinishLaunching(Notification(name:NSApplication.didFinishLaunchingNotification))
   func credentialLogin(_ password:String)throws{try credentialApp.startFTP(site,password:password,caCertificate:mode=="plain" ? nil : certificate)}
   func awaitCredentialLogin(){wait{credentialApp.remoteConnectionReady && !credentialApp.browsing && credentialApp.remote.currentPath=="/"}}
   func closeCredentialLogin(){check(credentialApp.closeConnection(credentialApp.currentConnection!))}
   try credentialLogin("macscp-test-only");awaitCredentialLogin();check(credentialVault.reads==0 && credentialVault.writes==0);closeCredentialLogin()
   try credentialApp.setRemembersPassword(site,true);try credentialLogin("wrong");let badCredential=credentialApp.currentConnection!;wait{if case .failed=badCredential.presentation{return true};return false};check(credentialVault.writes==0);closeCredentialLogin()
   try credentialLogin("macscp-test-only");closeCredentialLogin();RunLoop.current.run(until:Date().addingTimeInterval(0.05));check(credentialVault.writes==0)
   try credentialLogin("macscp-test-only");awaitCredentialLogin();let credentialKey=try PasswordEndpoint(site);check(credentialVault.writes==1 && credentialVault.values[credentialKey]=="macscp-test-only");closeCredentialLogin()
   try credentialLogin("");awaitCredentialLogin();check(credentialVault.reads==1 && credentialVault.writes==1);closeCredentialLogin()
   credentialVault.values[credentialKey]="wrong-saved";try credentialLogin("");let rejectedCredential=credentialApp.currentConnection!;wait{if case .failed=rejectedCredential.presentation{return true};return false};check(rejectedCredential.presentation.detail.contains("已保存密码未通过") && credentialVault.writes==1 && credentialVault.reads==2);closeCredentialLogin()
   try credentialLogin("macscp-test-only");awaitCredentialLogin();check(credentialVault.writes==2 && credentialVault.reads==2 && credentialVault.values[credentialKey]=="macscp-test-only");closeCredentialLogin()
   credentialVault.failRead=true;do{try credentialLogin("");fatalError("vault read failure ignored")}catch{};check(credentialApp.connections.isEmpty);credentialVault.failRead=false
   credentialVault.failWrite=true;try credentialLogin("macscp-test-only");awaitCredentialLogin();check(credentialApp.currentConnection!.credentialNotice != nil && credentialApp.remoteConnectionReady);credentialVault.failWrite=false
   try credentialApp.forgetPassword(site);check(!credentialApp.remembersPassword(site) && credentialVault.values[credentialKey]==nil && credentialApp.remoteConnectionReady);closeCredentialLogin()
   try credentialApp.setRemembersPassword(site,true);let writesBeforeForget=credentialVault.writes;try credentialLogin("macscp-test-only");try credentialApp.forgetPassword(site);awaitCredentialLogin();check(credentialVault.writes==writesBeforeForget);closeCredentialLogin()
   let credentialExport=try credentialApp.siteStore!.exportData();check(!String(decoding:credentialExport,as:UTF8.self).contains("macscp-test-only"));check(!String(describing:credentialDefaults.persistentDomain(forName:credentialSuite)).contains("macscp-test-only"));credentialApp.window.close()
   print("PASS: "+mode+" hidden App credential lifecycle with isolated vault: off-by-default, save after success only, cancel/failure no save, successful reuse without rewrite, rejected saved password, corrected update, read/write errors, forget while connected/in-flight and no export; no system keychain")
   print("PASS: "+mode+" hidden production App FTP login, real listing and queued upload, synchronous recovery write failure blocks remote STOR, protocol badges, read-only controls/drop refusal, independent tabs, failed login, cancellation/late callbacks and no credential export; no visible window or password prompt")
   fixture.stop()
  }
  for (mode,security) in [("plain",FTPConnection.Security.plain),("explicit",.explicitTLS),("implicit",.implicitTLS)]{
   let deniedPublication=try Fixture(root:root,workspace:workspace,security:mode,certificate:mode=="plain" ? nil : certificate,key:mode=="plain" ? nil : key,denyPublishOnce:true);defer{deniedPublication.stop()}
   let connection=try FTPConnection(host:"127.0.0.1",user:"fixture",password:"macscp-test-only",port:deniedPublication.port,security:security,caCertificate:mode=="plain" ? nil : certificate)
   let writer=try FTPClient(connection,publicationPolicy:.allowNonAtomic);defer{writer.close()}
   let name="denied-publication-"+mode,target=root.appendingPathComponent(name);try Data("preserve on RNTO denial".utf8).write(to:target)
   do{try writer.upload(source,to:"/"+name,overwrite:true,permissions:nil,beforeCommit:nil);fatalError("RNTO denial ignored")}catch{}
   check(try Data(contentsOf:target)==Data("preserve on RNTO denial".utf8));check(try fm.contentsOfDirectory(atPath:root.path).allSatisfy{!$0.hasPrefix(name+".macscp-")})
   try writer.upload(source,to:"/"+name,overwrite:true,permissions:nil,beforeCommit:nil);check(try Data(contentsOf:target)==data);deniedPublication.stop()
   print("PASS: "+mode+" real RNTO denial after backup restored original, cleaned owned stage/backup and permitted a fresh upload")
  }
  let fallback=try Fixture(root:root,workspace:workspace,security:"plain",certificate:nil,key:nil,unsupportedMLSD:true);defer{fallback.stop()}
  let fallbackTransport=try FTPCurlTransport(FTPConnection(host:"127.0.0.1",user:"fixture",password:"macscp-test-only",port:fallback.port,security:.plain));defer{fallbackTransport.close()}
  let fallbackReader=FTPDirectoryReader(transport:fallbackTransport);check(try fallbackReader.list("/").contains{$0.name==name});fallback.stop()
  let strictFixture=try Fixture(root:root,workspace:workspace,security:"plain",certificate:nil,key:nil,unsupportedMLSD:true);defer{strictFixture.stop()}
  let strictConnection=try FTPConnection(host:"127.0.0.1",user:"fixture",password:"macscp-test-only",port:strictFixture.port,security:.plain,options:FTPSiteOptions(listing:.machineOnly)),strictClient=try FTPClient(strictConnection);defer{strictClient.close()}
  do{_ = try strictClient.list("/");fatalError("MLSD-only silently fell back")}catch let error as FTPCurlFailure{check(error.reply==502)};strictFixture.stop()
  let authLog=workspace.appendingPathComponent("auth-order.txt"),migratedFixture=try Fixture(root:root,workspace:workspace,security:"explicit",certificate:certificate,key:key,deniedMLSD:true,authLog:authLog);defer{migratedFixture.stop()}
  let migratedINI="""
  [Sessions\\migrated]
  HostName=127.0.0.1
  UserName=fixture
  FSProtocol=5
  Ftps=2
  PortNumber=\(migratedFixture.port)
  Timeout=9
  FtpUseMlsd=off
  """
  let migrated=try SiteImportPlan.read(Data(migratedINI.utf8),fileExtension:"ini").candidates[0].session!
  let suite="ftp-migrated-"+UUID().uuidString,isolated=UserDefaults(suiteName:suite)!;defer{isolated.removePersistentDomain(forName:suite)}
  let migratedApp=App(defaults:isolated,dataDirectory:workspace.appendingPathComponent("migrated-profile"),initialLocalDirectory:workspace.path,automaticLogin:false,showsMainWindow:false,transferOptionsEnabled:false,frameAutosaveName:nil);migratedApp.applicationDidFinishLaunching(Notification(name:NSApplication.didFinishLaunchingNotification))
  try migratedApp.startFTP(migrated,password:"macscp-test-only",caCertificate:certificate);wait{migratedApp.remoteConnectionReady && !migratedApp.browsing && migratedApp.remote.currentPath=="/"}
  check(migratedApp.remote.entries.contains{$0.name==name} && !migratedApp.remoteWriteAvailable && !migratedApp.window.isVisible)
  let migratedClient=try migratedApp.client(migrated,migratedApp.socket) as! FTPClient;check(migratedClient.transport.connection.options.connectTimeout==9 && migratedClient.transport.connection.options.listingMode == .legacy);migratedClient.close()
  let firstAUTH=try String(contentsOf:authLog,encoding:.utf8).split(separator:"\n").first;check(firstAUTH=="SSL");check(migratedApp.closeConnection(migratedApp.currentConnection!));migratedApp.window.close();migratedFixture.stop()
  let delayed=try Fixture(root:root,workspace:workspace,security:"plain",certificate:nil,key:nil,greetingDelay:3);defer{delayed.stop()}
  let timeoutConnection=try FTPConnection(host:"127.0.0.1",user:"fixture",password:"macscp-test-only",port:delayed.port,security:.plain,options:FTPSiteOptions(timeout:1)),timeoutClient=try FTPCurlTransport(timeoutConnection);defer{timeoutClient.close()};let timeoutBegan=Date()
  do{_ = try timeoutClient.perform(.entryDirectory);fatalError("FTP greeting timeout ignored")}catch let error as FTPCurlFailure{check(error.code==28 && Date().timeIntervalSince(timeoutBegan)<2.5)};delayed.stop()
  let responseDelayed=try Fixture(root:root,workspace:workspace,security:"plain",certificate:nil,key:nil,sizeDelay:3);defer{responseDelayed.stop()}
  let responseConnection=try FTPConnection(host:"127.0.0.1",user:"fixture",password:"macscp-test-only",port:responseDelayed.port,security:.plain,options:FTPSiteOptions(timeout:1)),responseClient=try FTPCurlTransport(responseConnection);defer{responseClient.close()};_ = try responseClient.perform(.entryDirectory);let responseBegan=Date()
  do{_ = try responseClient.perform(.metadata("/"+name));fatalError("FTP command response timeout ignored")}catch let error as FTPCurlFailure{check(error.code==28 && Date().timeIntervalSince(responseBegan)<2.5)};responseDelayed.stop()
  print("PASS: WinSCP INI imported into real hidden App: forced LIST bypasses denied MLSD, AUTH SSL preference observed, native connect and authenticated-command response timeouts, MLSD-only refuses fallback; no user endpoints")
  let denied=try Fixture(root:root,workspace:workspace,security:"plain",certificate:nil,key:nil,deniedMLSD:true);defer{denied.stop()}
  let deniedTransport=try FTPCurlTransport(FTPConnection(host:"127.0.0.1",user:"fixture",password:"macscp-test-only",port:denied.port,security:.plain));defer{deniedTransport.close()}
  do{_ = try FTPDirectoryReader(transport:deniedTransport).list("/");fatalError("permission failure hidden by LIST fallback")}catch let error as FTPCurlFailure{check(error.reply==550)};denied.stop()
  let uploadFixture=try Fixture(root:root,workspace:workspace,security:"plain",certificate:nil,key:nil,failUploadOnce:true);defer{uploadFixture.stop()}
  let uploadConnection=try FTPConnection(host:"127.0.0.1",user:"fixture",password:"macscp-test-only",port:uploadFixture.port,security:.plain),uploadFirst=try FTPClient(uploadConnection,publicationPolicy:.allowNonAtomic);defer{uploadFirst.close()}
  let uploadPath="/upload-resumed",uploadTarget=root.appendingPathComponent("upload-resumed");try Data("original upload target".utf8).write(to:uploadTarget)
  let uploadState=TransferResume(source:source.path,destination:uploadPath,upload:true)
  do{try uploadFirst.uploadResumable(source,to:uploadPath,state:uploadState,overwrite:true,verifyChecksum:true);fatalError("injected STOR failure not observed")}catch{};check(try Data(contentsOf:uploadTarget)==Data("original upload target".utf8))
  let partial=try uploadFirst.attributes(uploadState.temporaryPath);check((partial?.size ?? 0)>0 && (partial?.size ?? 0)<UInt64(data.count))
  let noOverwrite=try FTPClient(uploadConnection,publicationPolicy:.allowNonAtomic);defer{noOverwrite.close()}
  do{try noOverwrite.uploadResumable(source,to:uploadPath,state:TransferResume(record:uploadState.record()),overwrite:false,verifyChecksum:true);fatalError("resume forgot overwrite permission")}catch{};check(try Data(contentsOf:uploadTarget)==Data("original upload target".utf8))
  let corruptUpload=try FileHandle(forUpdating:root.appendingPathComponent(String(uploadState.temporaryPath.dropFirst())));try corruptUpload.write(contentsOf:Data([255]));try corruptUpload.close()
  let badUploadPrefix=try FTPClient(uploadConnection,publicationPolicy:.allowNonAtomic);defer{badUploadPrefix.close()}
  do{try badUploadPrefix.uploadResumable(source,to:uploadPath,state:TransferResume(record:uploadState.record()),overwrite:true,verifyChecksum:true);fatalError("corrupt upload prefix accepted")}catch{};check(try Data(contentsOf:uploadTarget)==Data("original upload target".utf8))
  let fixUpload=try FileHandle(forUpdating:root.appendingPathComponent(String(uploadState.temporaryPath.dropFirst())));try fixUpload.write(contentsOf:data.prefix(1));try fixUpload.close()
  let secondWriter=try FTPClient(uploadConnection,publicationPolicy:.allowNonAtomic);defer{secondWriter.close()};var uploadedPrefix:UInt64=0,uploadedNew:UInt64=0;secondWriter.resumedProgress={uploadedPrefix+=$0};secondWriter.progress={uploadedNew+=$0}
  try secondWriter.uploadResumable(source,to:uploadPath,state:TransferResume(record:try JSONDecoder().decode(ResumeRecord.self,from:JSONEncoder().encode(uploadState.record()))),overwrite:true,verifyChecksum:true)
  check(try uploadedPrefix>0 && uploadedNew<UInt64(data.count) && Data(contentsOf:uploadTarget)==data);uploadFixture.stop()
  print("PASS: FTP partial STOR failure preserved old target; fresh client and decoded publication record verified prefix and resumed native APPE before publishing")
  let noTimeFixture=try Fixture(root:root,workspace:workspace,security:"plain",certificate:nil,key:nil,unsupportedMFMT:true);defer{noTimeFixture.stop()}
  let noTimeConnection=try FTPConnection(host:"127.0.0.1",user:"fixture",password:"macscp-test-only",port:noTimeFixture.port,security:.plain)
  let timeLogin=FTPLoginSession(connection:noTimeConnection,settings:FTPSiteOptions(allowNonAtomicWrites:true));defer{timeLogin.cancel()};_ = try timeLogin.authenticate()
  let timeRequired=try timeLogin.makeClient(preserveUploadTime:true);defer{timeRequired.close()};check(timeRequired.capabilities.contains(.timestamps))
  let timePath=root.appendingPathComponent("unsupported-time-target");try Data("original time target".utf8).write(to:timePath)
  do{try timeRequired.upload(source,to:"/unsupported-time-target",overwrite:true,permissions:nil,beforeCommit:nil);fatalError("unsupported MFMT ignored")}catch{check(error.localizedDescription.contains("MFMT"))}
  check(try Data(contentsOf:timePath)==Data("original time target".utf8))
  let noTimeRequired=try timeLogin.makeClient();defer{noTimeRequired.close()};check(!noTimeRequired.capabilities.contains(.timestamps))
  try noTimeRequired.upload(source,to:"/unsupported-time-target",overwrite:true,permissions:nil,beforeCommit:nil);check(try Data(contentsOf:timePath)==data)
  print("PASS: time-sync-only FTP override refuses unsupported MFMT before publishing, preserves original target, and leaves ordinary no-time upload available")
  let permissionsFixture=try Fixture(root:root,workspace:workspace,security:"plain",certificate:nil,key:nil,noPermissions:true);defer{permissionsFixture.stop()}
  let permissionsConnection=try FTPConnection(host:"127.0.0.1",user:"fixture",password:"macscp-test-only",port:permissionsFixture.port,security:.plain)
  let unknownPermissions=try FTPClient(permissionsConnection,publicationPolicy:.allowNonAtomic);defer{unknownPermissions.close()}
  let permissionsTarget=root.appendingPathComponent("unknown-permissions");try Data("keep original permissions".utf8).write(to:permissionsTarget);try fm.setAttributes([.posixPermissions:0o640],ofItemAtPath:permissionsTarget.path)
  do{try unknownPermissions.upload(source,to:"/unknown-permissions",overwrite:true,permissions:nil,beforeCommit:nil);fatalError("unknown permissions invented")}catch{}
  check(try Data(contentsOf:permissionsTarget)==Data("keep original permissions".utf8));check((try fm.attributesOfItem(atPath:permissionsTarget.path)[.posixPermissions] as? NSNumber)?.intValue==0o640)
  check(try fm.contentsOfDirectory(atPath:root.path).allSatisfy{!$0.hasPrefix("unknown-permissions.macscp-resume-")})
  let noPreservation=try FTPClient(permissionsConnection,publicationPolicy:.allowNonAtomic,preserveUploadPermissions:false);defer{noPreservation.close()};try noPreservation.upload(source,to:"/unknown-permissions",overwrite:true,permissions:nil,beforeCommit:nil);check(try Data(contentsOf:permissionsTarget)==data);permissionsFixture.stop()
  print("PASS: unknown original permissions refuse preservation before STOR; explicit no-preservation mode uploads without inventing mode 000")
  let metadataFixture=try Fixture(root:root,workspace:workspace,security:"plain",certificate:nil,key:nil,noMetadata:true);defer{metadataFixture.stop()}
  let metadataClient=try FTPClient(FTPConnection(host:"127.0.0.1",user:"fixture",password:"macscp-test-only",port:metadataFixture.port,security:.plain));defer{metadataClient.close()}
  let metadata=try metadataClient.attributes("/"+name);check(metadata?.size==UInt64(data.count) && (metadata?.modified ?? 0)>0);metadataFixture.stop()
  let unknownFixture=try Fixture(root:root,workspace:workspace,security:"plain",certificate:nil,key:nil,noMetadata:true,unsupportedMDTM:true);defer{unknownFixture.stop()}
  let unknownClient=try FTPClient(FTPConnection(host:"127.0.0.1",user:"fixture",password:"macscp-test-only",port:unknownFixture.port,security:.plain));defer{unknownClient.close()}
  do{_ = try unknownClient.attributes("/"+name);fatalError("unknown source date invented")}catch{};unknownFixture.stop()
  let textFixture=try Fixture(root:root,workspace:workspace,security:"plain",certificate:nil,key:nil,failUploadOnce:true);defer{textFixture.stop()}
  let tc=try FTPConnection(host:"127.0.0.1",user:"fixture",password:"macscp-test-only",port:textFixture.port,security:.plain),textSource=workspace.appendingPathComponent("resume-text.txt"),textPath="/resume-text.txt",textOld=Data("original text target".utf8)
  let textRaw=Data(String(repeating:"text line\n",count:30000).utf8),textConverted=Data(String(repeating:"text line\r\n",count:30000).utf8);try textRaw.write(to:textSource);try textOld.write(to:root.appendingPathComponent("resume-text.txt"))
  let textState=TransferResume(source:textSource.path,destination:textPath,upload:true),textFirst=try FTPClient(tc,publicationPolicy:.allowNonAtomic),textSettings=TextTransferOptions(mode:.text,remote:.crlf)
  do{try TextTransfer.upload(textSource.path,to:textPath,state:textState,client:textFirst,options:textSettings,overwrite:true,verify:true,checkpoint:{});fatalError("text STOR interruption not observed")}catch{};textFirst.close();check(try Data(contentsOf:root.appendingPathComponent("resume-text.txt"))==textOld)
  let textSaved=try JSONEncoder().encode(textState.record()),textRestored=TransferResume(record:try JSONDecoder().decode(ResumeRecord.self,from:textSaved));check(textRestored.source==textSource.path && textRestored.ftpPublication != nil)
  let textSecond=try FTPClient(tc,publicationPolicy:.allowNonAtomic);var textReused:UInt64=0;textSecond.resumedProgress={textReused+=$0};try TextTransfer.upload(textSource.path,to:textPath,state:textRestored,client:textSecond,options:textSettings,overwrite:true,verify:true,checkpoint:{});textSecond.close();check(textReused>0);check(try Data(contentsOf:root.appendingPathComponent("resume-text.txt"))==textConverted)
  textFixture.stop();print("PASS: real FTP text converted-prefix resume after JSON recovery retains publication binding and original target during failure")
  print("PASS: real FTP, explicit and implicit FTPS; private in-memory credentials, chain and hostname certificate rejection, no TLS downgrade, bad auth and cancellation; no user server/config/trust store")
 }
}
