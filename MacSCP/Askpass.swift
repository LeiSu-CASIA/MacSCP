import Cocoa
final class SSHSecretField:NSSecureTextField,NSTextFieldDelegate {
 weak var submitButton:NSButton?;var requiresValue=false
 override var stringValue:String{get{super.stringValue}set{super.stringValue=newValue;updateSubmission()}}
 func updateSubmission(){submitButton?.isEnabled = !requiresValue || !stringValue.isEmpty}
 func controlTextDidChange(_ notification:Notification){updateSubmission()}
}
struct AskpassPrompt {
 let text:String;let confirmation:Bool
 var requiresNonemptyResponse:Bool{!confirmation && text.localizedCaseInsensitiveContains("passphrase")}
 init(text:String,hint:String?=nil){self.text=text;confirmation=hint=="confirm" || text.localizedCaseInsensitiveContains("Are you sure you want to continue connecting")}
 func alert(server:String?=nil)->(NSAlert,NSSecureTextField?){let a=NSAlert();a.messageText=confirmation ? "确认 SSH 主机身份" : "SSH 身份验证";let scroll=NSScrollView(frame:NSRect(x:0,y:0,width:540,height:170));scroll.hasVerticalScroller=true;let description=NSTextView(frame:scroll.bounds);description.isEditable=false;description.isRichText=false;description.font = .systemFont(ofSize:12);description.string=text;scroll.documentView=description;let form=NSView(frame:NSRect(x:0,y:0,width:540,height:confirmation ? 180 : 225));scroll.frame.origin.y=confirmation ? 5 : 50;form.addSubview(scroll);var field:NSSecureTextField?;if !confirmation{let input=SSHSecretField(frame:NSRect(x:0,y:8,width:540,height:28));input.placeholderString="密码 / 私钥口令 / 验证码";form.addSubview(input);field=input};a.accessoryView=form;if let field=field{a.window.initialFirstResponder=field};a.informativeText=confirmation ? "请通过可信渠道核对上方指纹。确认后由 OpenSSH 记录主机密钥。" : "输入仅交给本次 OpenSSH 认证，不保存到站点或日志。";if let server=server,!server.isEmpty{a.informativeText="服务器："+server+"\n"+a.informativeText};a.addButton(withTitle:confirmation ? "核对后信任并连接" : "提交");a.addButton(withTitle:"取消");if let input=field as? SSHSecretField{input.requiresValue=requiresNonemptyResponse;input.submitButton=a.buttons.first;input.delegate=input;input.updateSubmission()};return(a,field)}
}
// Private per-connection signal: no password or other authentication value is stored.
final class SSHAuthenticationCancellation {
 let directory:URL
 var path:String{directory.appendingPathComponent("cancelled").path}
 var requested:Bool{FileManager.default.fileExists(atPath:path)}
 init(root:URL=FileManager.default.temporaryDirectory)throws{
  directory=root.appendingPathComponent("macscp-auth-"+UUID().uuidString,isDirectory:true)
  try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
 }
 static func wasRequested(environment:[String:String])->Bool{environment["MACSCP_AUTH_CANCEL_FILE"].map{FileManager.default.fileExists(atPath:$0)} ?? false}
 static func request(environment:[String:String]){
  guard let path=environment["MACSCP_AUTH_CANCEL_FILE"] else{return}
  _ = FileManager.default.createFile(atPath:path,contents:Data(),attributes:[.posixPermissions:0o600])
 }
 deinit{try? FileManager.default.removeItem(at:directory)}
}
enum SSHLoginEnvironment {
 static func authenticationExecutable(bundleURL:URL,fallback:String)->String{let helper=bundleURL.appendingPathComponent("Contents/Helpers/MacSCP-Authentication.app/Contents/MacOS/MacSCP-Authentication").path;return FileManager.default.isExecutableFile(atPath:helper) ? helper : fallback}
 static func make(base:[String:String],helper:String,executable:String,cancellation:String?=nil,server:String?=nil,credentialSocket:String?=nil,credentialToken:String?=nil,credentialOwner:Int32?=nil)->[String:String]{var env=base;env["MACSCP_AUTH_OWNER_PID"]=credentialOwner.map(String.init);env["MACSCP_AUTH_SOCKET"]=credentialSocket;env["MACSCP_AUTH_TOKEN"]=credentialToken;env["MACSCP_AUTH_SERVER"]=server;env["MACSCP_AUTH_CANCEL_FILE"]=cancellation;env.removeValue(forKey:"SSH_ASKPASS_PROMPT");env["SSH_ASKPASS"]=helper;env["SSH_ASKPASS_REQUIRE"]="force";env["MACSCP_EXECUTABLE"]=executable;env["DISPLAY"]=base["DISPLAY"] ?? "macscp";env["LC_ALL"]="C";return env}
 static func monitorParent(_ parent:pid_t,onExit:@escaping()->Void)->Timer{let timer=Timer(timeInterval:0.2,repeats:true){_ in if getppid() != parent || kill(parent,0) != 0{onExit()}};RunLoop.current.add(timer,forMode:.common);RunLoop.current.add(timer,forMode:.modalPanel);return timer}
 static func answer(prompt:String,allowInteraction:Bool=true)->Int32{
  let environment=ProcessInfo.processInfo.environment;guard !SSHAuthenticationCancellation.wasRequested(environment:environment) else{return 1}
  let hint=environment["SSH_ASKPASS_PROMPT"],parsed=AskpassPrompt(text:prompt,hint:hint),stored=SSHCredentialClient.lookup(prompt:prompt,hint:hint,environment:environment)
  if let value=stored?.answer{do{try FileHandle.standardOutput.write(contentsOf:Data((value+"\n").utf8));return 0}catch{return 1}}
  guard allowInteraction else{return 1}
  let app=NSApplication.shared;app.setActivationPolicy(.accessory);app.finishLaunching();let(alert,field)=parsed.alert(server:environment["MACSCP_AUTH_SERVER"])
  if stored?.eligible==true{alert.informativeText += "\n已选择认证成功后保存服务器密码到钥匙串。"};if stored?.rejectedSavedPassword==true{alert.informativeText += "\n保存的密码未通过认证，请重新输入；不会重复自动填入。"}
  alert.window.title=parsed.confirmation ? "确认 SSH 主机身份" : "SSH 身份验证";let parent=getppid();let timer=monitorParent(parent){app.abortModal()};app.activate(ignoringOtherApps:true);let response=alert.runModal();timer.invalidate()
  guard response == .alertFirstButtonReturn else{SSHAuthenticationCancellation.request(environment:environment);return 1};let value=parsed.confirmation ? "yes" : field?.stringValue ?? ""
  guard (!parsed.requiresNonemptyResponse || !value.isEmpty),value.utf8.count<=4096,!value.unicodeScalars.contains(where:{[0,10,13].contains($0.value)}) else{SSHAuthenticationCancellation.request(environment:environment);return 1}
  if !parsed.confirmation,stored?.eligible==true{SSHCredentialClient.submitted(value,prompt:prompt,hint:hint,environment:environment)}
  do{try FileHandle.standardOutput.write(contentsOf:Data((value+"\n").utf8));return 0}catch{return 1}
 }
}
