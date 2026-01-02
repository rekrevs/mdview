import SwiftUI
import Markdown
import AppKit

struct ContentView: View {
    let fileURL: URL?
    @State private var markdownText: String
    @State private var scrollProxy: ScrollViewProxy?
    @State private var zoomLevel: CGFloat = 1.0
    @State private var fileWatcher: FileWatcher?

    private let minZoom: CGFloat = 0.5
    private let maxZoom: CGFloat = 3.0
    private let zoomStep: CGFloat = 1.1

    private var baseURL: URL? {
        fileURL?.deletingLastPathComponent()
    }

    private var scaledFontSize: CGFloat {
        14 * zoomLevel
    }

    init(document: MarkdownDocument, fileURL: URL?) {
        self.fileURL = fileURL
        self._markdownText = State(initialValue: document.text)
    }

    var body: some View {
        KeyboardScrollView {
            ScrollViewReader { proxy in
                ScrollView {
                    MarkdownContentView(
                        text: markdownText,
                        baseURL: baseURL,
                        fontSize: scaledFontSize
                    )
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
        .environment(\.openURL, OpenURLAction { url in
            handleURL(url)
        })
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

    private func handleURL(_ url: URL) -> OpenURLAction.Result {
        // For markdown files, open in mdview
        if url.isFileURL && url.pathExtension.lowercased() == "md" {
            NSWorkspace.shared.open(
                [url],
                withApplicationAt: Bundle.main.bundleURL,
                configuration: NSWorkspace.OpenConfiguration()
            )
            return .handled
        }

        // For other URLs (http, https, etc.), use system default
        return .systemAction
    }
}

// MARK: - Markdown Content View

struct MarkdownContentView: View {
    let text: String
    let baseURL: URL?
    let fontSize: CGFloat

    var body: some View {
        let document = Document(parsing: text)
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(document.children.enumerated()), id: \.offset) { _, child in
                renderBlock(child)
            }
        }
    }

    @ViewBuilder
    private func renderBlock(_ markup: any Markup) -> some View {
        switch markup {
        case let heading as Heading:
            HeadingBlockView(heading: heading, fontSize: fontSize)

        case let paragraph as Paragraph:
            MathAwareParagraph(paragraph: paragraph, baseURL: baseURL, fontSize: fontSize)

        case let codeBlock as CodeBlock:
            CodeBlockContentView(codeBlock: codeBlock, fontSize: fontSize)

        case let blockQuote as BlockQuote:
            BlockQuoteContentView(blockQuote: blockQuote, baseURL: baseURL, fontSize: fontSize)

        case let orderedList as OrderedList:
            OrderedListContentView(list: orderedList, baseURL: baseURL, fontSize: fontSize)

        case let unorderedList as UnorderedList:
            UnorderedListContentView(list: unorderedList, baseURL: baseURL, fontSize: fontSize)

        case is ThematicBreak:
            Divider().padding(.vertical, 8)

        case let table as Markdown.Table:
            TableContentView(table: table, baseURL: baseURL, fontSize: fontSize)

        case is HTMLBlock:
            EmptyView()

        default:
            EmptyView()
        }
    }
}

// MARK: - Heading

struct HeadingBlockView: View {
    let heading: Heading
    let fontSize: CGFloat

    private var scaledSize: CGFloat {
        switch heading.level {
        case 1: return fontSize * 2.0
        case 2: return fontSize * 1.5
        case 3: return fontSize * 1.25
        case 4: return fontSize * 1.1
        case 5: return fontSize * 1.0
        default: return fontSize * 0.9
        }
    }

    private var topPadding: CGFloat {
        switch heading.level {
        case 1: return fontSize * 1.5
        case 2: return fontSize * 1.3
        case 3: return fontSize * 1.1
        default: return fontSize * 0.8
        }
    }

    var body: some View {
        renderInlineContent(Array(heading.children), fontSize: scaledSize, baseURL: nil)
            .fontWeight(.semibold)
            .padding(.top, topPadding)
            .padding(.bottom, fontSize * 0.3)
    }
}

// MARK: - Paragraph with Math

struct MathAwareParagraph: View {
    let paragraph: Paragraph
    let baseURL: URL?
    let fontSize: CGFloat

    var body: some View {
        let segments = parseSegments()

        if segments.count == 1, case .blockMath(let latex) = segments[0] {
            // Single block math - center it
            MathView(latex: latex, fontSize: fontSize * 1.2, displayStyle: true)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 8)
        } else {
            // Mixed content - use flow layout
            WrappingHStack(alignment: .leading, spacing: 0) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                    renderSegment(segment)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private enum Segment {
        case text(SwiftUI.Text)
        case inlineMath(String)
        case blockMath(String)
    }

    private func parseSegments() -> [Segment] {
        var segments: [Segment] = []

        for child in paragraph.children {
            if let textNode = child as? Markdown.Text {
                let parts = splitTextForMath(textNode.string)
                for part in parts {
                    switch part {
                    case .plain(let str):
                        if !str.isEmpty {
                            segments.append(.text(SwiftUI.Text(str).font(.system(size: fontSize))))
                        }
                    case .inline(let latex):
                        segments.append(.inlineMath(latex))
                    case .block(let latex):
                        segments.append(.blockMath(latex))
                    }
                }
            } else {
                // Handle other inline markup (emphasis, strong, etc.)
                let text = renderMarkupToText(child, fontSize: fontSize, baseURL: baseURL)
                segments.append(.text(text))
            }
        }

        return segments
    }

    private enum TextPart {
        case plain(String)
        case inline(String)
        case block(String)
    }

    private func splitTextForMath(_ text: String) -> [TextPart] {
        var parts: [TextPart] = []
        var remaining = text[...]

        while !remaining.isEmpty {
            // Look for block math first ($$...$$)
            if let blockStart = remaining.range(of: "$$") {
                let before = String(remaining[..<blockStart.lowerBound])
                if !before.isEmpty {
                    parts.append(.plain(before))
                }

                let afterStart = remaining[blockStart.upperBound...]
                if let blockEnd = afterStart.range(of: "$$") {
                    let latex = String(afterStart[..<blockEnd.lowerBound])
                    parts.append(.block(latex))
                    remaining = afterStart[blockEnd.upperBound...]
                } else {
                    parts.append(.plain(String(remaining[blockStart.lowerBound...])))
                    break
                }
            }
            // Look for inline math ($...$)
            else if let inlineStart = remaining.range(of: "$") {
                let before = String(remaining[..<inlineStart.lowerBound])
                if !before.isEmpty {
                    parts.append(.plain(before))
                }

                let afterStart = remaining[inlineStart.upperBound...]
                if let inlineEnd = afterStart.range(of: "$") {
                    let latex = String(afterStart[..<inlineEnd.lowerBound])
                    if !latex.isEmpty && !latex.contains("\n") {
                        parts.append(.inline(latex))
                    } else {
                        parts.append(.plain("$" + latex + "$"))
                    }
                    remaining = afterStart[inlineEnd.upperBound...]
                } else {
                    parts.append(.plain(String(remaining[inlineStart.lowerBound...])))
                    break
                }
            } else {
                parts.append(.plain(String(remaining)))
                break
            }
        }

        return parts
    }

    @ViewBuilder
    private func renderSegment(_ segment: Segment) -> some View {
        switch segment {
        case .text(let text):
            text
        case .inlineMath(let latex):
            MathView(latex: latex, fontSize: fontSize, displayStyle: false)
        case .blockMath(let latex):
            MathView(latex: latex, fontSize: fontSize * 1.2, displayStyle: true)
        }
    }
}

// MARK: - Inline Content Rendering

@ViewBuilder
func renderInlineContent(_ children: [any Markup], fontSize: CGFloat, baseURL: URL?) -> some View {
    children.reduce(SwiftUI.Text("")) { result, child in
        result + renderMarkupToText(child, fontSize: fontSize, baseURL: baseURL)
    }
    .font(.system(size: fontSize))
}

private func renderMarkupToText(_ markup: any Markup, fontSize: CGFloat, baseURL: URL?) -> SwiftUI.Text {
    switch markup {
    case let text as Markdown.Text:
        return SwiftUI.Text(text.string)

    case let emphasis as Emphasis:
        return emphasis.children.reduce(SwiftUI.Text("")) { result, child in
            result + renderMarkupToText(child, fontSize: fontSize, baseURL: baseURL)
        }.italic()

    case let strong as Strong:
        return strong.children.reduce(SwiftUI.Text("")) { result, child in
            result + renderMarkupToText(child, fontSize: fontSize, baseURL: baseURL)
        }.bold()

    case let inlineCode as InlineCode:
        return SwiftUI.Text(inlineCode.code)
            .font(.system(size: fontSize * 0.85, design: .monospaced))
            .foregroundColor(.secondary)

    case let link as Markdown.Link:
        let linkText = link.children.reduce(SwiftUI.Text("")) { result, child in
            result + renderMarkupToText(child, fontSize: fontSize, baseURL: baseURL)
        }
        return linkText.foregroundColor(.blue).underline()

    case is SoftBreak:
        return SwiftUI.Text(" ")

    case is LineBreak:
        return SwiftUI.Text("\n")

    case let strikethrough as Strikethrough:
        return strikethrough.children.reduce(SwiftUI.Text("")) { result, child in
            result + renderMarkupToText(child, fontSize: fontSize, baseURL: baseURL)
        }.strikethrough()

    default:
        return SwiftUI.Text("")
    }
}

// MARK: - Code Block

struct CodeBlockContentView: View {
    let codeBlock: CodeBlock
    let fontSize: CGFloat

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Text(codeBlock.code.trimmingCharacters(in: .whitespacesAndNewlines))
                .font(.system(size: fontSize * 0.85, design: .monospaced))
                .textSelection(.enabled)
                .padding()
        }
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .padding(.vertical, 4)
    }
}

// MARK: - Block Quote

struct BlockQuoteContentView: View {
    let blockQuote: BlockQuote
    let baseURL: URL?
    let fontSize: CGFloat

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Rectangle()
                .fill(Color.secondary.opacity(0.5))
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(blockQuote.children.enumerated()), id: \.offset) { _, child in
                    if let paragraph = child as? Paragraph {
                        MathAwareParagraph(paragraph: paragraph, baseURL: baseURL, fontSize: fontSize)
                            .foregroundColor(.secondary)
                            .italic()
                    }
                }
            }
            .padding(.leading, 16)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Lists

struct OrderedListContentView: View {
    let list: OrderedList
    let baseURL: URL?
    let fontSize: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(list.listItems.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .top, spacing: 8) {
                    Text("\(list.startIndex + UInt(index)).")
                        .font(.system(size: fontSize))
                        .foregroundColor(.secondary)
                        .frame(minWidth: 24, alignment: .trailing)

                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(item.children.enumerated()), id: \.offset) { _, child in
                            renderListItem(child)
                        }
                    }
                }
            }
        }
        .padding(.leading, 8)
    }

    @ViewBuilder
    private func renderListItem(_ child: any Markup) -> some View {
        if let paragraph = child as? Paragraph {
            MathAwareParagraph(paragraph: paragraph, baseURL: baseURL, fontSize: fontSize)
        } else if let nested = child as? OrderedList {
            OrderedListContentView(list: nested, baseURL: baseURL, fontSize: fontSize)
        } else if let nested = child as? UnorderedList {
            UnorderedListContentView(list: nested, baseURL: baseURL, fontSize: fontSize)
        }
    }
}

struct UnorderedListContentView: View {
    let list: UnorderedList
    let baseURL: URL?
    let fontSize: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(list.listItems.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .top, spacing: 8) {
                    Text("•")
                        .font(.system(size: fontSize))
                        .foregroundColor(.secondary)
                        .frame(minWidth: 24, alignment: .trailing)

                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(item.children.enumerated()), id: \.offset) { _, child in
                            renderListItem(child)
                        }
                    }
                }
            }
        }
        .padding(.leading, 8)
    }

    @ViewBuilder
    private func renderListItem(_ child: any Markup) -> some View {
        if let paragraph = child as? Paragraph {
            MathAwareParagraph(paragraph: paragraph, baseURL: baseURL, fontSize: fontSize)
        } else if let nested = child as? OrderedList {
            OrderedListContentView(list: nested, baseURL: baseURL, fontSize: fontSize)
        } else if let nested = child as? UnorderedList {
            UnorderedListContentView(list: nested, baseURL: baseURL, fontSize: fontSize)
        }
    }
}

// MARK: - Table

struct TableContentView: View {
    let table: Markdown.Table
    let baseURL: URL?
    let fontSize: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 0) {
                ForEach(Array(table.head.cells.enumerated()), id: \.offset) { _, cell in
                    TableCellContentView(cell: cell, baseURL: baseURL, fontSize: fontSize, isHeader: true)
                }
            }
            .background(Color(NSColor.controlBackgroundColor))

            // Body rows
            ForEach(Array(table.body.rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 0) {
                    ForEach(Array(row.cells.enumerated()), id: \.offset) { _, cell in
                        TableCellContentView(cell: cell, baseURL: baseURL, fontSize: fontSize, isHeader: false)
                    }
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .padding(.vertical, 4)
    }
}

struct TableCellContentView: View {
    let cell: Markdown.Table.Cell
    let baseURL: URL?
    let fontSize: CGFloat
    let isHeader: Bool

    var body: some View {
        renderInlineContent(Array(cell.children), fontSize: fontSize, baseURL: baseURL)
            .fontWeight(isHeader ? .semibold : .regular)
            .padding(.horizontal, 13)
            .padding(.vertical, 6)
            .frame(minWidth: 60, alignment: .leading)
            .overlay(
                Rectangle()
                    .stroke(Color.secondary.opacity(0.3), lineWidth: 0.5)
            )
    }
}

// MARK: - Wrapping HStack with vertical center alignment

struct WrappingHStack: Layout {
    var alignment: HorizontalAlignment = .leading
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                                  proposal: .unspecified)
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity

        // First pass: group subviews into rows
        var rows: [[LayoutSubviews.Element]] = []
        var currentRow: [LayoutSubviews.Element] = []
        var currentX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if currentX + size.width > maxWidth && currentX > 0 {
                rows.append(currentRow)
                currentRow = []
                currentX = 0
            }

            currentRow.append(subview)
            currentX += size.width
        }
        if !currentRow.isEmpty {
            rows.append(currentRow)
        }

        // Second pass: calculate positions with vertical center alignment
        var positions: [CGPoint] = []
        var currentY: CGFloat = 0
        var totalWidth: CGFloat = 0

        for row in rows {
            // Find the maximum height in this row
            var rowHeight: CGFloat = 0
            for subview in row {
                let dims = subview.dimensions(in: .unspecified)
                rowHeight = max(rowHeight, dims.height)
            }

            // Place each subview vertically centered within the row
            var x: CGFloat = 0
            for subview in row {
                let dims = subview.dimensions(in: .unspecified)
                // Center this view vertically within the row
                let yOffset = (rowHeight - dims.height) / 2

                positions.append(CGPoint(x: x, y: currentY + yOffset))
                x += dims.width
                totalWidth = max(totalWidth, x)
            }

            currentY += rowHeight + spacing
        }

        let totalHeight = max(0, currentY - spacing) // Remove trailing spacing

        return (CGSize(width: totalWidth, height: totalHeight), positions)
    }
}

// MARK: - Image Support

struct LocalImageView: View {
    let url: URL?
    let baseURL: URL?

    var body: some View {
        if let imageURL = resolvedURL, let nsImage = NSImage(contentsOf: imageURL) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: nsImage.size.width, maxHeight: nsImage.size.height)
        }
    }

    private var resolvedURL: URL? {
        guard let url = url else { return nil }
        if url.scheme == "file" || url.scheme == nil {
            if url.path.hasPrefix("/") {
                return url
            } else if let base = baseURL {
                return base.appendingPathComponent(url.path)
            }
        }
        return url
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
