import SwiftUI

@main
struct mdviewApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open...") {
                    appState.openFile()
                }
                .keyboardShortcut("o", modifiers: .command)
            }
        }
    }
}

class AppState: ObservableObject {
    @Published var markdownContent: String = """
        # Welcome to mdview

        Use **File > Open** (⌘O) to open a markdown file.

        Or drag a `.md` file onto this window.
        """
    @Published var currentFile: URL?

    func openFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Select a Markdown file"

        if panel.runModal() == .OK, let url = panel.url {
            loadFile(url)
        }
    }

    func loadFile(_ url: URL) {
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            markdownContent = content
            currentFile = url
        } catch {
            markdownContent = "# Error\n\nCould not read file: \(error.localizedDescription)"
        }
    }
}
