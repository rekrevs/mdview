import SwiftUI

@main
struct mdviewApp: App {
    var body: some Scene {
        DocumentGroup(viewing: MarkdownDocument.self) { file in
            ContentView(document: file.document, fileURL: file.fileURL)
        }
        .defaultSize(width: 820, height: defaultWindowHeight)
        .commands { ReaderCommands() }
    }

    private var defaultWindowHeight: CGFloat {
        (NSScreen.main?.visibleFrame.height ?? 1000) * 0.8
    }
}
