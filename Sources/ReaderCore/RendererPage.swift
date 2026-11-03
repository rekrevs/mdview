import Foundation
import WebKit

/// The bundled renderer page shared by reader windows and the Quick Look extension.
/// Each host bundle carries its own copy of the resource bundle and resolves it here,
/// so an installed app or extension never reads resources from a build tree.
public enum RendererPage {
    /// SwiftPM's resource bundle for the app target, copied into every host bundle.
    public static let resourceBundleName = "mdview_mdview.bundle"
    /// The script message handler name the renderer posts to (`window.webkit.messageHandlers.reader`).
    public static let messageHandlerName = "reader"
    /// The custom scheme the renderer uses for local images (see `LocalImageHandler`).
    public static let imageScheme = "mdview-image"
    /// Render with `callAsyncJavaScript`, passing `markdown` and `options` as arguments.
    public static let renderScript = "return await window.mdview.render(markdown, options)"

    /// The first `index.html` found in a resource bundle directly inside one of `roots`.
    public static func indexURL(searching roots: [URL]) -> URL? {
        for root in roots {
            let url = root.appendingPathComponent(resourceBundleName)
            if let bundle = Bundle(url: url), let index = index(in: bundle) { return index }
        }
        return nil
    }

    /// The renderer page inside a resource bundle. SwiftPM's native build system emits a flat
    /// bundle (`Resources/Web`); the Swift Build backend emits `Contents/Resources/Resources/Web`,
    /// which `Bundle.resourceURL` already resolves to `Contents/Resources`.
    public static func index(in bundle: Bundle) -> URL? {
        guard let root = bundle.resourceURL else { return nil }
        for path in ["Resources/Web/index.html", "Web/index.html"] {
            let url = root.appendingPathComponent(path)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return nil
    }

    /// A configuration with no persistent website data and the local image scheme.
    /// The caller adds its own script message handler under `messageHandlerName`.
    @MainActor
    public static func makeConfiguration() -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.setURLSchemeHandler(LocalImageHandler(), forURLScheme: imageScheme)
        return config
    }

    /// Options for `window.mdview.render`: relative links and images resolve against the file.
    public static func renderOptions(for fileURL: URL?, diagrams: Bool = true) -> [String: Any] {
        var options: [String: Any] = ["baseURL": fileURL?.deletingLastPathComponent().absoluteString ?? "",
                                      "documentURL": fileURL?.absoluteString ?? ""]
        if !diagrams { options["diagrams"] = false }
        return options
    }
}
