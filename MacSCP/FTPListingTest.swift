import Foundation
@main struct FTPListingTests {
 static func check(_ v:Bool,line:UInt=#line){precondition(v,"assertion at line \(line)")}
 static func main()throws{
  let rows="Type=cdir; .\r\nType=pdir; ..\r\nType=file;Size=123;Modify=20260228123456.789;UNIX.mode=0640; 中文 ' [%] #?.csv\r\nType=dir;Modify=20260101000000; folder\r\nType=OS.unix=slink:/target; link\r\nType=file;Size=0;  leading space\r\n"
  let entries=try FTPListing.mlsd(Data(rows.utf8));check(entries.count==4 && entries[0].name=="中文 ' [%] #?.csv" && entries[0].size==123 && entries[0].mode==0o100640 && entries[1].directory && entries[2].symbolicLink && entries[2].linkTarget=="/target" && entries[3].name==" leading space" && !entries[3].permissionsKnown && !entries[3].modifiedKnown && entries[3].sizeKnown)
  let unix="total 12\n-rw-r----- 1 owner group 12 Nov 05 2026 中文 file.txt\ndrwxr-xr-x+ 2 owner group 4096 Dec 31 23:59 folder\nlrwxrwxrwx 1 owner group 7 Nov 05 2026 link -> /target\n-rwsr-Sr-T 1 owner group 0 Nov 05 2026 setid\n"
  let now=Date(timeIntervalSince1970:1767312000),legacy=try FTPListing.list(Data(unix.utf8),now:now)
  check(legacy.count==4 && legacy[0].mode==0o100640 && legacy[0].name=="中文 file.txt" && legacy[1].directory && legacy[2].symbolicLink && legacy[3].mode&0o7000==0o7000 && legacy[3].mode&0o111==0o100)
  let dos=try FTPListing.list(Data("11-05-26 12:00AM       <DIR>          folder name\r\n11-05-2026 12:30PM 123 file.txt\r\n".utf8));check(dos.count==2 && dos[0].name=="folder name" && dos[0].directory && dos[1].size==123 && !dos[1].directory)
  for row in ["Type=file; ../bad\n","Type=file; /bad\n","Type=file;Size=-1; bad\n","Type=file;Size=18446744073709551616; bad\n","Type=file;Modify=20260231000000; bad\n","Type=file;Type=dir; bad\n","Type=file; bad\nType=file; bad\n"]{do{_ = try FTPListing.mlsd(Data(row.utf8));fatalError("bad MLSD accepted")}catch{}}
  do{_ = try FTPListing.list(Data("garbage listing\n".utf8));fatalError("bad LIST accepted")}catch{}
  do{_ = try FTPListing.mlsd(Data(rows.utf8),maximumEntries:1);fatalError("limit ignored")}catch{}
  do{_ = try FTPListing.mlsd(Data([0xff]));fatalError("invalid UTF8 accepted")}catch{}
  let connection=try FTPConnection(host:"127.0.0.1",user:"fixture",password:"do-not-display ' quote");let url=try connection.url(path:"/folder/a[%] #?;type=a.txt",directory:false)
  check(url.contains("/%2Ffolder/a%5B%25%5D%20%23%3F%3Btype%3Da.txt") && !connection.description.contains("do-not-display") && !connection.debugDescription.contains("do-not-display"))
  let ipv6=try FTPConnection(host:"[::1]",user:"u",password:"p",security:.implicitTLS);check(try ipv6.url(path:"/",directory:true)=="ftps://[::1]:990/%2F/")
  for path in ["relative","/../../x","/x\r\nDELE /keep","/x\0"]{do{_ = try connection.url(path:path,directory:false);fatalError("unsafe FTP path accepted")}catch{}}
  for host in ["bad\nhost","a/b","user@host","bad:host"]{do{_ = try FTPConnection(host:host,user:"u",password:"p");fatalError("bad host accepted")}catch{}}
  do{_ = try FTPConnection(host:"localhost",user:"u",password:"p\r\nQUIT");fatalError("credential injection accepted")}catch{}
  print("PASS: strict MLSD facts/UTC/fractions/Unicode/leading spaces/links, Unix and DOS LIST, permission bits/year inference, malformed/duplicate/oversize/unsafe names rejected, URL encoding/IPv6 and credential redaction; no network")
 }
}
