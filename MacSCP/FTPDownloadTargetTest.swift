import Foundation
@main struct FTPDownloadTargetTests {
 static func check(_ v:Bool,line:UInt=#line){precondition(v,"assertion at \(line)")}
 static func main()throws{
  let fm=FileManager.default,root=fm.temporaryDirectory.appendingPathComponent("ftp-target-"+UUID().uuidString);try fm.createDirectory(at:root,withIntermediateDirectories:true);defer{try? fm.removeItem(at:root)}
  func state(_ name:String)->TransferResume{TransferResume(source:"/fixture",destination:root.appendingPathComponent(name).path,upload:false)}
  let destination=root.appendingPathComponent("new.bin"),first=state("new.bin")
  var target:FTPDownloadTarget?=try FTPDownloadTarget(destination:destination,temporary:URL(fileURLWithPath:first.temporaryPath),overwrite:false,resume:false,retainPartial:false)
  try target!.file.write(contentsOf:Data("new".utf8));try target!.publish(expectedSize:3,modified:1700000000);target=nil
  check(try Data(contentsOf:destination)==Data("new".utf8));let attrs=try fm.attributesOfItem(atPath:destination.path);check((attrs[.posixPermissions] as? NSNumber)?.intValue==0o600)
  let blocked=state("new.bin");do{_ = try FTPDownloadTarget(destination:destination,temporary:URL(fileURLWithPath:blocked.temporaryPath),overwrite:false,resume:true,retainPartial:true);fatalError("overwrite guard ignored")}catch{}
  let concurrent=state("new.bin");target=try FTPDownloadTarget(destination:destination,temporary:URL(fileURLWithPath:concurrent.temporaryPath),overwrite:true,resume:true,retainPartial:false);try target!.file.write(contentsOf:Data("next".utf8));try Data("concurrent".utf8).write(to:destination)
  do{try target!.publish(expectedSize:4,modified:1700000000);fatalError("concurrent target replaced")}catch{};target=nil;check(try Data(contentsOf:destination)==Data("concurrent".utf8));check(!fm.fileExists(atPath:concurrent.temporaryPath))
  let outside=root.appendingPathComponent("outside");try Data("safe".utf8).write(to:outside)
  let symlink=state("link-target");try fm.createSymbolicLink(atPath:symlink.temporaryPath,withDestinationPath:outside.path)
  do{_ = try FTPDownloadTarget(destination:root.appendingPathComponent("link-target"),temporary:URL(fileURLWithPath:symlink.temporaryPath),overwrite:false,resume:true,retainPartial:true);fatalError("symlink stage accepted")}catch{}
  let hardlink=state("hard-target");try fm.linkItem(at:outside,to:URL(fileURLWithPath:hardlink.temporaryPath));try fm.setAttributes([.posixPermissions:0o600],ofItemAtPath:outside.path)
  do{_ = try FTPDownloadTarget(destination:root.appendingPathComponent("hard-target"),temporary:URL(fileURLWithPath:hardlink.temporaryPath),overwrite:false,resume:true,retainPartial:true);fatalError("hardlink stage accepted")}catch{};check(try Data(contentsOf:outside)==Data("safe".utf8))
  let swapped=state("swapped-target"),held=root.appendingPathComponent("held-stage")
  target=try FTPDownloadTarget(destination:root.appendingPathComponent("swapped-target"),temporary:URL(fileURLWithPath:swapped.temporaryPath),overwrite:false,resume:false,retainPartial:false);try target!.file.write(contentsOf:Data("original-stage".utf8));try fm.moveItem(at:URL(fileURLWithPath:swapped.temporaryPath),to:held);try Data("foreign replacement".utf8).write(to:URL(fileURLWithPath:swapped.temporaryPath))
  do{try target!.publish(expectedSize:14,modified:1700000000);fatalError("replaced stage published")}catch{};target=nil;check(try Data(contentsOf:URL(fileURLWithPath:swapped.temporaryPath))==Data("foreign replacement".utf8))
  let folder=root.appendingPathComponent("folder"),moved=root.appendingPathComponent("moved");try fm.createDirectory(at:folder,withIntermediateDirectories:false)
  let final=folder.appendingPathComponent("result"),resume=TransferResume(source:"/fixture",destination:final.path,upload:false)
  target=try FTPDownloadTarget(destination:final,temporary:URL(fileURLWithPath:resume.temporaryPath),overwrite:false,resume:false,retainPartial:false);try target!.file.write(contentsOf:Data("data".utf8));try fm.moveItem(at:folder,to:moved);try fm.createDirectory(at:folder,withIntermediateDirectories:false)
  do{try target!.publish(expectedSize:4,modified:1700000000);fatalError("changed directory accepted")}catch{};target=nil;check(!fm.fileExists(atPath:folder.appendingPathComponent("result").path) && !fm.fileExists(atPath:moved.appendingPathComponent(URL(fileURLWithPath:resume.temporaryPath).lastPathComponent).path))
  print("PASS: descriptor-based FTP download publication, exclusive new target, explicit overwrite check, concurrent target preservation, owned-stage cleanup, symlink/hardlink rejection and replaced-parent refusal; fixture only")
 }
}
