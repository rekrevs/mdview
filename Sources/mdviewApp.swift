import SwiftUI
import AppKit

@main
struct mdviewApp: App {
    var body: some Scene {
        DocumentGroup(viewing: MarkdownDocument.self) { file in
            ContentView(document: file.document)
        }
        .defaultSize(width: defaultWindowWidth, height: defaultWindowHeight)
        .commands {
            CommandGroup(after: .toolbar) {
                Divider()
                Button("Zoom In") {
                    NotificationCenter.default.post(name: .zoomIn, object: nil)
                }
                .keyboardShortcut("+", modifiers: .command)

                Button("Zoom Out") {
                    NotificationCenter.default.post(name: .zoomOut, object: nil)
                }
                .keyboardShortcut("-", modifiers: .command)

                Button("Actual Size") {
                    NotificationCenter.default.post(name: .zoomReset, object: nil)
                }
                .keyboardShortcut("0", modifiers: .command)
            }
        }
    }

    private var defaultWindowHeight: CGFloat {
        guard let screen = NSScreen.main else { return 800 }
        return screen.visibleFrame.height * 0.8
    }

    private var defaultWindowWidth: CGFloat {
        guard let screen = NSScreen.main else { return 600 }
        let width = screen.visibleFrame.width * 0.5
        return min(max(width, 600), 1000)
    }
}

extension Notification.Name {
    static let zoomIn = Notification.Name("zoomIn")
    static let zoomOut = Notification.Name("zoomOut")
    static let zoomReset = Notification.Name("zoomReset")
}
