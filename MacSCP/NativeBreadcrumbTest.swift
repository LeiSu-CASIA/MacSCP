import Cocoa
@main struct NativeBreadcrumbTests {static func main(){
let control=NSPathControl(frame:NSRect(x:0,y:0,width:650,height:28));let titles=["/","home","ps","sulei","datarun","DISTIALL"];let items=titles.map{title in let item=NSPathControlItem();item.title=title;return item};control.pathItems=items
precondition(control.pathItems.map{$0.title}==titles)
precondition(zip(control.pathItems,items).allSatisfy{$0 === $1})
print("PASS: native NSPathControl retains all titles and item identities used for ancestor click routing")

}}
