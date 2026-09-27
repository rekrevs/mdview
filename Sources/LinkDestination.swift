import Foundation

/// Resolve against the document URL, never the bundled renderer's location.
enum LinkDestination: Equatable {
    case anchor(String)
    case document(URL, fragment: String?)
    case external(URL)
    case localFile(URL)
    case blocked

    static func resolve(_ href: String, relativeTo document: URL?) -> LinkDestination {
        let href = href.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !href.isEmpty else { return .blocked }
        if href.hasPrefix("#") {
            return .anchor(String(href.dropFirst()).removingPercentEncoding ?? String(href.dropFirst()))
        }
        guard let url = URL(string: href, relativeTo: document)?.absoluteURL,
              let scheme = url.scheme?.lowercased() else { return .blocked }
        if ["http", "https", "mailto"].contains(scheme) { return .external(url) }
        guard scheme == "file", url.host == nil || url.host == "" || url.host == "localhost",
              var parts = URLComponents(url: url, resolvingAgainstBaseURL: true) else { return .blocked }
        let fragment = parts.fragment
        parts.fragment = nil
        parts.query = nil
        guard let target = parts.url?.standardizedFileURL else { return .blocked }
        if target == document?.standardizedFileURL { return .anchor(fragment ?? "") }
        if ["md", "markdown", "mdown", "mkd"].contains(target.pathExtension.lowercased()) {
            return .document(target, fragment: fragment)
        }
        return .localFile(target)
    }
}
