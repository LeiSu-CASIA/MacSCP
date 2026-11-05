import Cocoa

struct TransferConflictResponse {
 enum Action{case skip,replace,cancelRemaining}
 let action:Action
 var applyToRemainingConflicts=false
}

// One user gesture owns one decision scope. Never persist blanket permission.
final class TransferApprovalBatch {
 private var remaining=[Bool:TransferConflictResponse.Action]()
 private(set) var cancelled=false
 func approve(_ job:TransferJob,exists:Bool,prompt:()->TransferConflictResponse)->Bool {
  guard !cancelled else{return false}
  guard exists else{return true}
  let response=remaining[job.directory].map{TransferConflictResponse(action:$0)} ?? prompt()
  if response.action == .cancelRemaining{cancelled=true;return false}
  if response.applyToRemainingConflicts{remaining[job.directory]=response.action}
  guard response.action == .replace else{return false}
  job.overwrite=true;return true
 }
}

final class TransferConflictDialog {
 let alert=NSAlert()
 let applyAll=NSButton(checkboxWithTitle:"对本次操作中其余同名目标使用相同选择",target:nil,action:nil)
 init(_ job:TransferJob){
  applyAll.title=job.directory ? "对本次操作中其余同名目录使用相同选择" : "对本次操作中其余同名文件使用相同选择"
  alert.alertStyle = .warning;alert.messageText="目标已存在：\((job.destination as NSString).lastPathComponent)"
  alert.informativeText=(job.directory ? "替换 / 合并会递归替换目录内的同名文件，保留目标中独有的文件。" : "替换会在文件完整传输后发布，传输失败前保留原目标。")+"\n取消剩余任务不会停止此前已加入队列的任务。"
  let form=NSStackView();form.orientation = .vertical;form.alignment = .leading;form.spacing=8
  for (title,value) in [("源",job.displaySource ?? job.source),("目标",job.displayDestination ?? job.destination)]{
   let label=NSTextField(wrappingLabelWithString:title+"："+value);label.font = .systemFont(ofSize:12);label.preferredMaxLayoutWidth=500;label.widthAnchor.constraint(equalToConstant:500).isActive=true;label.setAccessibilityLabel(title+"："+value);form.addArrangedSubview(label)
  }
  form.addArrangedSubview(applyAll);form.frame=NSRect(x:0,y:0,width:500,height:form.fittingSize.height);alert.accessoryView=form
  alert.addButton(withTitle:"跳过");alert.addButton(withTitle:"替换 / 合并");alert.addButton(withTitle:"取消剩余任务")
  alert.buttons[0].keyEquivalent="\r";alert.buttons[1].keyEquivalent="";alert.buttons[2].keyEquivalent="\u{1b}"
 }
 func response(_ result:NSApplication.ModalResponse)->TransferConflictResponse {
  let action:TransferConflictResponse.Action=result == .alertSecondButtonReturn ? .replace : result == .alertFirstButtonReturn ? .skip : .cancelRemaining
  return TransferConflictResponse(action:action,applyToRemainingConflicts:applyAll.state == .on)
 }
 func run()->TransferConflictResponse{response(alert.runModal())}
}
