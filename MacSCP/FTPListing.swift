import Foundation

struct FTPDirectoryEntry {
 let file:RemoteFile,sizeKnown:Bool,modifiedKnown:Bool,permissionsKnown:Bool
 var name:String{file.name};var size:UInt64{file.size};var mode:UInt32{file.mode};var modified:UInt32{file.modified};var directory:Bool{file.directory};var symbolicLink:Bool{file.symbolicLink};var linkTarget:String?{file.linkTarget}
}
enum FTPListing {
 private static func name(_ value:String)throws->String{guard !value.isEmpty,!value.contains("/"),!value.unicodeScalars.contains(where:{[0,10,13].contains($0.value)}) else{throw SFTPError.message("FTP 返回不安全的项目名称")};return value}
 private static func number(_ value:String)throws->UInt64{guard !value.isEmpty,value.utf8.allSatisfy({(48...57).contains($0)}),let number=UInt64(value) else{throw SFTPError.message("FTP 文件大小无效")};return number}
 private static func date(year:Int,month:Int,day:Int,hour:Int,minute:Int,second:Int,timeZone:TimeZone)throws->Date{
  guard year>=1,year<=9999,(1...12).contains(month),(1...31).contains(day),(0...23).contains(hour),(0...59).contains(minute),(0...60).contains(second) else{throw SFTPError.message("FTP 时间字段无效")}
  var calendar=Calendar(identifier:.gregorian);calendar.timeZone=timeZone
  let c=DateComponents(timeZone:timeZone,year:year,month:month,day:day,hour:hour,minute:minute,second:min(59,second))
  guard let value=calendar.date(from:c) else{throw SFTPError.message("FTP 日期无效")};let round=calendar.dateComponents([.year,.month,.day,.hour,.minute,.second],from:value)
  guard round.year==year,round.month==month,round.day==day,round.hour==hour,round.minute==minute,round.second==min(59,second) else{throw SFTPError.message("FTP 日期无效")};return second==60 ? value.addingTimeInterval(1) : value
 }
 private static func timestamp(_ text:String)throws->UInt32{
  let parts=text.split(separator:".",omittingEmptySubsequences:false);guard (1...2).contains(parts.count),parts[0].count==14,parts.allSatisfy({!$0.isEmpty && $0.utf8.allSatisfy{(48...57).contains($0)}}) else{throw SFTPError.message("FTP modify 时间格式无效")}
  let bytes=Array(parts[0]);func n(_ a:Int,_ b:Int)->Int{Int(String(bytes[a..<b]))!}
  let value=try date(year:n(0,4),month:n(4,6),day:n(6,8),hour:n(8,10),minute:n(10,12),second:n(12,14),timeZone:TimeZone(secondsFromGMT:0)!)
  return UInt32(clamping:Int64(value.timeIntervalSince1970))
 }
 private static func lines(_ data:Data,maximumEntries:Int)throws->[String]{guard maximumEntries>0,data.count<=16*1024*1024,let text=String(data:data,encoding:.utf8) else{throw SFTPError.message("FTP 列表超过上限或不是 UTF-8 编码")};let lines=try text.components(separatedBy:"\n").map{row->String in let row=row.hasSuffix("\r") ? String(row.dropLast()) : row;guard !row.unicodeScalars.contains(where:{[0,13].contains($0.value)}) else{throw SFTPError.message("FTP 列表含无效控制字符")};return row}.filter{!$0.isEmpty};guard lines.count<=maximumEntries+2 else{throw SFTPError.message("FTP 列表条目超过上限")};return lines}
 static func mlsd(_ data:Data,maximumEntries:Int=100000)throws->[FTPDirectoryEntry]{
  var output=[FTPDirectoryEntry](),seen=Set<String>()
  for line in try lines(data,maximumEntries:maximumEntries){
   guard let split=line.firstIndex(of:" ") else{throw SFTPError.message("FTP MLSD 行缺少名称")};let factsText=line[..<split],rawName=String(line[line.index(after:split)...]);guard factsText.hasSuffix(";") else{throw SFTPError.message("FTP MLSD facts 格式无效")}
   var facts=[String:String]();for field in factsText.split(separator:";"){guard let equal=field.firstIndex(of:"=") else{throw SFTPError.message("FTP MLSD fact 无效")};let key=field[..<equal].lowercased(),value=String(field[field.index(after:equal)...]);guard !key.isEmpty,facts[key]==nil else{throw SFTPError.message("FTP MLSD 重复或空 fact")};facts[key]=value}
   guard let rawType=facts["type"] else{throw SFTPError.message("FTP MLSD 缺少 type")};let type=rawType.lowercased();if type=="cdir" || type=="pdir"{continue};let filename=try name(rawName);guard filename != ".",filename != "..",seen.insert(filename).inserted else{throw SFTPError.message("FTP 列表名称重复或无效")}
   let link=type.hasPrefix("os.unix=slink"),modeType:UInt32=type=="file" ? 0o100000 : type=="dir" ? 0o040000 : link ? 0o120000 : 0
   var permissions:UInt32=0;if let raw=facts["unix.mode"]{guard !raw.isEmpty,raw.count<=7,raw.allSatisfy({("0"..."7").contains(String($0))}),let mode=UInt32(raw,radix:8) else{throw SFTPError.message("FTP UNIX.mode 无效")};permissions=mode&0o7777}
   let size=try facts["size"].map(number) ?? 0,modified=try facts["modify"].map(timestamp) ?? 0
   let target=link && rawType.contains(":") ? String(rawType[rawType.index(after:rawType.firstIndex(of:":")!)...]) : nil
   output.append(FTPDirectoryEntry(file:RemoteFile(name:filename,size:size,directory:type=="dir",modified:modified,mode:modeType|permissions,linkTarget:target,permissionsKnown:facts["unix.mode"] != nil),sizeKnown:facts["size"] != nil,modifiedKnown:facts["modify"] != nil,permissionsKnown:facts["unix.mode"] != nil));guard output.count<=maximumEntries else{throw SFTPError.message("FTP 列表条目超过上限")}
  };return output
 }
 private static let unix=try! NSRegularExpression(pattern:"^([bcdlps-][r-][w-][xSs-][r-][w-][xSs-][r-][w-][xTt-][+@.]?)\\s+\\d+\\s+\\S+\\s+\\S+\\s+(\\d+)\\s+([A-Za-z]{3})\\s+(\\d{1,2})\\s+(\\d{2}:\\d{2}|\\d{4}) (.+)$")
 private static let dos=try! NSRegularExpression(pattern:"^(\\d{2})-(\\d{2})-(\\d{2}|\\d{4})\\s+(\\d{1,2}):(\\d{2})(AM|PM)\\s+(<DIR>|\\d+)\\s+(.+)$",options:.caseInsensitive)
 static func list(_ data:Data,maximumEntries:Int=100000,now:Date=Date(),timeZone:TimeZone=TimeZone(secondsFromGMT:0)!)throws->[FTPDirectoryEntry]{
  var output=[FTPDirectoryEntry](),seen=Set<String>(),calendar=Calendar(identifier:.gregorian);calendar.timeZone=timeZone
  for line in try lines(data,maximumEntries:maximumEntries){
   if line.range(of:"^total [0-9]+$",options:.regularExpression) != nil{continue}
   let range=NSRange(line.startIndex...,in:line);let file:RemoteFile
   if let m=unix.firstMatch(in:line,range:range){
    func s(_ n:Int)->String{String(line[Range(m.range(at:n),in:line)!])}
    let permissions=Array(s(1)),type=permissions[0],size=try number(s(2));let months=["jan","feb","mar","apr","may","jun","jul","aug","sep","oct","nov","dec"]
    guard let month=months.firstIndex(of:s(3).lowercased()),let day=Int(s(4)) else{throw SFTPError.message("FTP LIST 日期无效")}
    let clock=s(5).split(separator:":"),hasTime=clock.count==2,year=hasTime ? calendar.component(.year,from:now) : Int(s(5))!
    var value=try date(year:year,month:month+1,day:day,hour:hasTime ? Int(clock[0])! : 0,minute:hasTime ? Int(clock[1])! : 0,second:0,timeZone:timeZone)
    if hasTime,value>now.addingTimeInterval(2*86400){value=try date(year:year-1,month:month+1,day:day,hour:Int(clock[0])!,minute:Int(clock[1])!,second:0,timeZone:timeZone)}
    var mode:UInt32=type=="d" ? 0o040000 : type=="l" ? 0o120000 : type=="-" ? 0o100000 : 0
    for i in 0..<9{let c=permissions[i+1],bit=UInt32(1) << UInt32(8-i);if "rwxst".contains(c){mode|=bit}}
    if permissions[3]=="s" || permissions[3]=="S"{mode|=0o4000};if permissions[6]=="s" || permissions[6]=="S"{mode|=0o2000};if permissions[9]=="t" || permissions[9]=="T"{mode|=0o1000}
    var filename=s(6),target:String?
    if type=="l"{let parts=filename.components(separatedBy:" -> ");guard parts.count==2,!parts[1].isEmpty else{throw SFTPError.message("FTP LIST 链接名称不明确")};filename=parts[0];target=parts[1]}
    file=RemoteFile(name:try name(filename),size:size,directory:type=="d",modified:UInt32(clamping:Int64(value.timeIntervalSince1970)),mode:mode,linkTarget:target)
   }else if let m=dos.firstMatch(in:line,range:range){
    func s(_ n:Int)->String{String(line[Range(m.range(at:n),in:line)!])};var year=Int(s(3))!;if year<100{year+=year>=70 ? 1900 : 2000};let hour=Int(s(4))!;guard (1...12).contains(hour) else{throw SFTPError.message("FTP LIST 小时无效")}
    let value=try date(year:year,month:Int(s(1))!,day:Int(s(2))!,hour:hour%12+(s(6).uppercased()=="PM" ? 12 : 0),minute:Int(s(5))!,second:0,timeZone:timeZone),directory=s(7).uppercased()=="<DIR>"
    file=RemoteFile(name:try name(s(8)),size:directory ? 0 : try number(s(7)),directory:directory,modified:UInt32(clamping:Int64(value.timeIntervalSince1970)),mode:directory ? 0o040000 : 0o100000,permissionsKnown:false)
   }else{throw SFTPError.message("无法识别 FTP LIST 行；请使用支持 MLSD 的服务器或检查列表格式")}
   if file.name=="." || file.name==".."{continue};guard seen.insert(file.name).inserted,output.count<maximumEntries else{throw SFTPError.message("FTP 列表重复或超过上限")};output.append(FTPDirectoryEntry(file:file,sizeKnown:!file.directory || unix.firstMatch(in:line,range:range) != nil,modifiedKnown:true,permissionsKnown:unix.firstMatch(in:line,range:range) != nil))
  };return output
 }
}

final class FTPDirectoryReader {
 let transport:FTPCurlTransport;private var home:String?
 init(transport:FTPCurlTransport){self.transport=transport}
 func canonical(_ value:String)throws->String{
  if value.hasPrefix("/"){return try FTPPath.absolute(value)}
  if home==nil{guard let path=try transport.perform(.entryDirectory).entryDirectory else{throw SFTPError.message("FTP 服务器未返回登录目录")};home=try FTPPath.absolute(path)}
  return try FTPPath.absolute((home=="/" ? "/" : home!+"/")+value)
 }
 func list(_ path:String,maximumEntries:Int=100000)throws->[FTPDirectoryEntry]{
  let path=try canonical(path)
  if transport.connection.options.listingMode == .legacy{return try FTPListing.list(transport.perform(.legacyList(path)).data,maximumEntries:maximumEntries)}
  do{return try FTPListing.mlsd(transport.perform(.machineList(path)).data,maximumEntries:maximumEntries)}
  catch let error as FTPCurlFailure where error.unsupportedListing && transport.connection.options.listingMode == .automatic{return try FTPListing.list(transport.perform(.legacyList(path)).data,maximumEntries:maximumEntries)}
 }
}
