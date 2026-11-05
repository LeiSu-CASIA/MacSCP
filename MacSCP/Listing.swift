import Foundation
struct Entry {var name:String;var size:UInt64;var dir:Bool;var date:String="—";var permissions:String="—";var modified:TimeInterval=0;var symbolicLink=false;var linkTarget:String?=nil;var linkUnavailable=false}
enum FileListing {
 static func visible(_ source:[Entry],filter:String,showHidden:Bool,key:String,ascending:Bool)->[Entry]{source.filter{e in (e.name==".." || showHidden || !e.name.hasPrefix(".")) && (e.name==".." || filter.isEmpty || e.name.localizedCaseInsensitiveContains(filter))}.sorted{a,b in if a.name==".." || b.name==".."{return a.name==".." && b.name != ".."};if a.dir != b.dir{return a.dir};let comparison:ComparisonResult;switch key{case "size":comparison=a.size==b.size ? .orderedSame : a.size<b.size ? .orderedAscending : .orderedDescending;case "date":comparison=a.modified==b.modified ? .orderedSame : a.modified<b.modified ? .orderedAscending : .orderedDescending;case "extension":comparison=(a.name as NSString).pathExtension.localizedStandardCompare((b.name as NSString).pathExtension);case "permissions":let av=UInt32(a.permissions,radix:8) ?? 0,bv=UInt32(b.permissions,radix:8) ?? 0;comparison=av==bv ? .orderedSame : av<bv ? .orderedAscending : .orderedDescending;default:comparison=a.name.localizedStandardCompare(b.name)};if comparison == .orderedSame{return a.name.localizedStandardCompare(b.name) == .orderedAscending};return ascending ? comparison == .orderedAscending : comparison == .orderedDescending}}
}
struct TransferPreferences:Codable,Equatable {
 var concurrency=3;var kibibytesPerSecond=0;var policy:TransferPolicy?=nil
 var filePolicy:TransferPolicy{policy ?? TransferPolicy()}
 func validated()throws->TransferPreferences{guard (1...8).contains(concurrency),(0...1048576).contains(kibibytesPerSecond) else{throw SFTPError.message("并行数应为 1–8；限速应为 0–1048576 KiB/s")};_ = try filePolicy.validated();return self}
 var bytesPerSecond:UInt64{UInt64(max(0,kibibytesPerSecond))*1024}
}
enum FileKeyAction {
 static func resolve(code:UInt16,command:Bool,shift:Bool,option:Bool,control:Bool=false)->String?{
  if control{return !command && !option && code==48 ? (shift ? "previousTab" : "nextTab") : nil}
  if command && option{guard !shift else{return nil};return [18:"sortName",19:"sortSize",20:"sortDate",21:"sortExtension",23:"sortPermissions"][code]}
  if option{guard !shift else{return nil};switch code{case 123:return "back";case 124:return "forward";case 126:return "up";case 36:return "properties";case 115:return "home";default:return nil}}
  if command{
   if shift{switch code{case 34:return "invertSelection";case 8:return "copyPath";case 47:return "hidden";default:return nil}}
   switch code{case 33:return "back";case 30:return "forward";case 0:return "selectAllFiles";case 15:return "refresh";case 37:return "pathEdit";case 8:return "copyFiles";case 9:return "pasteFiles";case 3:return "filterFocus";case 42:return "root";case 126:return "up";default:return nil}
  }
  if shift{return code==48 ? "otherPane" : code==117 ? "delete" : nil}
  switch code{case 53:return "cancelTargetProbe";case 96:return "transfer";case 120:return "rename";case 118:return "edit";case 98:return "mkdir";case 100,117:return "delete";case 101:return "properties";case 48:return "otherPane";case 36,76:return "activate";case 51:return "up";default:return nil}
 }
 static let sortKeys=["sortName":"name","sortSize":"size","sortDate":"date","sortExtension":"extension","sortPermissions":"permissions"]
}

enum LocalListing {
 static func entries(_ path:String)throws->[Entry]{let root=URL(fileURLWithPath:path);return try FileManager.default.contentsOfDirectory(at:root,includingPropertiesForKeys:nil).map{url in let attrs=try FileManager.default.attributesOfItem(atPath:url.path);let link=attrs[.type] as? FileAttributeType == .typeSymbolicLink;let target=link ? try? FileManager.default.destinationOfSymbolicLink(atPath:url.path) : nil;let resolved=link ? try? FileManager.default.attributesOfItem(atPath:url.resolvingSymlinksInPath().path) : attrs;let directory=resolved?[.type] as? FileAttributeType == .typeDirectory;let unavailable=link && (resolved==nil || resolved?[.type] as? FileAttributeType == .typeSymbolicLink);let date=attrs[.modificationDate] as? Date;return Entry(name:url.lastPathComponent,size:(attrs[.size] as? NSNumber)?.uint64Value ?? 0,dir:directory,date:date?.formatted(date:.numeric,time:.shortened) ?? "—",permissions:String((attrs[.posixPermissions] as? NSNumber)?.uint32Value ?? 0,radix:8),modified:date?.timeIntervalSince1970 ?? 0,symbolicLink:link,linkTarget:target,linkUnavailable:unavailable)}}
}
