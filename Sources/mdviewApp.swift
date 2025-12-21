import SwiftUI
import AppKit

@main
struct mdviewApp: App {
    var body: some Scene {
        DocumentGroup(viewing: MarkdownDocument.self) { file in
            ContentView(document: file.document)
        }
        .defaultSize(width: defaultWindowWidth, height: defaultWindowHeight)
    }

    private var defaultWindowHeight: CGFloat {
        guard let screen = NSScreen.main else { return 800 }
        return screen.visibleFrame.height * 0.8
    }

    private var defaultWindowWidth: CGFloat {
        guard let screen = NSScreen.main else { return 600 }
        // Use 50% of screen width, but cap between 600-1000
        let width = screen.visibleFrame.width * 0.5
        return min(max(width, 600), 1000)
    }
}
