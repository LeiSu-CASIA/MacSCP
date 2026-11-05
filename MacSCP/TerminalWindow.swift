import Cocoa
final class RemoteTerminalController:NSWindowController,NSWindowDelegate {
 let pane:TerminalPane;var onClosed:(()->Void)?
 init(session:Session,socket:String,directory:String)throws{let args=try SSHArguments.terminal(session,socket:socket,directory:directory);pane=TerminalPane(path:"/usr/bin/ssh",args:args);let window=NSWindow(contentRect:NSRect(x:0,y:0,width:900,height:550),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false);window.isReleasedWhenClosed=false;super.init(window:window);window.title=session.name+" · SSH 终端";window.contentView=pane;window.delegate=self;window.center()}
 required init?(coder:NSCoder){fatalError()}
 func windowWillClose(_ notification:Notification){pane.stop();onClosed?()}
}
