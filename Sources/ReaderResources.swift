import Foundation
import ReaderCore

/// Installed applications must resolve resources without touching the build tree.
enum ReaderResources {
    static var indexURL: URL? {
        let roots = [Bundle.main.resourceURL, Bundle.main.bundleURL].compactMap { $0 }
        return RendererPage.indexURL(searching: roots) ?? RendererPage.index(in: Bundle.module)
    }
}
