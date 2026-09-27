import SwiftUI
import WebKit

struct ReaderWebView: NSViewRepresentable {
    @ObservedObject var reader: ReaderController

    func makeNSView(context: Context) -> WKWebView { reader.makeWebView() }
    func updateNSView(_ view: WKWebView, context: Context) {}
}

final class DocumentWebView: WKWebView {
    override func keyDown(with event: NSEvent) {
        // Character shortcuts are handled by SwiftUI commands, preserving keyboard layout.
        // WebKit handles selection (Shift+arrows), while physical reading keys scroll.
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if mods.contains(.shift) && event.keyCode != 49 { super.keyDown(with: event); return }
        let action: String?
        switch event.keyCode {
        case 126: action = mods.contains(.command) ? "window.scrollTo(0,0)" : "window.scrollBy(0,-\(mods.contains(.option) ? "window.innerHeight*0.9" : "40"))"
        case 125: action = mods.contains(.command) ? "window.scrollTo(0,document.documentElement.scrollHeight)" : "window.scrollBy(0,\(mods.contains(.option) ? "window.innerHeight*0.9" : "40"))"
        case 49 where !mods.contains(.command): action = "window.scrollBy(0,window.innerHeight*\(mods.contains(.shift) ? "-0.9" : "0.9"))"
        case 115: action = "window.scrollTo(0,0)"
        case 119: action = "window.scrollTo(0,document.documentElement.scrollHeight)"
        case 116: action = "window.scrollBy(0,-window.innerHeight*0.9)"
        case 121: action = "window.scrollBy(0,window.innerHeight*0.9)"
        default: action = nil
        }
        if let action { evaluateJavaScript(action) } else { super.keyDown(with: event) }
    }
}
