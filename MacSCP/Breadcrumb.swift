import Foundation
struct BreadcrumbSegment:Equatable {let title:String;let path:String}
enum BreadcrumbPath {
 static func segments(_ path:String)->[BreadcrumbSegment]{guard !path.isEmpty else{return []};let absolute=path.hasPrefix("/");var result=absolute ? [BreadcrumbSegment(title:"/",path:"/")] : [];var prefix="";for component in path.split(separator:"/",omittingEmptySubsequences:true){let name=String(component);prefix+=(absolute || !prefix.isEmpty ? "/" : "")+name;result.append(BreadcrumbSegment(title:name,path:prefix))};return result}
}
