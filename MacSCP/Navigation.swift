import Foundation
struct DirectoryLocation {
 private(set) var current="";private(set) var draft=""
 mutating func edit(_ path:String){draft=path}
 mutating func commit(_ path:String){current=path;draft=path}
 mutating func cancelEdit(){draft=current}
 func child(_ name:String)->String{(current=="/" ? "/" : current+"/")+name}
}
struct SessionHistory:Equatable {var local=[String]();var remote=[String]();var lastLocal="";var lastRemote="";var localForward=[String]();var remoteForward=[String]()}
enum TabNavigation {static func next(current:Int?,count:Int,backwards:Bool)->Int?{guard count>0 else{return nil};let index=current ?? 0;return (index+(backwards ? count-1 : 1))%count}}
enum ShellPath {
 static func quote(_ path:String)throws->String{guard !path.contains("\0") else{throw SFTPError.message("路径包含无效字符")};return "'"+path.replacingOccurrences(of:"'",with:"'\\''")+"'"}
 static func terminalCommand(directory:String)throws->String{"cd -- "+(try quote(directory))+" && exec \"${SHELL:-/bin/sh}\" -l"}
}

enum RemotePaneConnectionState:Equatable {
 case disconnected,connecting,connected,cancelled,failed(String)
 var available:Bool{self == .connected}
 var title:String{switch self{case .disconnected:return "尚未连接服务器";case .connecting:return "正在连接服务器";case .connected:return "已连接";case .cancelled:return "连接已取消";case .failed:return "服务器连接已断开"}}
 var detail:String{switch self{case .disconnected:return "登录后，在这里浏览和管理服务器文件";case .connecting:return "连接成功后显示服务器文件，可查看当前连接进度。";case .connected:return "";case .cancelled:return "本次认证已停止；需要时可手动重新连接。";case .failed(let message):return message}}
 var buttonTitle:String{switch self{case .disconnected:return "连接服务器…";case .connecting:return "查看连接进度";case .connected:return "";case .cancelled,.failed:return "重新连接…"}}
 var command:String{switch self{case .disconnected:return "connect";case .connecting:return "connectionProgress";case .connected:return "";case .cancelled,.failed:return "reconnect"}}
 var symbol:String{switch self{case .connected:return "● ";case .connecting:return "◌ ";case .disconnected:return "○ ";case .cancelled,.failed:return "⚠ "}}
}

struct DirectoryHistory:Equatable {
 enum Direction{case back,forward}
 struct Request {let revision:UUID;let direction:Direction;let steps:Int;let target:String}
 var back=[String](),forward=[String](),current="",revision=UUID()
 init(back:[String]=[],forward:[String]=[],current:String=""){self.back=Array(back.suffix(200));self.forward=Array(forward.suffix(200));self.current=current}
 func request(_ direction:Direction,steps:Int=1)->Request?{let stack=direction == .back ? back : forward;guard steps>0,steps<=stack.count else{return nil};return Request(revision:revision,direction:direction,steps:steps,target:stack[stack.count-steps])}
 func accepts(_ request:Request)->Bool{guard revision==request.revision,let expected=self.request(request.direction,steps:request.steps) else{return false};return expected.target==request.target}
 mutating func visit(_ path:String){guard path != current else{return};if !current.isEmpty{back.append(current);back=Array(back.suffix(200))};current=path;forward=[];revision=UUID()}
 @discardableResult mutating func commit(_ path:String,request:Request)->Bool{
  guard accepts(request) else{return false}
  if request.direction == .back{if !current.isEmpty{forward.append(current)};forward.append(contentsOf:back.suffix(request.steps-1).reversed());back.removeLast(request.steps)}
  else{if !current.isEmpty{back.append(current)};back.append(contentsOf:forward.suffix(request.steps-1).reversed());forward.removeLast(request.steps)}
  back=Array(back.suffix(200));forward=Array(forward.suffix(200));current=path;revision=UUID();return true
 }
}
struct HistoryMenuJump {let local:Bool;let socket:String;let request:DirectoryHistory.Request}
