import Cocoa
if CommandLine.arguments.dropFirst().first=="--ssh-askpass"{exit(SSHLoginEnvironment.answer(prompt:CommandLine.arguments.dropFirst(2).first ?? "SSH authentication"))}
let app=NSApplication.shared;let delegate=App();app.delegate=delegate;app.setActivationPolicy(.regular);app.run()

