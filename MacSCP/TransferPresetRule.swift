import Foundation

struct TransferPresetContext:Equatable {
 let connection:String,host:String,user:String,local:String,remote:String
}

// This matcher handles names and directory paths, not file size/date constraints.
// Greedy glob matching has bounded storage and does not execute a backtracking regular expression.
struct TransferPresetMask {
 enum Token {case star,any,literal(Unicode.Scalar),set([(UInt32,UInt32)])}
 let included:[[Token]],excluded:[[Token]];let directory:Bool
 init(_ raw:String,directory:Bool=false)throws {
  guard raw.utf8.count<=2048,!raw.unicodeScalars.contains(where:{CharacterSet.controlCharacters.contains($0)}) else{throw SFTPError.message("自动匹配条件过长或包含控制字符")}
  self.directory=directory
  let chars=Array(raw.trimmingCharacters(in:.whitespaces).precomposedStringWithCanonicalMapping.lowercased().unicodeScalars)
  var parts=[[Unicode.Scalar]](),current=[Unicode.Scalar](),negative=false,includes=[[Token]](),excludes=[[Token]](),i=0
  func consume()throws{if !current.isEmpty{parts.append(current);current=[]};guard parts.count<=32 else{throw SFTPError.message("每个匹配条件最多 32 个掩码")};for part in parts{let text=String(String.UnicodeScalarView(part)).trimmingCharacters(in:.whitespaces);if !text.isEmpty{let token=try Self.tokens(text);if negative{excludes.append(token)}else{includes.append(token)}}};parts=[]}
  while i<chars.count {
   let c=chars[i]
   if c==";" || c=="," || c=="|" {
    if i+1<chars.count,chars[i+1]==c{current.append(c);i+=2;continue}
    if c=="|"{guard !negative else{throw SFTPError.message("自动匹配条件只能有一个排除分隔符 |")};try consume();negative=true}
    else{parts.append(current);current=[]}
   }else{current.append(c)}
   i+=1
  }
  try consume();included=includes;excluded=excludes
 }
 private static func tokens(_ string:String)throws->[Token]{
  let chars=Array(string.unicodeScalars);var result=[Token](),i=0
  while i<chars.count {
   let c=chars[i]
   if c=="*"{if case .star?=result.last{}else{result.append(.star)}}
   else if c=="?"{result.append(.any)}
   else if c=="[" {
    var members=[Unicode.Scalar]();i+=1
    while i<chars.count,chars[i] != "]"{members.append(chars[i]);i+=1}
    guard i<chars.count,!members.isEmpty else{throw SFTPError.message("自动匹配条件中的字符组 [] 未闭合或为空")}
    var ranges=[(UInt32,UInt32)](),j=0
    while j<members.count {
     if j+2<members.count,members[j+1]=="-"{guard members[j].value<=members[j+2].value else{throw SFTPError.message("自动匹配字符范围顺序错误")};ranges.append((members[j].value,members[j+2].value));j+=3}
     else{ranges.append((members[j].value,members[j].value));j+=1}
    }
    result.append(.set(ranges))
   }else{result.append(.literal(c))};i+=1
  };return result
 }
 private func match(_ tokens:[Token],_ chars:[Unicode.Scalar])->Bool{
  var p=0,v=0,star:Int?,retry=0
  while v<chars.count {
   if p<tokens.count {
    switch tokens[p] {
    case .star:star=p;p+=1;retry=v;continue
    case .any:p+=1;v+=1;continue
    case .literal(let c):if c==chars[v]{p+=1;v+=1;continue}
    case .set(let ranges):if ranges.contains(where:{$0.0<=chars[v].value && chars[v].value<=$0.1}){p+=1;v+=1;continue}
    }
   }
   guard let last=star else{return false};retry+=1;v=retry;p=last+1
  }
  while p<tokens.count{if case .star=tokens[p]{p+=1}else{return false}};return true
 }
 func matches(_ value:String)->Bool{
  guard value.utf8.count<=16384 else{return false}
  let text=value.precomposedStringWithCanonicalMapping.lowercased(),chars=Array(text.unicodeScalars)
  func accepts(_ pattern:[Token])->Bool{
   if match(pattern,chars){return true}
   // A directory mask ending in / includes descendants of the matched directory.
   guard directory,case .literal("/")?=pattern.last else{return false}
   let base=Array(pattern.dropLast());if match(base,chars){return true}
   for index in chars.indices where chars[index]=="/"{if match(base,Array(chars[..<index])){return true}}
   return false
  }
  return (included.isEmpty || included.contains(where:accepts)) && !excluded.contains(where:accepts)
 }
 static func literal(_ value:String)->String{var result="";for c in value{switch c{case "*","?","["," ":result+="["+String(c)+"]";case ";",",","|":result+=String(repeating:String(c),count:2);default:result.append(c)}};return result}
}

struct TransferPresetRule:Codable,Equatable {
 var enabled=false,host="",user="",local="",remote=""
 func validated()throws->Self{for (text,path) in [(host,false),(user,false),(local,true),(remote,true)]{_ = try TransferPresetMask(text,directory:path)};return self}
 func matches(_ context:TransferPresetContext)throws->Bool{guard enabled else{return false};return try TransferPresetMask(host).matches(context.host) && TransferPresetMask(user).matches(context.user) && TransferPresetMask(local,directory:true).matches(context.local) && TransferPresetMask(remote,directory:true).matches(context.remote)}
}
