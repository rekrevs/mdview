import Foundation

/// Bounded UTF-8 decoding for previews, which must stay fast on very large files.
public enum PreviewText {
    /// Quick Look renders at most this many bytes of a document.
    public static let byteLimit = 4 * 1024 * 1024

    /// Decode `data` as UTF-8, keeping at most `limit` bytes. A cut never splits a character:
    /// up to three trailing bytes of an incomplete sequence are dropped. Returns nil when the
    /// kept bytes are not valid UTF-8. `data` may hold more than `limit` bytes to signal truncation.
    public static func decode(_ data: Data, limit: Int = byteLimit) -> (text: String, truncated: Bool)? {
        guard data.count > limit else {
            return String(data: data, encoding: .utf8).map { ($0, false) }
        }
        let prefix = data.prefix(limit)
        for drop in 0...min(3, prefix.count) {
            if let text = String(data: prefix.dropLast(drop), encoding: .utf8) { return (text, true) }
        }
        return nil
    }
}
