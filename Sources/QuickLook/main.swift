import Foundation

// An app extension's entry point is Foundation's NSExtensionMain, which looks up the
// NSExtensionPrincipalClass (MDViewPreviewController) and serves Quick Look's XPC
// requests. SwiftPM generates `_main` for executable targets, so main.swift hands over
// to it instead of relinking with `-e _NSExtensionMain`.
@_silgen_name("NSExtensionMain")
private func NSExtensionMain(_ argc: Int32, _ argv: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) -> Int32

// Reference the principal class so the linker can never strip it.
_ = PreviewController.self
exit(NSExtensionMain(CommandLine.argc, CommandLine.unsafeArgv))
