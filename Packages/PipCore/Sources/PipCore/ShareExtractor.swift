import Foundation

public enum ShareType {
    public static let url = "public.url"
    public static let text = "public.plain-text"
    public static let image = "public.image"
    public static let fileURL = "public.file-url"
    public static let data = "public.data"
}

public protocol ShareProviding {
    var suggestedName: String? { get }
    func contains(_ typeIdentifier: String) -> Bool
    func loadData(typeIdentifier: String) async throws -> Data
    func loadText(typeIdentifier: String) async throws -> String
    func loadURL(typeIdentifier: String) async throws -> URL
}

public struct ShareExtractor: Sendable {
    public var maxFileBytes: Int

    public init(maxFileBytes: Int = PayloadLimits.standard.maxFileBytes) {
        self.maxFileBytes = maxFileBytes
    }

    public func extract(from providers: [any ShareProviding], source: ShareSource) async throws -> InboundShare {
        var link: URL?
        var sharedText: String?
        var image: ShareBinary?
        var file: ShareBinary?

        for provider in providers {
            let isFile = provider.contains(ShareType.fileURL)
            let isWebLink = provider.contains(ShareType.url) && !isFile
            if isWebLink, link == nil {
                let url = try await provider.loadURL(typeIdentifier: ShareType.url)
                if isWebURL(url) {
                    link = url
                }
            } else if image == nil, provider.contains(ShareType.image) {
                let data = try await provider.loadData(typeIdentifier: ShareType.image)
                image = ShareBinary(data: data, filename: provider.suggestedName, mimeType: "image/*")
            } else if file == nil, image == nil, isFile {
                let url = try await provider.loadURL(typeIdentifier: ShareType.fileURL)
                file = try loadFile(at: url, suggestedName: provider.suggestedName)
            } else if file == nil, image == nil, link == nil, provider.contains(ShareType.data) {
                let data = try await provider.loadData(typeIdentifier: ShareType.data)
                if data.count > maxFileBytes {
                    throw PayloadError.tooLarge(limit: maxFileBytes)
                }
                file = ShareBinary(data: data, filename: provider.suggestedName, mimeType: nil)
            }

            if sharedText == nil, provider.contains(ShareType.text) {
                let text = try await provider.loadText(typeIdentifier: ShareType.text)
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    sharedText = trimmed
                }
            }
        }

        return InboundShare(
            link: link,
            sharedText: sharedText,
            image: image,
            file: file,
            note: nil,
            source: source
        )
    }

    private func isWebURL(_ url: URL) -> Bool {
        guard !url.isFileURL, let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    func loadFile(at url: URL, suggestedName: String?) throws -> ShareBinary {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
        if size > maxFileBytes {
            throw PayloadError.tooLarge(limit: maxFileBytes)
        }
        let data = try Data(contentsOf: url)
        if data.count > maxFileBytes {
            throw PayloadError.tooLarge(limit: maxFileBytes)
        }
        let name = suggestedName ?? url.lastPathComponent
        return ShareBinary(data: data, filename: name, mimeType: MimeTypes.from(filename: name))
    }
}
