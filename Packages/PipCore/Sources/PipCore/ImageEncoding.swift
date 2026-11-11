import Foundation

public struct EncodedImage: Equatable, Sendable {
    public var base64: String
    public var filename: String
    public var mimeType: String

    public init(base64: String, filename: String, mimeType: String) {
        self.base64 = base64
        self.filename = filename
        self.mimeType = mimeType
    }
}

public protocol ImageEncoding: Sendable {
    func encodeJPEG(data: Data, preferredFilename: String?) throws -> EncodedImage
}

enum JPEGFilename {
    static func make(preferred: String?) -> String {
        let raw = preferred?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let stem = URL(fileURLWithPath: raw).deletingPathExtension().lastPathComponent
        let cleaned = stem.trimmingCharacters(in: .whitespacesAndNewlines)
        return (cleaned.isEmpty ? "image" : cleaned) + ".jpg"
    }
}
