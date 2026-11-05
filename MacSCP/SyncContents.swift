import Foundation
struct SyncContents {
 enum State {case off,mixed,on}
 let excludePrivateStages:Bool
 let root:String,manifest:[String:SyncNode],children:[String:[String]],leaves:Set<String>
 private(set) var selected:Set<String>
 private var totalCounts=[String:Int](),selectedCounts=[String:Int]()
 init(root:String,snapshot:[String:SyncNode],policy:TransferPolicy,selected:Set<String>?=nil,excludePrivateStages:Bool=false)throws {
  self.excludePrivateStages=excludePrivateStages;try SyncDeletionPlan.checkedRelative(root);_ = try policy.validated()
  guard snapshot[root]?.directory==true else{throw SFTPError.message("只能选择目录内容")}
  let predicate=try policy.predicate(),allows:(String,Bool)->Bool={(!excludePrivateStages || !TransferPrivateNames.contains(($0 as NSString).lastPathComponent)) && predicate($0,($0 as NSString).lastPathComponent,$1)}
  var nodes=[String:SyncNode]()
  for (path,node) in snapshot where path==root || path.hasPrefix(root+"/"){
   try SyncDeletionPlan.checkedRelative(path)
   if SyncComparison.permitted(path,directory:node.directory,allows:allows){nodes[path]=node}
  }
  guard nodes[root] != nil,nodes.count<=100000 else{throw SFTPError.message("目录被传输规则排除或条目数过多")}
  var children=[String:[String]]()
  for path in nodes.keys where path != root{let parent=(path as NSString).deletingLastPathComponent;guard nodes[parent]?.directory==true else{throw SFTPError.message("目录内容缺少有效父目录")};children[parent,default:[]].append(path)}
  for key in Array(children.keys){children[key]!.sort{let a=nodes[$0]!,b=nodes[$1]!;return a.directory != b.directory ? a.directory : $0.localizedStandardCompare($1) == .orderedAscending}}
  self.root=root;manifest=nodes;self.children=children;leaves=Set(nodes.keys.filter{children[$0]?.isEmpty ?? true})
  let chosen=selected ?? leaves;guard chosen.isSubset(of:leaves) else{throw SFTPError.message("目录勾选范围不属于原预览")};self.selected=chosen;recount()
 }
 private mutating func recount(){totalCounts=[:];selectedCounts=[:]
  for path in manifest.keys.sorted(by:>){if leaves.contains(path){totalCounts[path]=1;selectedCounts[path]=selected.contains(path) ? 1 : 0};let parent=(path as NSString).deletingLastPathComponent;if manifest[parent] != nil{totalCounts[parent,default:0]+=totalCounts[path,default:0];selectedCounts[parent,default:0]+=selectedCounts[path,default:0]}}
 }
 func state(_ path:String)->State{let count=selectedCounts[path,default:0];return count==0 ? .off : count==totalCounts[path,default:0] ? .on : .mixed}
 mutating func set(_ path:String,on:Bool){guard manifest[path] != nil else{return};let affected=leaves.filter{$0==path || $0.hasPrefix(path+"/")};if on{selected.formUnion(affected)}else{selected.subtract(affected)};recount()}
 mutating func setAll(_ on:Bool){selected=on ? leaves : [];recount()}
 var requiredPaths:Set<String>{var result=selected;for path in manifest.keys.sorted(by:>) where result.contains(path){let parent=(path as NSString).deletingLastPathComponent;if manifest[parent] != nil{result.insert(parent)}};return result}
 var selectedRoots:[String]{var result=[String](),pending=[root];while let path=pending.popLast(){switch state(path){case .off:continue;case .on:result.append(path);case .mixed:pending.append(contentsOf:(children[path] ?? []).reversed())}};return result}
 var bytes:UInt64{selected.reduce(0){sum,path in let value=manifest[path]!.directory ? 0 : manifest[path]!.size;let (total,overflow)=sum.addingReportingOverflow(value);return overflow ? UInt64.max : total}}
 var summary:String{"\(selected.count) / \(leaves.count) 个文件或空目录 · "+ByteCountFormatter.string(fromByteCount:Int64(clamping:bytes),countStyle:.file)}
 func validated(root:String,snapshot:[String:SyncNode],policy:TransferPolicy)throws->Self{let bound=try Self(root:root,snapshot:snapshot,policy:policy,selected:selected,excludePrivateStages:excludePrivateStages);guard self.root==root,bound.manifest==manifest else{throw SFTPError.message("目录勾选预览已失效，请重新比较")};return bound}
}

struct SyncSnapshotIndex {
 let paths:[String]
 init(_ snapshot:[String:SyncNode]){paths=snapshot.keys.sorted()}
 private func start(_ prefix:String)->Int{var low=0,high=paths.count;while low<high{let middle=(low+high)/2;if paths[middle]<prefix{low=middle+1}else{high=middle}};return low}
 func hasChildren(_ root:String)->Bool{let prefix=root+"/",index=start(prefix);return index<paths.count && paths[index].hasPrefix(prefix)}
 func subtree(_ root:String,values:[String:SyncNode])->[String:SyncNode]{var result=[String:SyncNode]();if let value=values[root]{result[root]=value};let prefix=root+"/";var index=start(prefix);while index<paths.count,paths[index].hasPrefix(prefix){let path=paths[index];result[path]=values[path];index+=1};return result}
}
