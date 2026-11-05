import Foundation
enum TransferPrivateNames {
 static func contains(_ name:String)->Bool{for marker in [".macscp-resume-",".macscp-backup-",".macscp-download-",".macscp-promise-",".macscp-"]{if let range=name.range(of:marker,options:.backwards),UUID(uuidString:String(name[range.upperBound...])) != nil{return true}};return false}
}
enum TransferMode:String,Codable,CaseIterable{case binary,text,automatic}
enum TextLineEnding:String,Codable,CaseIterable{case lf,crlf}
struct TextTransferOptions:Codable,Equatable {
 var mode:TransferMode = .binary
 var mask="*.txt;*.csv;*.tsv;*.md;*.html;*.htm;*.css;*.js;*.json;*.xml;*.ini;*.yaml;*.yml;*.py;*.sh;*.c;*.h;*.cpp;*.swift"
 var remote:TextLineEnding = .lf,local:TextLineEnding = .lf
 var removeBOM=false,removeEOF=false
 func validated()throws->Self{guard mask.utf8.count<=8192 else{throw SFTPError.message("文本文件掩码过长")};_ = try TransferPolicy(include:mask).validated();return self}
 func applies(_ path:String)throws->Bool{switch mode{case .binary:return false;case .text:return true;case .automatic:guard !mask.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else{return false};return try TransferPolicy(include:mask).allows(relative:(path as NSString).lastPathComponent,name:(path as NSString).lastPathComponent,directory:false)}}
}
struct TransferPolicy:Codable,Equatable {
 var include="";var exclude="";var verifyChecksum=false;var text:TextTransferOptions?=nil
 func validated()throws->TransferPolicy{guard include.count<=8192,exclude.count<=8192,!include.contains("\0"),!exclude.contains("\0") else{throw SFTPError.message("传输掩码过长或含无效字符")};_ = try rules(include);_ = try rules(exclude);_ = try text?.validated();return self}
 private func rules(_ text:String)throws->[(NSRegularExpression,Bool,Bool)]{try text.split(separator:";").filter{!$0.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty}.map{part in let raw=part.trimmingCharacters(in:.whitespacesAndNewlines);let directory=raw.hasSuffix("/");let value=directory ? String(raw.dropLast()) : raw;guard !value.isEmpty,!value.hasPrefix("/"),!value.split(separator:"/").contains("..") else{throw SFTPError.message("掩码应为名称或相对路径，不使用绝对路径和 ..")};let full=value.contains("/");var expression="^";var index=value.startIndex;while index<value.endIndex{let c=value[index];if c=="*"{let next=value.index(after:index);if next<value.endIndex,value[next]=="*"{let after=value.index(after:next);if after<value.endIndex,value[after]=="/"{expression+="(?:.*/)?";index=value.index(after:after)}else{expression+=".*";index=after};continue};expression+="[^/]*"}else if c=="?"{expression+="[^/]"}else{expression+=NSRegularExpression.escapedPattern(for:String(c))};index=value.index(after:index)};expression+="$";return(try NSRegularExpression(pattern:expression,options:[.caseInsensitive]),directory,full)}}
 func predicate()throws->(String,String,Bool)->Bool{let excludes=try rules(exclude),includes=try rules(include);return{relative,name,directory in func match(_ rule:(NSRegularExpression,Bool,Bool))->Bool{if rule.1 && !directory{return false};let value=rule.2 ? relative : name;return rule.0.firstMatch(in:value,range:NSRange(value.startIndex...,in:value)) != nil};if excludes.contains(where:match){return false};return directory || includes.isEmpty || includes.contains(where:match)}}
 func allows(relative:String,name:String,directory:Bool)throws->Bool{try predicate()(relative,name,directory)}
}
