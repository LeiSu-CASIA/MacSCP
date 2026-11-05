import Foundation
import CryptoKit
import Security

struct PasswordEndpoint:Hashable {
 let account:String,label:String
 init(_ site:Session)throws{
  let site=try site.validated();guard !site.user.isEmpty,site.user.utf8.count<=1024,site.host.utf8.count<=1024,![site.user,site.host].contains(where:{$0.unicodeScalars.contains(where:{CharacterSet.controlCharacters.contains($0)})}) else{throw SFTPError.message("保存密码需要有效主机和明确的服务器用户名")}
  var host=site.host.lowercased();if host.hasPrefix("["),host.hasSuffix("]"){host=String(host.dropFirst().dropLast())}
  let value=[site.fileProtocol.rawValue,host,String(site.port),site.user].joined(separator:"\0")
  account=SHA256.hash(data:Data(value.utf8)).map{String(format:"%02x",$0)}.joined();label="MacSCP · "+site.fileProtocol.title+" · "+site.user+"@"+site.host+":"+String(site.port)
 }
 static func ==(a:PasswordEndpoint,b:PasswordEndpoint)->Bool{a.account==b.account}
 func hash(into hasher:inout Hasher){hasher.combine(account)}
 static func validate(_ password:String)throws{guard password.utf8.count<=4096,!password.unicodeScalars.contains(where:{[0,10,13].contains($0.value)}) else{throw SFTPError.message("服务器密码过长或包含不支持的换行/空字符")}}
}
protocol PasswordVault:AnyObject {
 func password(for endpoint:PasswordEndpoint)throws->String?
 func save(_ password:String,for endpoint:PasswordEndpoint)throws
 func forget(_ endpoint:PasswordEndpoint)throws
}
struct PasswordVaultError:LocalizedError {
 let status:OSStatus
 var errorDescription:String?{"钥匙串访问未完成（\(status)）。可手动输入密码；不会自动弹出解锁或反复重试。"}
}
struct PasswordKeychainOperations {
 var interaction:()->(OSStatus,Bool)
 var setInteraction:(Bool)->OSStatus
 var copy:([String:Any])->(OSStatus,Data?)
 var update:([String:Any],[String:Any])->OSStatus
 var add:([String:Any])->OSStatus
 var remove:([String:Any])->OSStatus
 static var system:Self{Self(interaction:{var value:DarwinBoolean=false;let status=SecKeychainGetUserInteractionAllowed(&value);return(status,value.boolValue)},setInteraction:{SecKeychainSetUserInteractionAllowed($0)},copy:{query in var result:CFTypeRef?;let status=SecItemCopyMatching(query as CFDictionary,&result);return(status,result as? Data)},update:{SecItemUpdate($0 as CFDictionary,$1 as CFDictionary)},add:{SecItemAdd($0 as CFDictionary,nil)},remove:{SecItemDelete($0 as CFDictionary)})}
}
final class KeychainPasswordVault:PasswordVault {
 private static let lock=NSLock(),service="local.macscp.server-password.v1"
 private let operations:PasswordKeychainOperations
 init(operations:PasswordKeychainOperations = .system){self.operations=operations}
 // The ad-hoc signed preview uses the login keychain. The legacy interaction
 // guard is required for file-based keychains; restore it on every exit path.
 private func withoutInteraction<T>(_ body:()throws->T)throws->T{
  Self.lock.lock();defer{Self.lock.unlock()};let(read,allowed)=operations.interaction();guard read==errSecSuccess else{throw PasswordVaultError(status:read)}
  let disable=operations.setInteraction(false);guard disable==errSecSuccess else{throw PasswordVaultError(status:disable)}
  let result:Result<T,Error>;do{result = .success(try body())}catch{result = .failure(error)}
  var restored=operations.setInteraction(allowed);if restored != errSecSuccess{restored=operations.setInteraction(allowed)};guard restored==errSecSuccess else{throw PasswordVaultError(status:restored)};return try result.get()
 }
 private func query(_ endpoint:PasswordEndpoint)->[String:Any]{[kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:Self.service,kSecAttrAccount as String:endpoint.account]}
 func password(for endpoint:PasswordEndpoint)throws->String?{try withoutInteraction{
  var query=self.query(endpoint);query[kSecReturnData as String]=true;query[kSecMatchLimit as String]=kSecMatchLimitOne
  let(status,data)=operations.copy(query);if status==errSecItemNotFound{return nil};guard status==errSecSuccess,let data=data,let password=String(data:data,encoding:.utf8) else{throw PasswordVaultError(status:status==errSecSuccess ? errSecDecode : status)};try PasswordEndpoint.validate(password);return password
 }}
 func save(_ password:String,for endpoint:PasswordEndpoint)throws{try PasswordEndpoint.validate(password);try withoutInteraction{
  let value=[kSecValueData as String:Data(password.utf8),kSecAttrLabel as String:endpoint.label] as [String:Any]
  let status=operations.update(query(endpoint),value)
  if status==errSecItemNotFound{var item=query(endpoint);for(key,value) in value{item[key]=value};let added=operations.add(item);guard added==errSecSuccess else{throw PasswordVaultError(status:added)}}else if status != errSecSuccess{throw PasswordVaultError(status:status)}
 }}
 func forget(_ endpoint:PasswordEndpoint)throws{try withoutInteraction{let status=operations.remove(query(endpoint));guard status==errSecSuccess || status==errSecItemNotFound else{throw PasswordVaultError(status:status)}}}
}
