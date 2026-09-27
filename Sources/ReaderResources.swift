import Foundation

/// Installed applications must resolve resources without touching the build tree.
enum ReaderResources {
    static var indexURL: URL? {
        let bundles = [Bundle.main.resourceURL, Bundle.main.bundleURL].compactMap { $0 }
        for root in bundles {
            let url = root.appendingPathComponent("mdview_mdview.bundle")
            if let bundle = Bundle(url: url), let index = index(in: bundle) { return index }
        }
        return index(in: Bundle.module)
    }

    private static func index(in bundle: Bundle) -> URL? {
        guard let root = bundle.resourceURL else { return nil }
        for path in ["Resources/Web/index.html", "Web/index.html"] {
            let url = root.appendingPathComponent(path)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return nil
    }
}
