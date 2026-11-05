import Cocoa
import Security
private final class MemoryPasswordVault:PasswordVault {
 var values=[PasswordEndpoint:String](),reads=0,writes=0,removals=0
 func password(for endpoint:PasswordEndpoint)throws->String?{reads+=1;return values[endpoint]}
 func save(_ password:String,for endpoint:PasswordEndpoint)throws{writes+=1;values[endpoint]=password}
 func forget(_ endpoint:PasswordEndpoint)throws{removals+=1;values.removeValue(forKey:endpoint)}
}
private final class FakeKeychainAPI {
 let endpoint:PasswordEndpoint;var allowed=true,data:Data?,itemCalls=0,readError:OSStatus=errSecSuccess,disableError:OSStatus=errSecSuccess,copyError:OSStatus=errSecSuccess,restoreFailures=0
 init(_ endpoint:PasswordEndpoint){self.endpoint=endpoint}
 func verify(_ query:[String:Any]){precondition(!allowed && query[kSecAttrService as String] as? String == "local.macscp.server-password.v1" && query[kSecAttrAccount as String] as? String == endpoint.account);itemCalls+=1}
 func operations()->PasswordKeychainOperations{PasswordKeychainOperations(interaction:{(self.readError,self.allowed)},setInteraction:{value in if !value,self.disableError != errSecSuccess{return self.disableError};if value,self.restoreFailures>0{self.restoreFailures-=1;return errSecAuthFailed};self.allowed=value;return errSecSuccess},copy:{query in self.verify(query);if self.copyError != errSecSuccess{return(self.copyError,nil)};return self.data.map{(errSecSuccess,$0)} ?? (errSecItemNotFound,nil)},update:{query,attributes in self.verify(query);guard self.data != nil else{return errSecItemNotFound};self.data=attributes[kSecValueData as String] as? Data;return errSecSuccess},add:{query in self.verify(query);self.data=query[kSecValueData as String] as? Data;return errSecSuccess},remove:{query in self.verify(query);let exists=self.data != nil;self.data=nil;return exists ? errSecSuccess : errSecItemNotFound})}
}
@main struct PasswordVaultTests {
 static func check(_ value:Bool){precondition(value)}
 static func main()throws{
  NSApplication.shared.setActivationPolicy(.prohibited)
  let site=Session(name:"fixture",host:"EXAMPLE.invalid",user:"demo",port:22,key:""),key=try PasswordEndpoint(site)
  var lower=site;lower.host=site.host.lowercased();check(try PasswordEndpoint(lower)==key)
  var other=site;other.protocolKind = .ftp;check(try PasswordEndpoint(other) != key);other=site;other.port=2222;check(try PasswordEndpoint(other) != key);other=site;other.user="Demo";check(try PasswordEndpoint(other) != key)
  var empty=site;empty.user="";do{_ = try PasswordEndpoint(empty);fatalError("ambiguous default user")}catch{}
  for invalid in ["line\nsecret","line\rsecret","nul\0secret",String(repeating:"a",count:4097)]{do{try PasswordEndpoint.validate(invalid);fatalError("unsupported secret accepted")}catch{}}
  var control=site;control.host="example.invalid\0suffix";do{_ = try PasswordEndpoint(control);fatalError("ambiguous endpoint separator") }catch{}
  let api=FakeKeychainAPI(key),actual=KeychainPasswordVault(operations:api.operations());check(try actual.password(for:key)==nil);check(api.allowed)
  try actual.save("framework-fixture-only",for:key);check(api.allowed && api.data==Data("framework-fixture-only".utf8));check(try actual.password(for:key)=="framework-fixture-only")
  try actual.save("updated-framework-fixture",for:key);check(try actual.password(for:key)=="updated-framework-fixture")
  api.copyError=errSecAuthFailed;do{_ = try actual.password(for:key);fatalError("keychain failure ignored")}catch{};check(api.allowed);api.copyError=errSecSuccess
  api.data=Data([255]);do{_ = try actual.password(for:key);fatalError("malformed credential decoded")}catch{};check(api.allowed)
  api.disableError=errSecInteractionNotAllowed;let calls=api.itemCalls;do{try actual.forget(key);fatalError("failed UI guard ignored")}catch{};check(api.allowed && api.itemCalls==calls);api.disableError=errSecSuccess
  api.restoreFailures=1;try actual.forget(key);check(api.allowed && api.data==nil);try actual.forget(key);check(api.allowed)
  api.allowed=false;_ = try actual.password(for:key);check(!api.allowed);api.allowed=true
  let root=FileManager.default.temporaryDirectory.appendingPathComponent("password-vault-"+UUID().uuidString);try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true);defer{try? FileManager.default.removeItem(at:root)}
  let suite="password-vault-"+UUID().uuidString,defaults=UserDefaults(suiteName:suite)!;defer{defaults.removePersistentDomain(forName:suite)}
  let vault=MemoryPasswordVault(),app=App(defaults:defaults,dataDirectory:root.appendingPathComponent("profile"),initialLocalDirectory:root.path,automaticLogin:false,showsMainWindow:false,frameAutosaveName:nil,vault:vault)
  app.applicationDidFinishLaunching(Notification(name:NSApplication.didFinishLaunchingNotification));check(vault.reads==0 && vault.writes==0 && vault.removals==0)
  let form=ConnectionForm(store:app.siteStore!,selected:site,localPath:root.path,remembered:{app.remembersPassword($0)},onForget:{try app.forgetPassword($0)});check(form.remember.state == .off)
  form.remember.state = .on;let saved=try form.value(localPath:root.path);try app.siteStore!.save(saved);try app.setRemembersPassword(saved,true);check(app.remembersPassword(saved) && vault.writes==0)
  let reopened=ConnectionForm(store:app.siteStore!,selected:saved,localPath:root.path,remembered:{app.remembersPassword($0)});check(reopened.remember.state == .on && reopened.password.stringValue.isEmpty)
  let secret="isolated-test-only";try vault.save(secret,for:key);form.forgetPassword();check(vault.removals==1 && !app.remembersPassword(site) && form.remember.state == .off && vault.values[key]==nil)
  check(!String(decoding:try app.siteStore!.exportData(),as:UTF8.self).contains(secret));check(!String(describing:(defaults.persistentDomain(forName:suite) ?? [:])).contains(secret))
  let cleared=SSHLoginEnvironment.make(base:["MACSCP_AUTH_SOCKET":"stale","MACSCP_AUTH_TOKEN":"stale","MACSCP_AUTH_OWNER_PID":"99"],helper:"helper",executable:"exe");check(cleared["MACSCP_AUTH_SOCKET"]==nil && cleared["MACSCP_AUTH_TOKEN"]==nil && cleared["MACSCP_AUTH_OWNER_PID"]==nil)
  for prompt in ["Enter passphrase for key '/tmp/key':","Verification code:","Password:","other@example.invalid's password:","demo@jump.invalid's password:","Are you sure you want to continue connecting (yes/no)?"]{check(!SSHPasswordBroker.matches(prompt:prompt,hint:nil,user:site.user,host:site.host))}
  check(SSHPasswordBroker.matches(prompt:"demo@example.invalid's password: ",hint:nil,user:site.user,host:site.host));check(!SSHPasswordBroker.matches(prompt:"demo@example.invalid's password:",hint:"confirm",user:site.user,host:site.host));check(!SSHPasswordBroker.matches(prompt:"demo@example.invalid's password:",hint:"none",user:site.user,host:site.host))
  app.window.close();print("PASS: isolated password vault preference off by default, explicit username and endpoint/protocol/port isolation, local-only preference, form restore/forget, no password export/defaults, strict SSH target prompts and stale env removal; real vault adapter with fake system operations restores UI on errors, no real keychain, login or network")
 }
}
