import Cocoa
// Separate application identity keeps authentication windows independently visible.
guard CommandLine.arguments.dropFirst().first == "--ssh-askpass" else {exit(1)}
exit(SSHLoginEnvironment.answer(prompt:CommandLine.arguments.dropFirst(2).first ?? "SSH authentication"))
