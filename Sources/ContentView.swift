import SwiftUI
import MarkdownUI

struct ContentView: View {
    let fileURL: URL?
    @State private var markdownText: String
    @State private var scrollProxy: ScrollViewProxy?
    @State private var zoomLevel: CGFloat = 1.0
    @State private var fileWatcher: FileWatcher?

    private let minZoom: CGFloat = 0.5
    private let maxZoom: CGFloat = 3.0
    private let zoomStep: CGFloat = 1.1

    init(document: MarkdownDocument, fileURL: URL?) {
        self.fileURL = fileURL
        self._markdownText = State(initialValue: document.text)
    }

    var body: some View {
        KeyboardScrollView {
            ScrollViewReader { proxy in
                ScrollView {
                    Markdown(markdownText, imageBaseURL: fileURL?.deletingLastPathComponent())
                        .markdownImageProvider(LocalFileImageProvider())
                        .markdownTheme(scaledTheme)
                        .padding()
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .id("content")
                }
                .onAppear {
                    scrollProxy = proxy
                }
            }
        }
        .frame(minWidth: 500, minHeight: 400)
        .background(Color(NSColor.textBackgroundColor))
        .onAppear {
            startWatching()
        }
        .onDisappear {
            stopWatching()
        }
        .onReceive(NotificationCenter.default.publisher(for: .zoomIn)) { _ in
            zoomIn()
        }
        .onReceive(NotificationCenter.default.publisher(for: .zoomOut)) { _ in
            zoomOut()
        }
        .onReceive(NotificationCenter.default.publisher(for: .zoomReset)) { _ in
            zoomReset()
        }
    }

    private func startWatching() {
        guard let url = fileURL else { return }
        fileWatcher = FileWatcher(url: url) { [self] in
            reloadFile()
        }
    }

    private func stopWatching() {
        fileWatcher = nil
    }

    private func reloadFile() {
        guard let url = fileURL,
              let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8)
        else { return }

        if text != markdownText {
            markdownText = text
        }
    }

    private func zoomIn() {
        zoomLevel = min(maxZoom, zoomLevel * zoomStep)
    }

    private func zoomOut() {
        zoomLevel = max(minZoom, zoomLevel / zoomStep)
    }

    private func zoomReset() {
        zoomLevel = 1.0
    }

    private var scaledTheme: Theme {
        let baseFontSize: CGFloat = 14 * zoomLevel
        return Theme()
            .text {
                FontSize(baseFontSize)
            }
            .code {
                FontFamilyVariant(.monospaced)
                FontSize(.em(0.85))
            }
            .heading1 { configuration in
                configuration.label
                    .markdownTextStyle {
                        FontWeight(.semibold)
                        FontSize(.em(2))
                    }
                    .markdownMargin(top: .em(1.5), bottom: .em(0.5))
            }
            .heading2 { configuration in
                configuration.label
                    .markdownTextStyle {
                        FontWeight(.semibold)
                        FontSize(.em(1.5))
                    }
                    .markdownMargin(top: .em(1.3), bottom: .em(0.4))
            }
            .heading3 { configuration in
                configuration.label
                    .markdownTextStyle {
                        FontWeight(.semibold)
                        FontSize(.em(1.25))
                    }
                    .markdownMargin(top: .em(1.1), bottom: .em(0.3))
            }
            .heading4 { configuration in
                configuration.label
                    .markdownTextStyle {
                        FontWeight(.semibold)
                        FontSize(.em(1.1))
                    }
                    .markdownMargin(top: .em(1), bottom: .em(0.2))
            }
            .heading5 { configuration in
                configuration.label
                    .markdownTextStyle {
                        FontWeight(.semibold)
                        FontSize(.em(1))
                    }
                    .markdownMargin(top: .em(0.9), bottom: .em(0.2))
            }
            .heading6 { configuration in
                configuration.label
                    .markdownTextStyle {
                        FontWeight(.semibold)
                        FontSize(.em(0.9))
                    }
                    .markdownMargin(top: .em(0.8), bottom: .em(0.2))
            }
            .codeBlock { configuration in
                configuration.label
                    .markdownTextStyle {
                        FontFamilyVariant(.monospaced)
                        FontSize(.em(0.85))
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .markdownMargin(top: .em(0.5), bottom: .em(0.5))
            }
            .blockquote { configuration in
                configuration.label
                    .markdownTextStyle {
                        FontStyle(.italic)
                        ForegroundColor(.secondary)
                    }
                    .padding(.leading, 16)
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.5))
                            .frame(width: 4)
                    }
            }
            .table { configuration in
                configuration.label
                    .fixedSize(horizontal: false, vertical: true)
                    .markdownTableBorderStyle(.init(color: .secondary.opacity(0.3)))
                    .markdownMargin(top: .em(0.5), bottom: .em(0.5))
            }
            .tableCell { configuration in
                configuration.label
                    .markdownTextStyle {
                        if configuration.row == 0 {
                            FontWeight(.semibold)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 13)
            }
    }
}

// MARK: - Local File Image Provider

struct LocalFileImageProvider: ImageProvider {
    func makeImage(url: URL?) -> some View {
        if let url = url, url.isFileURL, let nsImage = NSImage(contentsOf: url) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: nsImage.size.width, maxHeight: nsImage.size.height)
        }
    }
}

// MARK: - File Watcher

class FileWatcher {
    private var source: DispatchSourceFileSystemObject?
    private let fileDescriptor: Int32
    private let onChange: () -> Void

    init?(url: URL, onChange: @escaping () -> Void) {
        self.onChange = onChange
        self.fileDescriptor = open(url.path, O_EVTONLY)

        guard fileDescriptor >= 0 else { return nil }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .rename, .delete, .extend],
            queue: .main
        )

        source.setEventHandler { [weak self] in
            self?.onChange()
        }

        source.setCancelHandler { [weak self] in
            if let fd = self?.fileDescriptor, fd >= 0 {
                close(fd)
            }
        }

        source.resume()
        self.source = source
    }

    deinit {
        source?.cancel()
    }
}

// MARK: - Keyboard handling wrapper

struct KeyboardScrollView<Content: View>: NSViewRepresentable {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    func makeNSView(context: Context) -> KeyboardCaptureView {
        let view = KeyboardCaptureView()
        let hostingView = NSHostingView(rootView: content)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hostingView)

        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: view.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        context.coordinator.hostingView = hostingView
        return view
    }

    func updateNSView(_ nsView: KeyboardCaptureView, context: Context) {
        context.coordinator.hostingView?.rootView = content
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {
        var hostingView: NSHostingView<Content>?
    }
}

class KeyboardCaptureView: NSView {
    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        DispatchQueue.main.async {
            self.window?.makeFirstResponder(self)
        }
    }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        guard let scrollView = findScrollView() else {
            super.keyDown(with: event)
            return
        }

        let clipView = scrollView.contentView
        guard let documentView = scrollView.documentView else {
            super.keyDown(with: event)
            return
        }

        let lineHeight: CGFloat = 40
        let pageHeight = scrollView.bounds.height - lineHeight

        let currentY = clipView.bounds.origin.y
        let maxY = max(0, documentView.bounds.height - clipView.bounds.height)

        var newY = currentY

        switch event.keyCode {
        case 126: // Up arrow
            if event.modifierFlags.contains(.command) {
                newY = 0
            } else if event.modifierFlags.contains(.option) {
                newY = max(0, currentY - pageHeight)
            } else {
                newY = max(0, currentY - lineHeight)
            }

        case 125: // Down arrow
            if event.modifierFlags.contains(.command) {
                newY = maxY
            } else if event.modifierFlags.contains(.option) {
                newY = min(maxY, currentY + pageHeight)
            } else {
                newY = min(maxY, currentY + lineHeight)
            }

        case 49: // Space bar
            if event.modifierFlags.contains(.shift) {
                newY = max(0, currentY - pageHeight)
            } else {
                newY = min(maxY, currentY + pageHeight)
            }

        case 115: // Home
            newY = 0

        case 119: // End
            newY = maxY

        case 116: // Page Up
            newY = max(0, currentY - pageHeight)

        case 121: // Page Down
            newY = min(maxY, currentY + pageHeight)

        default:
            super.keyDown(with: event)
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            clipView.animator().setBoundsOrigin(NSPoint(x: 0, y: newY))
        }
    }

    private func findScrollView() -> NSScrollView? {
        var view: NSView? = self
        while let v = view {
            for subview in v.subviews {
                if let scrollView = findScrollViewIn(subview) {
                    return scrollView
                }
            }
            view = v.superview
        }
        return nil
    }

    private func findScrollViewIn(_ view: NSView) -> NSScrollView? {
        if let scrollView = view as? NSScrollView {
            return scrollView
        }
        for subview in view.subviews {
            if let scrollView = findScrollViewIn(subview) {
                return scrollView
            }
        }
        return nil
    }

    override func becomeFirstResponder() -> Bool {
        return true
    }
}
