import Cocoa

final class FTPAdvancedOptionsView:NSView {
 let listing=NSPopUpButton(),timeout=NSTextField(),authentication=NSPopUpButton()
 init(){super.init(frame:NSRect(x:0,y:0,width:500,height:138));listing.addItems(withTitles:FTPListingMode.allCases.map{$0.title});authentication.addItems(withTitles:["AUTH TLS 优先","AUTH SSL 优先"])
  for (i,pair) in [("目录列表",listing as NSView),("连接/响应超时（秒）",timeout),("显式 FTPS 认证",authentication)].enumerated(){let y=CGFloat(104-i*36);let label=NSTextField(labelWithString:pair.0);label.alignment = .right;label.frame=NSRect(x:0,y:y+3,width:125,height:22);pair.1.frame=NSRect(x:138,y:y,width:350,height:26);addSubview(label);addSubview(pair.1)};let note=NSTextField(wrappingLabelWithString:"超时会终止本次操作，可手动重试；不会弹出继续等待窗口。");note.font = .systemFont(ofSize:10);note.textColor = .secondaryLabelColor;note.frame=NSRect(x:12,y:0,width:476,height:25);addSubview(note);timeout.placeholderString="1–600";load(FTPSiteOptions())
 }
 required init?(coder:NSCoder){fatalError()}
 func load(_ options:FTPSiteOptions){listing.selectItem(at:FTPListingMode.allCases.firstIndex(of:options.listingMode)!);timeout.stringValue=String(options.connectTimeout);authentication.selectItem(at:options.prefersSSLAuth ? 1 : 0)}
 func value(base:FTPSiteOptions)throws->FTPSiteOptions{guard FTPListingMode.allCases.indices.contains(listing.indexOfSelectedItem),[0,1].contains(authentication.indexOfSelectedItem),let seconds=Int(timeout.stringValue) else{throw SFTPError.message("请选择列表与认证方式，并输入有效的连接超时")};var options=base;let mode=FTPListingMode.allCases[listing.indexOfSelectedItem];options.listing=mode == .automatic ? nil : mode;options.timeout=seconds==15 ? nil : seconds;options.sslAuthFirst=authentication.indexOfSelectedItem==1 ? true : nil;return try options.validated()}
}
