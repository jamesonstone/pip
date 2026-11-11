import Foundation

/// Decodes the URL representations returned by share item providers.
public enum ShareURLDecoder {
    public static func decode(_ item: Any) throws -> URL {
        if let url = item as? URL { return url }
        if let text = item as? String, let url = URL(string: text) { return url }
        if let data = item as? Data,
           let text = String(data: data, encoding: .utf8),
           let url = URL(string: text) {
            return url
        }
        throw PayloadError.unreadable
    }
}
