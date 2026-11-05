import Cocoa
import WebKit

@_silgen_name("terminal_spawn") func terminalSpawn(_ path: UnsafePointer<CChar>, _ args: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>, _ pid: UnsafeMutablePointer<Int32>) -> Int32
@_silgen_name("terminal_resize") func terminalResize(_ fd: Int32, _ cols: Int32, _ rows: Int32)
@_silgen_name("terminal_stop") func terminalStop(_ pid: Int32)
@_silgen_name("terminal_wait") func terminalWait(_ pid: Int32) -> Int32

final class TerminalPane: NSView, WKScriptMessageHandler, WKNavigationDelegate {
 var web: WKWebView!; var fd: Int32 = -1; var pid: Int32 = 0; var ready=false; var pending=[Data](); var reader: FileHandle?; var stopped=false;var exitCode:Int32?
 init(path:String,args:[String]) {
  super.init(frame:.zero)
  let config=WKWebViewConfiguration();config.userContentController.add(self,name:"bridge")
  web=WKWebView(frame:bounds,configuration:config);web.autoresizingMask=[.width,.height];web.navigationDelegate=self;addSubview(web)
  let url=Bundle.main.resourceURL!.appendingPathComponent("terminal.html");web.loadFileURL(url,allowingReadAccessTo:url.deletingLastPathComponent())
  var argv=([path]+args).map{strdup($0)};argv.append(nil)
  fd=terminalSpawn(path,&argv,&pid);for p in argv {if let p=p {free(p)}}
  if fd>=0 {
   reader=FileHandle(fileDescriptor:fd,closeOnDealloc:false)
   reader?.readabilityHandler={ [weak self] handle in
    let data=handle.availableData
    if data.isEmpty {handle.readabilityHandler=nil;return}
    DispatchQueue.main.async {self?.output(data)}
   }
   let child=pid
   DispatchQueue.global().async { [weak self] in let code=terminalWait(child);DispatchQueue.main.async {self?.exitCode=code;self?.output(Data("\r\n[会话结束，退出码 \(code)]\r\n".utf8))} }
  } else {pending.append(Data("无法启动终端。\r\n".utf8))}
 }
 required init?(coder:NSCoder){fatalError()}
 func output(_ data:Data){if !ready {pending.append(data);return};web.evaluateJavaScript("receive('\(data.base64EncodedString())')",completionHandler:nil)}
 func send(_ string:String){guard fd>=0 && !stopped else{return};let data=Data(string.utf8);data.withUnsafeBytes { raw in guard let base=raw.baseAddress else{return};var offset=0;while offset<data.count {let n=Darwin.write(fd,base.advanced(by:offset),data.count-offset);if n<=0 {break};offset+=n} }}
 func userContentController(_ userContentController:WKUserContentController,didReceive message:WKScriptMessage){guard let obj=message.body as? [String:Any],let type=obj["type"] as? String else{return};switch type {case "ready":ready=true;for d in pending {output(d)};pending=[];web.evaluateJavaScript("focusTerminal()",completionHandler:nil)
 case "input":if let data=obj["data"] as? String {send(data)}
 case "resize":if let c=obj["cols"] as? Int,let r=obj["rows"] as? Int,fd>=0 {terminalResize(fd,Int32(c),Int32(r))}
 default:break}}
 func webView(_ webView:WKWebView,decidePolicyFor navigationAction:WKNavigationAction,decisionHandler:@escaping(WKNavigationActionPolicy)->Void){decisionHandler(navigationAction.request.url?.isFileURL == true ? .allow : .cancel)}
 func stop(){guard !stopped else{return};stopped=true;reader?.readabilityHandler=nil;terminalStop(pid);if fd>=0 {close(fd);fd = -1};web.configuration.userContentController.removeScriptMessageHandler(forName:"bridge")}
}

