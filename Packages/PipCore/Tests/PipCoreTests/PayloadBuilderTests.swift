import XCTest
@testable import PipCore

final class PayloadBuilderTests: XCTestCase {
    func testURLShareUsesTheLinkField() throws {
        let payload = try builder().build(InboundShare(
            link: URL(string: "https://example.com/story")!,
            source: .ios
        ))
        XCTAssertEqual(payload.url, "https://example.com/story")
        XCTAssertNil(payload.text)
        XCTAssertNil(payload.imageBase64)
        XCTAssertEqual(payload.source, .ios)
        XCTAssertEqual(try jsonKeys(payload), ["source", "url"])
    }

    func testPlainTextLandsInTheURLField() throws {
        let payload = try builder().build(InboundShare(sharedText: "  hello pip  ", source: .macos))
        XCTAssertEqual(payload.url, "hello pip")
        XCTAssertNil(payload.text)
        XCTAssertEqual(payload.source, .macos)
    }

    func testNoteIsSeparateFromTheLink() throws {
        let payload = try builder().build(InboundShare(
            link: URL(string: "https://example.com")!,
            sharedText: "Headline",
            note: " read later ",
            source: .ios
        ))
        XCTAssertEqual(payload.url, "https://example.com")
        XCTAssertEqual(payload.text, "read later")
    }

    func testSharedTextBecomesTheNoteWhenALinkIsPresent() throws {
        let payload = try builder().build(InboundShare(
            link: URL(string: "https://example.com")!,
            sharedText: "Headline",
            source: .ios
        ))
        XCTAssertEqual(payload.text, "Headline")
    }

    func testImageUsesTheEncoderOutput() throws {
        let encoder = StaticEncoder()
        let payload = try PayloadBuilder(images: encoder).build(InboundShare(
            image: ShareBinary(data: Data("pixels".utf8), filename: "Photo.HEIC", mimeType: "image/heic"),
            source: .ios
        ))
        XCTAssertEqual(payload.imageBase64, "aW1hZ2U=")
        XCTAssertEqual(payload.filename, "Photo.jpg")
        XCTAssertEqual(payload.mimeType, "image/jpeg")
        XCTAssertEqual(encoder.seenFilename, "Photo.HEIC")
        XCTAssertEqual(try jsonKeys(payload), ["filename", "image", "source", "type"])
    }

    func testTextFileBecomesTheURLBody() throws {
        let payload = try builder().build(InboundShare(
            file: ShareBinary(data: Data("notes from today".utf8), filename: "notes.txt", mimeType: "text/plain"),
            source: .macos
        ))
        XCTAssertEqual(payload.url, "notes from today")
        XCTAssertNil(payload.imageBase64)
        XCTAssertEqual(payload.filename, "notes.txt")
        XCTAssertEqual(payload.mimeType, "text/plain")
    }

    func testBinaryFileIsBase64InTheImageSlot() throws {
        let bytes = Data([0x00, 0x01, 0x02, 0xFF])
        let payload = try builder().build(InboundShare(
            file: ShareBinary(data: bytes, filename: "clip.pdf", mimeType: "application/pdf"),
            source: .ios
        ))
        XCTAssertEqual(payload.imageBase64, bytes.base64EncodedString())
        XCTAssertEqual(payload.filename, "clip.pdf")
        XCTAssertEqual(payload.mimeType, "application/pdf")
        XCTAssertNil(payload.url)
    }

    func testOversizedFileThrows() {
        let data = Data(repeating: 1, count: 32)
        let limits = PayloadLimits(maxImageBytes: 750_000, maxFileBytes: 8, maxNoteCharacters: 20, maxTextCharacters: 20)
        XCTAssertThrowsError(try PayloadBuilder(limits: limits, images: StaticEncoder()).build(
            InboundShare(file: ShareBinary(data: data, filename: "big.bin", mimeType: "application/octet-stream"), source: .ios)
        )) { error in
            XCTAssertEqual(error as? PayloadError, .tooLarge(limit: 8))
        }
    }

    func testEmptyShareThrows() {
        XCTAssertThrowsError(try builder().build(InboundShare(source: .ios))) { error in
            XCTAssertEqual(error as? PayloadError, .empty)
        }
    }

    func testNoteOnlyIsAllowed() throws {
        let payload = try builder().build(InboundShare(note: "just a thought", source: .ios))
        XCTAssertNil(payload.url)
        XCTAssertEqual(payload.text, "just a thought")
    }

    func testBearerTokenIsNotPartOfThePayload() throws {
        let payload = try builder().build(InboundShare(sharedText: "secret-looking text", source: .ios))
        let body = try JSONEncoder.pip.encode(payload)
        let json = String(decoding: body, as: UTF8.self)
        XCTAssertFalse(json.contains("Bearer"))
        XCTAssertFalse(json.contains("Authorization"))
    }

    private func builder() -> PayloadBuilder {
        PayloadBuilder(images: StaticEncoder())
    }

    private func jsonKeys(_ payload: IntakePayload) throws -> [String] {
        let data = try JSONEncoder.pip.encode(payload)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return object?.keys.sorted() ?? []
    }
}

private final class StaticEncoder: ImageEncoding, @unchecked Sendable {
    var seenFilename: String?

    func encodeJPEG(data: Data, preferredFilename: String?) throws -> EncodedImage {
        seenFilename = preferredFilename
        let stem = URL(fileURLWithPath: preferredFilename ?? "image").deletingPathExtension().lastPathComponent
        return EncodedImage(base64: "aW1hZ2U=", filename: stem + ".jpg", mimeType: "image/jpeg")
    }
}
