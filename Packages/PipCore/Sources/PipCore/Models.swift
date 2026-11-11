import Foundation

public enum ShareSource: String, Codable, Equatable, Sendable {
    case ios
    case macos
}

public struct ShareBinary: Equatable, Sendable {
    public var data: Data
    public var filename: String?
    public var mimeType: String?

    public init(data: Data, filename: String?, mimeType: String?) {
        self.data = data
        self.filename = filename
        self.mimeType = mimeType
    }
}

public struct InboundShare: Equatable, Sendable {
    public var link: URL?
    public var sharedText: String?
    public var image: ShareBinary?
    public var file: ShareBinary?
    public var note: String?
    public var source: ShareSource

    public init(
        link: URL? = nil,
        sharedText: String? = nil,
        image: ShareBinary? = nil,
        file: ShareBinary? = nil,
        note: String? = nil,
        source: ShareSource
    ) {
        self.link = link
        self.sharedText = sharedText
        self.image = image
        self.file = file
        self.note = note
        self.source = source
    }
}

public struct IntakePayload: Equatable, Sendable {
    public var url: String?
    public var text: String?
    public var imageBase64: String?
    public var filename: String?
    public var mimeType: String?
    public var source: ShareSource

    public init(
        url: String?,
        text: String?,
        imageBase64: String?,
        filename: String?,
        mimeType: String?,
        source: ShareSource
    ) {
        self.url = url
        self.text = text
        self.imageBase64 = imageBase64
        self.filename = filename
        self.mimeType = mimeType
        self.source = source
    }
}

extension IntakePayload: Codable {
    enum CodingKeys: String, CodingKey {
        case url
        case text
        case image
        case filename
        case type
        case source
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(url, forKey: .url)
        try container.encodeIfPresent(text, forKey: .text)
        try container.encodeIfPresent(imageBase64, forKey: .image)
        try container.encodeIfPresent(filename, forKey: .filename)
        try container.encodeIfPresent(mimeType, forKey: .type)
        try container.encode(source, forKey: .source)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        url = try container.decodeIfPresent(String.self, forKey: .url)
        text = try container.decodeIfPresent(String.self, forKey: .text)
        imageBase64 = try container.decodeIfPresent(String.self, forKey: .image)
        filename = try container.decodeIfPresent(String.self, forKey: .filename)
        mimeType = try container.decodeIfPresent(String.self, forKey: .type)
        source = try container.decode(ShareSource.self, forKey: .source)
    }
}

public enum PayloadError: Error, Equatable, Sendable {
    case empty
    case tooLarge(limit: Int)
    case unreadable
}

public struct PayloadLimits: Equatable, Sendable {
    public var maxImageBytes: Int
    public var maxFileBytes: Int
    public var maxNoteCharacters: Int
    public var maxTextCharacters: Int

    public init(maxImageBytes: Int, maxFileBytes: Int, maxNoteCharacters: Int, maxTextCharacters: Int) {
        self.maxImageBytes = maxImageBytes
        self.maxFileBytes = maxFileBytes
        self.maxNoteCharacters = maxNoteCharacters
        self.maxTextCharacters = maxTextCharacters
    }

    public static let standard = PayloadLimits(
        maxImageBytes: 750_000,
        maxFileBytes: 750_000,
        maxNoteCharacters: 4_000,
        maxTextCharacters: 100_000
    )
}

public extension JSONEncoder {
    static var pip: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}
