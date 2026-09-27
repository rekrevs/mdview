import Foundation
import WebKit
import UniformTypeIdentifiers

/// Serve local image bytes to a renderer whose file access is limited to its own assets.
/// Document text never gains arbitrary file access or a script-capable file origin.
final class LocalImageHandler: NSObject, WKURLSchemeHandler {
    private let queue = DispatchQueue(label: "com.mdview.images", qos: .userInitiated)
    private var cancelled = Set<ObjectIdentifier>()
    private let lock = NSLock()

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        let identity = ObjectIdentifier(urlSchemeTask)
        lock.lock(); cancelled.remove(identity); lock.unlock()
        queue.async { [self] in
            let result: Result<(Data, URLResponse), Error> = Result {
                guard let requestURL = urlSchemeTask.request.url,
                      requestURL.host == "local",
                      let path = URLComponents(url: requestURL, resolvingAgainstBaseURL: false)?.percentEncodedPath.removingPercentEncoding,
                      path.hasPrefix("/") else { throw URLError(.badURL) }
                let url = URL(fileURLWithPath: path)
                guard let type = UTType(filenameExtension: url.pathExtension), type.conforms(to: .image),
                      let mime = type.preferredMIMEType else { throw URLError(.unsupportedURL) }
                let data = try Data(contentsOf: url, options: .mappedIfSafe)
                return (data, URLResponse(url: requestURL, mimeType: mime, expectedContentLength: data.count, textEncodingName: nil))
            }
            DispatchQueue.main.async { [self] in
                lock.lock(); let wasCancelled = cancelled.remove(identity) != nil; lock.unlock()
                guard !wasCancelled else { return }
                switch result {
                case .success(let (data, response)):
                    urlSchemeTask.didReceive(response)
                    urlSchemeTask.didReceive(data)
                    urlSchemeTask.didFinish()
                case .failure(let error): urlSchemeTask.didFailWithError(error)
                }
            }
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        lock.lock(); cancelled.insert(ObjectIdentifier(urlSchemeTask)); lock.unlock()
    }
}
