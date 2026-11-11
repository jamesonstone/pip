import Foundation

public struct PayloadBuilder: Sendable {
    public var limits: PayloadLimits
    public var images: any ImageEncoding

    public init(limits: PayloadLimits = .standard, images: any ImageEncoding) {
        self.limits = limits
        self.images = images
    }

    public func build(_ share: InboundShare) throws -> IntakePayload {
        let note = try limited(share.note, maxCharacters: limits.maxNoteCharacters)
        let sharedText = try limited(share.sharedText, maxCharacters: limits.maxTextCharacters)
        let fileText = try textualBody(share.file)
        let link = share.link.flatMap { normalizedLink($0) }

        let url: String?
        if let link {
            url = link
        } else if let sharedText {
            url = sharedText
        } else {
            url = fileText
        }

        let text: String?
        if let note {
            text = note
        } else if link != nil, let sharedText, sharedText != link {
            text = sharedText
        } else if link != nil, let fileText, fileText != link {
            text = fileText
        } else {
            text = nil
        }

        var imageBase64: String?
        var filename: String?
        var mimeType: String?

        if let image = share.image {
            let encoded = try images.encodeJPEG(data: image.data, preferredFilename: image.filename)
            imageBase64 = encoded.base64
            filename = encoded.filename
            mimeType = encoded.mimeType
        } else if let file = share.file {
            filename = cleanedFilename(file.filename)
            mimeType = file.mimeType ?? MimeTypes.from(filename: filename ?? "")
            if fileText == nil {
                if file.data.count > limits.maxFileBytes {
                    throw PayloadError.tooLarge(limit: limits.maxFileBytes)
                }
                imageBase64 = file.data.base64EncodedString()
                if mimeType == nil {
                    mimeType = "application/octet-stream"
                }
            }
        }

        guard url != nil || text != nil || imageBase64 != nil else {
            throw PayloadError.empty
        }

        return IntakePayload(
            url: url,
            text: text,
            imageBase64: imageBase64,
            filename: filename,
            mimeType: mimeType,
            source: share.source
        )
    }

    private func normalizedLink(_ url: URL) -> String? {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return nil
        }
        guard !url.isFileURL else { return nil }
        let absolute = url.absoluteString.trimmingCharacters(in: .whitespacesAndNewlines)
        return absolute.isEmpty ? nil : absolute
    }

    private func limited(_ value: String?, maxCharacters: Int) throws -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard trimmed.count <= maxCharacters else {
            throw PayloadError.tooLarge(limit: maxCharacters)
        }
        return trimmed
    }

    private func textualBody(_ file: ShareBinary?) throws -> String? {
        guard let file else { return nil }
        guard MimeTypes.isText(mimeType: file.mimeType, filename: file.filename) else { return nil }
        if file.data.count > limits.maxFileBytes {
            throw PayloadError.tooLarge(limit: limits.maxFileBytes)
        }
        guard let decoded = String(data: file.data, encoding: .utf8) else {
            throw PayloadError.unreadable
        }
        return try limited(decoded, maxCharacters: limits.maxTextCharacters)
    }

    private func cleanedFilename(_ filename: String?) -> String? {
        guard let filename else { return nil }
        let trimmed = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

enum MimeTypes {
    static func isText(mimeType: String?, filename: String?) -> Bool {
        let mime = mimeType?.lowercased() ?? ""
        if mime.hasPrefix("text/") || mime == "application/json" || mime == "application/xml" {
            return true
        }
        switch extensionOf(filename) {
        case "txt", "md", "markdown", "json", "xml", "csv", "html", "css":
            return mime.isEmpty || mime.hasPrefix("text/") || mime == "application/json" || mime == "application/xml"
        default:
            return false
        }
    }

    static func from(filename: String) -> String? {
        switch extensionOf(filename) {
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "heic": return "image/heic"
        case "tif", "tiff": return "image/tiff"
        case "webp": return "image/webp"
        case "bmp": return "image/bmp"
        case "txt": return "text/plain"
        case "md", "markdown": return "text/markdown"
        case "json": return "application/json"
        case "pdf": return "application/pdf"
        case "zip": return "application/zip"
        default: return nil
        }
    }

    private static func extensionOf(_ filename: String?) -> String {
        guard let filename else { return "" }
        return URL(fileURLWithPath: filename).pathExtension.lowercased()
    }
}
