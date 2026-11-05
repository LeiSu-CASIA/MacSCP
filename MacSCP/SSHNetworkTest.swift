import Cocoa
@main struct SSHNetworkTests {
 static func waitSocket(_ socket:String,_ process:Process)throws{let end=Date().addingTimeInterval(10);while Date()<end{if FileManager.default.fileExists(atPath:socket){return};if !process.isRunning{throw SFTPError.message("SSH 测试主连接提前退出")};Thread.sleep(forTimeInterval:0.02)};process.terminate();throw SFTPError.message("SSH 测试连接超时")}
 static func master(_ session:Session,_ socket:String,_ config:String,_ log:URL)throws->Process{let p=Process();p.executableURL=URL(fileURLWithPath:"/usr/bin/ssh");p.arguments=["-F",config]+(try SSHArguments.master(session,socket:socket));p.standardInput=FileHandle.nullDevice;p.standardOutput=FileHandle.nullDevice;FileManager.default.createFile(atPath:log.path,contents:nil);p.standardError=try FileHandle(forWritingTo:log);try p.run();try waitSocket(socket,p);return p}
 static func waitRunLoop(_ condition:()->Bool)throws{let end=Date().addingTimeInterval(10);while !condition() && Date()<end{RunLoop.current.run(until:Date().addingTimeInterval(0.02))};guard condition() else{throw SFTPError.message("认证集成测试超时")}}
 static func main()throws{NSApplication.shared.setActivationPolicy(.prohibited);let root=URL(fileURLWithPath:CommandLine.arguments[1]),targetPort=Int(CommandLine.arguments[2])!,jumpPort=Int(CommandLine.arguments[3])!;let config=root.appendingPathComponent("client.conf").path;let site=Session(name:"local-fixture",host:"127.0.0.1",user:NSUserName(),port:targetPort,key:root.appendingPathComponent("client_key").path);let socket=root.appendingPathComponent("control").path;let connection=try master(site,socket,config,root.appendingPathComponent("master.log"));defer{if connection.isRunning{connection.terminate();connection.waitUntilExit()}};let c=try SFTPClient(arguments:["-F",config]+SSHArguments.sftp(site,socket:socket));defer{c.close()};let directory=root.appendingPathComponent("中文 space ' $; directory");try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:false);let input=root.appendingPathComponent("input.bin"),remote=directory.appendingPathComponent("remote ' $.bin"),output=root.appendingPathComponent("output.bin");let bytes=Data((0..<180000).map{UInt8($0%251)});try bytes.write(to:input);try c.upload(input,to:remote.path);try c.download(remote.path,to:output);let actual=try Data(contentsOf:output);precondition(actual==bytes);let entries=try c.list(directory.path);precondition(entries.contains{$0.name==remote.lastPathComponent})
 var terminalArgs=try SSHArguments.terminal(site,socket:socket,directory:directory.path);terminalArgs.removeLast();terminalArgs.append("cd -- "+(try ShellPath.quote(directory.path))+" && printf 'MACSCP_TERMINAL=' && /bin/pwd");if let i=terminalArgs.firstIndex(of:"-t"){terminalArgs[i]="-tt"};let terminal=Process();terminal.executableURL=URL(fileURLWithPath:"/usr/bin/ssh");terminal.arguments=["-F",config]+terminalArgs;terminal.standardInput=FileHandle.nullDevice;terminal.standardError=FileHandle.nullDevice;let pipe=Pipe();terminal.standardOutput=pipe;try terminal.run();let text=String(decoding:pipe.fileHandleForReading.readDataToEndOfFile(),as:UTF8.self);terminal.waitUntilExit();precondition(terminal.terminationStatus==0 && text.contains("MACSCP_TERMINAL=") && text.contains(directory.lastPathComponent))
 var jumped=site;jumped.options=SSHOptions(jumpHost:NSUserName()+"@127.0.0.1:"+String(jumpPort),connectTimeout:5,keepAliveInterval:2,keepAliveCount:2,compression:true);let jumpedSocket=root.appendingPathComponent("jump-control").path;let viaJump=try master(jumped,jumpedSocket,config,root.appendingPathComponent("jump-master.log"));defer{if viaJump.isRunning{viaJump.terminate();viaJump.waitUntilExit()}};let sc=try SFTPClient(arguments:["-F",config]+SSHArguments.sftp(jumped,socket:jumpedSocket));defer{sc.close()};let path=try sc.canonical(directory.path);precondition(path.hasSuffix(directory.lastPathComponent));let throughJump=try sc.checksum(remote.path);let direct=try c.checksum(remote.path);precondition(throughJump==direct)


 var targetServer=site;targetServer.port=jumpPort
 let targetSocket=root.appendingPathComponent("target-server-control").path
 let targetConnection=try master(targetServer,targetSocket,config,root.appendingPathComponent("target-master.log"));defer{if targetConnection.isRunning{targetConnection.terminate();targetConnection.waitUntilExit()}}
 let relay=try RelayTransfer(file:DragFile(path:remote.path,directory:false,size:UInt64(bytes.count),connection:socket),destination:root.appendingPathComponent("network-relay ' 中文.bin").path,sourceSite:site,targetSite:targetServer)
 relay.download.factory={try SFTPClient(arguments:["-F",config]+SSHArguments.sftp(site,socket:socket))}
 relay.upload.factory={try SFTPClient(arguments:["-F",config]+SSHArguments.sftp(targetServer,socket:targetSocket))}
 let relayJournal=try RelayJournal(url:root.appendingPathComponent("relay-queue.json"))
 func observe(_ item:RelayTransfer){item.enableRecovery();item.recoveryChanged={[weak item] force in guard let item=item else{return};if let record=item.recoveryRecord(){try! relayJournal.save(record,force:force)}else{try! relayJournal.remove(item.id)}}}
 observe(relay)
 relay.changed={[weak relay] in if let relay=relay,relay.upload.transferredBytes>=32768{relay.suspendForExit()}}
 let transferQueue=TransferScheduler();transferQueue.isSuspended=true;try relay.start(on:transferQueue);relay.upload.speedLimit=65536;transferQueue.isSuspended=false
 try waitRunLoop{relay.canDiscard}
 guard relay.phase == .failed,let saved=relayJournal.list().first else{throw SFTPError.message("网络中转未保留恢复记录")}
 let recovered=try RelayTransfer(record:saved);observe(recovered)
 recovered.download.factory={try SFTPClient(arguments:["-F",config]+SSHArguments.sftp(site,socket:socket))}
 recovered.upload.factory={try SFTPClient(arguments:["-F",config]+SSHArguments.sftp(targetServer,socket:targetSocket))}
 let recoveredQueue=TransferScheduler();try recovered.start(on:recoveredQueue)
 try waitRunLoop{recovered.canDiscard}
 precondition(recovered.upload.reusedBytes>=32768 && relayJournal.list().isEmpty)
 guard recovered.phase == .completed else{throw SFTPError.message("双服务器中转失败："+relay.download.column("progress")+" / "+relay.upload.column("progress"))}
 let targetClient=try SFTPClient(arguments:["-F",config]+SSHArguments.sftp(targetServer,socket:targetSocket));defer{targetClient.close()}
 let relayDigest=try targetClient.checksum(relay.upload.destination)
 precondition(relayDigest==direct && !FileManager.default.fileExists(atPath:relay.staging.path))
 let bridge=URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent("Resources/ssh-askpass.sh").path
 var encrypted=site;encrypted.key=root.appendingPathComponent("encrypted_key").path
 let authConfig=root.appendingPathComponent("client-encrypted.conf").path
 let authSocket=root.appendingPathComponent("auth-control").path
 let authenticated=SSHConnection(arguments:["-F",authConfig]+(try SSHArguments.master(encrypted,socket:authSocket)),helper:bridge,executable:root.appendingPathComponent("fixture askpass").path)
 defer{authenticated.stop()}
 try waitRunLoop{FileManager.default.fileExists(atPath:authSocket) || authenticated.exitCode != nil}
 precondition(authenticated.exitCode==nil && FileManager.default.fileExists(atPath:authSocket))
 authenticated.markConnected()
 let authClient=try SFTPClient(arguments:["-F",authConfig]+SSHArguments.sftp(encrypted,socket:authSocket));defer{authClient.close()}
 let authenticatedDigest=try authClient.checksum(remote.path);precondition(authenticatedDigest==direct)
 authenticated.stop();try waitRunLoop{authenticated.exitCode != nil}
 try Data().write(to:root.appendingPathComponent("cancel-mode"))
 let cancelled=SSHConnection(arguments:["-F",authConfig]+(try SSHArguments.master(encrypted,socket:root.appendingPathComponent("cancel-control").path)),helper:bridge,executable:root.appendingPathComponent("fixture askpass").path)
 defer{cancelled.stop()}
 try waitRunLoop{cancelled.exitCode != nil}
 precondition(cancelled.authenticationCancellation?.requested==true && cancelled.message.stringValue.contains("已取消"))
 precondition(!FileManager.default.fileExists(atPath:root.appendingPathComponent("cancel-control").path))
 connection.terminate();connection.waitUntilExit();Thread.sleep(forTimeInterval:0.1);do{let unexpected=try SFTPClient(arguments:["-F",config]+SSHArguments.sftp(site,socket:socket));unexpected.close();fatalError("dead multiplex master must not fall back to direct login")}catch{}
 print("PASS: real loopback SSH authentication, master socket/SFTP list and binary transfer, quoted remote PTY command directory, ProxyJump authentication/forwarding/SFTP, dead-master fail-closed, real encrypted-key authentication through SSHConnection/packaged askpass bridge, per-attempt cancellation, dependency-managed relay preserved/reconstructed/resumed across two separate SSH server connections")}
}
