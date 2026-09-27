import AppKit
import Combine
import WebKit

struct DocumentHeading: Identifiable, Equatable {
    let id: String
    let title: String
    let level: Int
}

@MainActor
final class ReaderController: NSObject, ObservableObject, WKNavigationDelegate, WKScriptMessageHandler {
    let fileURL: URL?
    @Published private(set) var zoom: Double = 1
    @Published private(set) var headings: [DocumentHeading] = []
    @Published var showOutline = false
    @Published var findVisible = false
    @Published private(set) var findFocusRequest = 0
    @Published var findQuery = "" { didSet { if findQuery != oldValue { scheduleFind() } } }
    @Published private(set) var findCount = 0
    @Published private(set) var findIndex = 0
    @Published private(set) var isLoading = true
    @Published var errorMessage: String?
    private(set) var webView: WKWebView?
    private(set) var markdown: String
    private var ready = false
    private var watcher: FileWatcher?
    private var reloadGeneration = 0
    private var renderGeneration = 0
    private var findGeneration = 0
    private var findTask: Task<Void, Never>?
    private var pendingFragment: String?
    private var initialNavigation = true
    // Injectable endpoints keep link routing testable without opening other applications.
    var openExternal: (URL) -> Bool = { NSWorkspace.shared.open($0) }
    var openDocument: ((URL, String?) -> Void)?

    init(markdown: String, fileURL: URL?) {
        self.markdown = markdown
        self.fileURL = fileURL
        super.init()
        if let fileURL { ReaderWindows.register(self, for: fileURL) }
    }

    deinit {
        watcher?.stop()
        findTask?.cancel()
    }

    func makeWebView() -> WKWebView {
        if let webView { return webView }
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.setURLSchemeHandler(LocalImageHandler(), forURLScheme: "mdview-image")
        config.userContentController.add(WeakReaderHandler(self), name: "reader")
        let view = DocumentWebView(frame: .zero, configuration: config)
        view.navigationDelegate = self
        view.allowsBackForwardNavigationGestures = false
        view.setValue(false, forKey: "drawsBackground")
        view.setAccessibilityLabel("Markdown document")
        self.webView = view
        guard let index = ReaderResources.indexURL else {
            isLoading = false
            errorMessage = "The reader resources are missing. Reinstall mdview to restore them."
            return view
        }
        view.loadFileURL(index, allowingReadAccessTo: index.deletingLastPathComponent())
        return view
    }

    func startWatching() {
        guard watcher == nil, let fileURL else { return }
        watcher = FileWatcher(url: fileURL) { [weak self] in
            Task { @MainActor [weak self] in self?.reloadFile() }
        }
        if watcher == nil { errorMessage = "Changes to this file could not be monitored." }
    }

    func stopWatching() {
        watcher?.stop()
        watcher = nil
        reloadGeneration += 1
    }

    func reloadFile() {
        guard let fileURL else { return }
        reloadGeneration += 1
        let generation = reloadGeneration
        Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                Result { try String(contentsOf: fileURL, encoding: .utf8) }
            }.value
            guard let self, self.reloadGeneration == generation else { return }
            switch result {
            case .success(let text):
                self.errorMessage = nil
                self.updateMarkdown(text)
            case .failure:
                self.errorMessage = "The file is unavailable or is not UTF-8 text. Showing the last readable version."
            }
        }
    }

    func updateMarkdown(_ text: String) {
        guard text != markdown else { return }
        markdown = text
        render()
    }

    private func render() {
        guard ready, let view = webView else { return }
        renderGeneration += 1
        let generation = renderGeneration
        let options: [String: Any] = ["baseURL": fileURL?.deletingLastPathComponent().absoluteString ?? "",
                                      "documentURL": fileURL?.absoluteString ?? ""]
        view.callAsyncJavaScript("return await window.mdview.render(markdown, options)", arguments: ["markdown": markdown, "options": options], in: nil, in: .page) { [weak self] result in
            guard let self, self.renderGeneration == generation else { return }
            if case .failure(let error) = result {
                self.isLoading = false
                self.errorMessage = "The document could not be displayed: \(error.localizedDescription)"
            }
        }
    }

    func zoomIn() { setZoom(min(3, zoom * 1.1)) }
    func zoomOut() { setZoom(max(0.5, zoom / 1.1)) }
    func resetZoom() { setZoom(1) }
    private func setZoom(_ value: Double) {
        zoom = value
        guard ready else { return }
        webView?.callAsyncJavaScript("window.mdview.setZoom(scale)", arguments: ["scale": zoom], in: nil, in: .page)
    }

    func showFind() { findVisible = true; findFocusRequest += 1 }
    func hideFind() {
        findVisible = false
        findQuery = ""
        focusDocument()
    }
    func focusDocument() {
        guard let view = webView else { return }
        view.window?.makeFirstResponder(view)
    }
    func nextMatch() { find(direction: 1, reset: false) }
    func previousMatch() { find(direction: -1, reset: false) }
    private func scheduleFind() {
        findTask?.cancel()
        findTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            self?.find(direction: 1, reset: true)
        }
    }
    private func find(direction: Int, reset: Bool) {
        guard ready, let view = webView else { return }
        findGeneration += 1
        let generation = findGeneration
        view.callAsyncJavaScript("return window.mdview.find(query, direction, reset)", arguments: ["query": findQuery, "direction": direction, "reset": reset], in: nil, in: .page) { [weak self] result in
            guard let self, self.findGeneration == generation else { return }
            if case .success(let value) = result, let result = value as? [String: Any] {
                self.findCount = result["count"] as? Int ?? 0
                self.findIndex = result["index"] as? Int ?? 0
            }
        }
    }

    func scrollToHeading(_ id: String) {
        pendingFragment = id
        guard ready, !isLoading, let view = webView else { return }
        pendingFragment = nil
        view.callAsyncJavaScript("return window.mdview.scrollToHeading(id)", arguments: ["id": id], in: nil, in: .page)
    }

    func followLink(_ href: String) {
        switch LinkDestination.resolve(href, relativeTo: fileURL) {
        case .anchor(let id): scrollToHeading(id)
        case .document(let url, let fragment):
            guard FileManager.default.fileExists(atPath: url.path) else {
                errorMessage = "The linked file could not be found: \(url.lastPathComponent)"
                return
            }
            if let openDocument { openDocument(url, fragment) }
            else { ReaderWindows.open(url, fragment: fragment) { [weak self] error in self?.errorMessage = error.localizedDescription } }
        case .external(let url), .localFile(let url):
            if !openExternal(url) { errorMessage = "The link could not be opened: \(url.absoluteString)" }
        case .blocked:
            errorMessage = "This link uses an unsupported address."
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        switch type {
        case "ready": ready = true; render(); setZoom(zoom)
        case "rendered":
            isLoading = false
            if let fragment = pendingFragment { scrollToHeading(fragment) }
            if !findQuery.isEmpty { find(direction: 1, reset: true) }
        case "headings":
            headings = (body["headings"] as? [[String: Any]] ?? []).compactMap {
                guard let id = $0["id"] as? String, let title = $0["title"] as? String, let level = $0["level"] as? Int else { return nil }
                return DocumentHeading(id: id, title: title, level: level)
            }
        case "link": if let href = body["href"] as? String { followLink(href) }
        case "copy":
            if let text = body["text"] as? String {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            }
        case "error": errorMessage = body["message"] as? String ?? "The document could not be displayed."
        default: break
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // ready is normally sent by the bundled JS; focus enables immediate reading keys.
        if initialNavigation { initialNavigation = false; focusDocument() }
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        isLoading = false; errorMessage = error.localizedDescription
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        ready = false; isLoading = true; webView.reload()
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        if navigationAction.navigationType == .linkActivated {
            followLink(url.absoluteString); decisionHandler(.cancel); return
        }
        // Only our immutable bootstrap page is allowed to navigate the document surface.
        decisionHandler(url.standardizedFileURL == ReaderResources.indexURL?.standardizedFileURL ? .allow : .cancel)
    }
}

@MainActor
private final class WeakReaderHandler: NSObject, WKScriptMessageHandler {
    weak var reader: ReaderController?
    init(_ reader: ReaderController) { self.reader = reader }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        reader?.userContentController(userContentController, didReceive: message)
    }
}

@MainActor
private enum ReaderWindows {
    private static let controllers = NSMapTable<NSURL, ReaderController>(keyOptions: .strongMemory, valueOptions: .weakMemory)
    private static var pending: [URL: String] = [:]

    static func register(_ controller: ReaderController, for url: URL) {
        let key = url.standardizedFileURL
        controllers.setObject(controller, forKey: key as NSURL)
        if let fragment = pending.removeValue(forKey: key) { controller.scrollToHeading(fragment) }
    }
    static func open(_ url: URL, fragment: String?, onError: @escaping (Error) -> Void) {
        let key = url.standardizedFileURL
        if let existing = controllers.object(forKey: key as NSURL), let window = existing.webView?.window {
            window.makeKeyAndOrderFront(nil)
            if let fragment { existing.scrollToHeading(fragment) }
            return
        }
        if let fragment { pending[key] = fragment }
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
            if let error { pending.removeValue(forKey: key); onError(error) }
        }
    }
}
