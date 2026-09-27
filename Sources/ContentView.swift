import SwiftUI

struct ContentView: View {
    @StateObject private var reader: ReaderController

    init(document: MarkdownDocument, fileURL: URL?) {
        _reader = StateObject(wrappedValue: ReaderController(markdown: document.text, fileURL: fileURL))
    }

    var body: some View {
        VStack(spacing: 0) {
            if reader.findVisible { findBar }
            if let message = reader.errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                    Text(message).font(.callout).textSelection(.enabled)
                    Spacer()
                    Button { reader.errorMessage = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain).help("Dismiss")
                }.padding(10).background(Color.yellow.opacity(0.12))
                Divider()
            }
            HStack(spacing: 0) {
                if reader.showOutline {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 3) {
                            if reader.headings.isEmpty { Text("No headings").foregroundStyle(.secondary).padding() }
                            ForEach(reader.headings) { heading in
                                Button { reader.scrollToHeading(heading.id) } label: {
                                    Text(heading.title)
                                        .font(.system(size: 12, weight: heading.level == 1 ? .semibold : .regular))
                                        .multilineTextAlignment(.leading)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.leading, CGFloat(max(0, heading.level - 1)) * 10)
                                        .padding(.vertical, 5)
                                }.buttonStyle(.plain)
                            }
                        }.padding(12)
                    }.frame(width: 220).background(.quaternary.opacity(0.3))
                    Divider()
                }
                ReaderWebView(reader: reader)
                    .overlay(alignment: .topTrailing) {
                        if reader.isLoading { ProgressView().controlSize(.small).padding() }
                    }
            }
        }
        .frame(minWidth: 500, minHeight: 400)
        .background(Color(nsColor: .textBackgroundColor))
        .focusedSceneValue(\.readerController, reader)
        .toolbar {
            ToolbarItemGroup {
                Button { reader.showOutline.toggle() } label: { Image(systemName: "sidebar.left") }.help("Table of Contents")
                Button { reader.showFind() } label: { Image(systemName: "magnifyingglass") }.help("Find (⌘F)")
            }
        }
        .onAppear { reader.startWatching() }
        .onDisappear { reader.stopWatching() }
        .onExitCommand { if reader.findVisible { reader.hideFind() } }
    }

    private var findBar: some View {
        HStack(spacing: 8) {
            NativeFindField(text: $reader.findQuery, focusRequest: reader.findFocusRequest,
                            next: reader.nextMatch, previous: reader.previousMatch, dismiss: reader.hideFind)
            Text(reader.findQuery.isEmpty ? "" : "\(reader.findIndex) of \(reader.findCount)")
                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            Button { reader.previousMatch() } label: { Image(systemName: "chevron.up") }.help("Previous match (⇧⌘G)")
            Button { reader.nextMatch() } label: { Image(systemName: "chevron.down") }.help("Next match (⌘G)")
            Button("Done") { reader.hideFind() }
        }.padding(10).background(.bar)
    }
}

private struct ReaderControllerKey: FocusedValueKey { typealias Value = ReaderController }
extension FocusedValues {
    var readerController: ReaderController? {
        get { self[ReaderControllerKey.self] }
        set { self[ReaderControllerKey.self] = newValue }
    }
}

struct ReaderCommands: Commands {
    @FocusedValue(\.readerController) private var reader
    var body: some Commands {
        CommandGroup(after: .textEditing) {
            Divider()
            Button("Find…") { reader?.showFind() }.keyboardShortcut("f").disabled(reader == nil)
            Button("Find Next") { reader?.nextMatch() }.keyboardShortcut("g").disabled(reader == nil)
            Button("Find Previous") { reader?.previousMatch() }.keyboardShortcut("g", modifiers: [.command, .shift]).disabled(reader == nil)
        }
        CommandGroup(after: .toolbar) {
            Divider()
            Button("Table of Contents") { reader?.showOutline.toggle() }.keyboardShortcut("t", modifiers: [.command, .option]).disabled(reader == nil)
            Button("Zoom In") { reader?.zoomIn() }.keyboardShortcut("+").disabled(reader == nil)
            Button("Zoom Out") { reader?.zoomOut() }.keyboardShortcut("-").disabled(reader == nil)
            Button("Actual Size") { reader?.resetZoom() }.keyboardShortcut("0").disabled(reader == nil)
            Divider()
            Button("Reload") { reader?.reloadFile() }.keyboardShortcut("r").disabled(reader?.fileURL == nil)
        }
    }
}
