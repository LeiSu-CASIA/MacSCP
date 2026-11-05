import Foundation
@main struct BreadcrumbTests{
 static func main(){let path="/home/ps/sulei/datarun/DISTIALL";let s=BreadcrumbPath.segments(path);precondition(s.map{$0.title}==["/","home","ps","sulei","datarun","DISTIALL"]);precondition(s[4].path=="/home/ps/sulei/datarun");precondition(s[1].path=="/home");precondition(BreadcrumbPath.segments("/")==[BreadcrumbSegment(title:"/",path:"/")]);let special=BreadcrumbPath.segments("/中文 目录/a%20b/带#号");precondition(special[2].path=="/中文 目录/a%20b");precondition(BreadcrumbPath.segments("").isEmpty);precondition(BreadcrumbPath.segments("/a//b/").last?.path=="/a/b");print("PASS: ancestor navigation targets, root, Unicode, spaces, percent/hash characters, empty/trailing paths")}
}
