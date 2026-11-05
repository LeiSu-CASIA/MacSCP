import Foundation
@main struct TextModeTests {
 static func check(_ value:Bool,file:StaticString = #file,line:UInt = #line){precondition(value,file:file,line:line)}
 static func refused(_ action:()throws->Void){do{try action();fatalError("conversion should fail")}catch{}}
 static func main()throws{
  let fm=FileManager.default,root=fm.temporaryDirectory.appendingPathComponent("text-mode-test-"+UUID().uuidString);try fm.createDirectory(at:root,withIntermediateDirectories:false);defer{try? fm.removeItem(at:root)}
  let source=root.appendingPathComponent("source.txt")
  func convert(_ bytes:Data,_ options:TextTransferOptions,_ up:Bool=true)throws->Data{try bytes.write(to:source);return try TextTransfer.withSnapshot(source.path,options:options,upload:up,checkpoint:nil){url,_ in try Data(contentsOf:url)}}
  var options=TextTransferOptions(mode:.text)
  check(try convert(Data("a\r\nb\nc\rd\r".utf8),options)==Data("a\nb\nc\nd\n".utf8))
  options.remote = .crlf;check(try convert(Data("a\r\nb\nc\rd".utf8),options)==Data("a\r\nb\r\nc\r\nd".utf8))
  let split=Data(String(repeating:"x",count:65535).utf8)+Data("\r\n中\r尾".utf8);options.remote = .lf
  check(try convert(split,options)==Data(String(repeating:"x",count:65535).utf8)+Data("\n中\n尾".utf8))
  options.removeBOM=true;options.removeEOF=true
  check(try convert(Data([239,187,191])+Data("a\r\n".utf8)+Data([26,26]),options)==Data("a\n".utf8))
  check(try convert(Data("a\r".utf8)+Data([26])+Data("\nb".utf8)+Data([26]),options)==Data("a\n".utf8)+Data([26])+Data("\nb".utf8))
  check(try convert(Data([239,187,191])+Data("a\r\n".utf8)+Data([26]),options,false)==Data([239,187,191])+Data("a\n".utf8)+Data([26]))
  check(try convert(Data(),options).isEmpty);check(try convert(Data([233,13,10]),options)==Data([233,10]))
  for binary in [Data([255,254,78,45]),Data([0,13,10]),Data("prefix\r\n".utf8)+Data(repeating:1,count:70000)+Data([0])]{refused{_ = try convert(binary,options)};var auto=options;auto.mode = .automatic;check(try convert(binary,auto)==binary)}
  let auto=TextTransferOptions(mode:.automatic);check(try auto.applies("README.TXT") && !auto.applies("archive.zip"));check(try !TextTransferOptions().applies("a.txt"))
  var invalid=auto;invalid.mask="/absolute";refused{_ = try invalid.validated()}
  let policy=TransferPolicy(verifyChecksum:true,text:options),data=try JSONEncoder().encode(policy);check(try JSONDecoder().decode(TransferPolicy.self,from:data)==policy)
  let legacy=try JSONDecoder().decode(TransferPolicy.self,from:Data("{\"include\":\"\",\"exclude\":\"\",\"verifyChecksum\":false}".utf8));check(legacy.text==nil)
  var entered=false;try Data(repeating:65,count:100000).write(to:source);refused{try TextTransfer.withSnapshot(source.path,options:options,upload:true,checkpoint:{throw SFTPError.message("cancel fixture")}){_,_ in entered=true}};check(!entered)
  print("PASS: bounded streaming LF/CRLF/CR conversion across chunk boundaries, empty/Latin-1/Unicode bytes, upload-only BOM and trailing Ctrl-Z handling, forced binary refusal and automatic exact fallback, cancellation, masks, policy persistence and binary legacy default")
 }
}
