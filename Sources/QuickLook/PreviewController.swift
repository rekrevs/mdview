import AppKit
import os
import QuickLookUI
import ReaderCore
import WebKit

/// Finder Quick Look preview: the reader's bundled renderer in a sandboxed, read-only page.
/// Links are inert except in-document anchors (the renderer scrolls to those itself).
@objc(MDViewPreviewController)
final class PreviewController: NSViewController, QLPreviewingController, WKNavigationDelegate, WKScriptMessageHandler {
    static let renderTimeout: TimeInterval = 10
    private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.mdview.app.quicklook", category: "preview")
    private var webView: WKWebView?
    private var indexURL: URL?
    private var fileURL: URL?
    private var markdown = ""
    private var truncated = false
    private var completion: ((Error?) -> Void)?
    private var timeout: DispatchWorkItem?
    private var started = Date()

    override func loadView() {
        // No nib: NSViewController would otherwise look for one named after the class.
        view = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
    }

    func preparePreviewOfFile(at url: URL, completionHandler handler: @escaping (Error?) -> Void) {
        started = Date()
        let text: (text: String, truncated: Bool)
        do {
            text = try Self.read(url)
        } catch {
            log.error("preview failed for \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            handler(error)
            return
        }
        guard let index = RendererPage.indexURL(searching: [Bundle.main.resourceURL, Bundle.main.bundleURL].compactMap { $0 }) else {
            handler(Self.failure("The renderer resources are missing from the Quick Look extension. Reinstall mdview."))
            return
        }
        fileURL = url
        markdown = text.text
        truncated = text.truncated
        indexURL = index
        completion = handler

        let config = RendererPage.makeConfiguration()
        config.userContentController.add(WeakMessageHandler(self), name: RendererPage.messageHandlerName)
        let webView = WKWebView(frame: view.bounds, configuration: config)
        webView.autoresizingMask = [.width, .height]
        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = false
        webView.setValue(false, forKey: "drawsBackground")
        webView.setAccessibilityLabel("Markdown preview")
        view.addSubview(webView)
        self.webView = webView

        let work = DispatchWorkItem { [weak self] in
            self?.finish(Self.failure("The Markdown preview did not finish within \(Int(Self.renderTimeout)) seconds. Open the file in mdview."))
        }
        timeout = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.renderTimeout, execute: work)
        webView.loadFileURL(index, allowingReadAccessTo: index.deletingLastPathComponent())
    }

    /// Reads at most `PreviewText.byteLimit` bytes (plus one, to detect truncation).
    private static func read(_ url: URL) throws -> (text: String, truncated: Bool) {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: PreviewText.byteLimit + 1) ?? Data()
        guard let decoded = PreviewText.decode(data) else {
            throw failure("This file is not UTF-8 text, so mdview cannot preview it.")
        }
        return decoded
    }

    private static func failure(_ message: String) -> NSError {
        NSError(domain: "com.mdview.quicklook", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }

    private func finish(_ error: Error?) {
        timeout?.cancel(); timeout = nil
        guard let completion else { return }
        self.completion = nil
        if let error { log.error("preview failed: \(error.localizedDescription, privacy: .public)") }
        else { log.debug("preview ready after \(Date().timeIntervalSince(self.started), privacy: .public) s") }
        completion(error)
    }

    private func render() {
        guard let webView else { return }
        webView.callAsyncJavaScript(RendererPage.renderScript,
                                    arguments: ["markdown": markdown, "options": RendererPage.renderOptions(for: fileURL)],
                                    in: nil, in: .page) { [weak self] result in
            if case .failure(let error) = result {
                self?.finish(Self.failure("The document could not be displayed: \(error.localizedDescription)"))
            }
        }
    }

    private func rendered() {
        guard let webView, completion != nil else { return }
        if truncated {
            let note = "Preview truncated to the first \(PreviewText.byteLimit / (1024 * 1024)) MiB; open in mdview to read the whole document."
            webView.callAsyncJavaScript(Self.truncationScript, arguments: ["text": note], in: nil, in: .page) { _ in }
        }
        finish(nil)
        logStatistics(webView)
    }

    private static let truncationScript = """
        const note = document.createElement('p'); note.className = 'preview-note'; note.setAttribute('role', 'note');
        note.textContent = text;
        note.style.cssText = 'margin:0;padding:8px 16px;border-bottom:1px solid var(--border);color:var(--muted);font-size:0.875rem;';
        document.body.prepend(note);
        """

    /// One log line per preview (subsystem = the extension bundle identifier) for scripted checks.
    /// It waits for diagrams and images, so it never delays the preview itself.
    private static let statisticsScript = """
        const root = document.getElementById('document');
        const settle = Promise.all([window.mdview.diagramsSettled(), document.fonts.ready,
          ...Array.from(root.querySelectorAll('img')).filter(img => !img.complete).map(img => new Promise(resolve => {
            img.addEventListener('load', resolve, { once: true }); img.addEventListener('error', resolve, { once: true }); }))]);
        await Promise.race([settle, new Promise(resolve => setTimeout(resolve, 8000))]);
        const count = selector => root.querySelectorAll(selector).length;
        return {
          katex: count('.katex'), mathErrors: count('.math-error'),
          highlighted: Array.from(root.querySelectorAll('pre code')).filter(code => code.querySelector('[class^="hljs-"]')).length,
          images: Array.from(root.querySelectorAll('img')).filter(img => img.complete && img.naturalWidth > 0).length,
          imageErrors: count('.image-error'), alerts: count('.markdown-alert'), footnotes: count('section.footnotes li'),
          frontMatter: count('.front-matter'), tables: count('table'), tasks: count('.task-checkbox'),
          diagrams: count('figure.mermaid[data-state="rendered"]'), diagramErrors: count('figure.mermaid[data-state="error"]'),
          // Mermaid's own SVG carries a generated <style>; author HTML may carry none.
          activeHTML: count('script, iframe, object, embed, form, link, meta, base') + Array.from(root.querySelectorAll('style')).filter(style => !style.closest('.mermaid-svg')).length, literalScript: root.textContent.includes('<script>'),
          dark: matchMedia('(prefers-color-scheme: dark)').matches, truncated: !!document.querySelector('.preview-note')
        };
        """

    private func logStatistics(_ webView: WKWebView) {
        let elapsed = Date().timeIntervalSince(started)
        let file = fileURL?.lastPathComponent ?? "-"
        let bundle = Bundle.main.bundlePath
        webView.callAsyncJavaScript(Self.statisticsScript, arguments: [:], in: nil, in: .page) { [log] result in
            switch result {
            case .success(let value):
                let stats = (value as? [String: Any]) ?? [:]
                let fields = stats.keys.sorted().map { "\($0)=\(stats[$0].map { "\($0)" } ?? "")" }.joined(separator: " ")
                log.notice("MDVIEW-QL-STATS file=\(file, privacy: .public) bundle=\(bundle, privacy: .public) renderSeconds=\(String(format: "%.2f", elapsed), privacy: .public) \(fields, privacy: .public)")
            case .failure(let error):
                log.error("MDVIEW-QL-STATS failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: - WebKit

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        switch type {
        case "ready": log.debug("renderer ready"); render()
        case "rendered": log.debug("document rendered"); rendered()
        case "copy":
            if let text = body["text"] as? String {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            }
        case "error": finish(Self.failure(body["message"] as? String ?? "The document could not be displayed."))
        default: break // "link" and "headings": links stay inert in a preview.
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        // Only the immutable bootstrap page may load; every other navigation is cancelled.
        let allowed = navigationAction.request.url?.standardizedFileURL == indexURL?.standardizedFileURL
            && navigationAction.navigationType != .linkActivated
        decisionHandler(allowed ? .allow : .cancel)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        finish(Self.failure("The preview renderer stopped unexpectedly."))
    }
}

private final class WeakMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ target: WKScriptMessageHandler) { self.target = target }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}
