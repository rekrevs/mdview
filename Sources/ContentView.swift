import SwiftUI
import MarkdownUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ScrollView {
            Markdown(appState.markdownContent)
                .padding()
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 500, minHeight: 400)
        .background(Color(NSColor.textBackgroundColor))
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers)
        }
        .navigationTitle(appState.currentFile?.lastPathComponent ?? "mdview")
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, error in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil),
                  url.pathExtension.lowercased() == "md" || url.pathExtension.lowercased() == "markdown"
            else { return }

            DispatchQueue.main.async {
                appState.loadFile(url)
            }
        }
        return true
    }
}
