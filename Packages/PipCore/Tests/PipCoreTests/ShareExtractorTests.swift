import XCTest
@testable import PipCore

final class ShareExtractorTests: XCTestCase {
    func testTextConformingToDataDoesNotLoadBinaryRepresentation() async throws {
        let provider = FakeProvider(items: [
            ShareType.text: .text("shared text"),
            ShareType.data: .text("not a binary representation"),
        ])
        let share = try await ShareExtractor().extract(from: [provider], source: .macos)
        XCTAssertEqual(share.sharedText, "shared text")
        XCTAssertNil(share.file)
        XCTAssertNil(share.image)
    }

    func testInlineSelectedTextWithoutAttachments() async throws {
        let share = try await ShareExtractor().extract(
            from: [], source: .macos, fallbackText: "  Pip selected text\n"
        )
        let payload = try PayloadBuilder(images: UnexpectedImageEncoder()).build(share)
        XCTAssertEqual(payload.url, "Pip selected text")
        XCTAssertEqual(share.sharedText, "Pip selected text")
    }

    func testAttachmentTextTakesPrecedenceOverInlineText() async throws {
        let provider = FakeProvider(items: [ShareType.text: .text("attachment text")])
        let share = try await ShareExtractor().extract(
            from: [provider], source: .macos, fallbackText: "inline text"
        )
        XCTAssertEqual(share.sharedText, "attachment text")
    }

    func testBlankInlineTextDoesNotInventContent() async throws {
        let share = try await ShareExtractor().extract(
            from: [], source: .macos, fallbackText: " \n "
        )
        XCTAssertNil(share.sharedText)
    }

    func testLinkAndText() async throws {
        let provider = FakeProvider(items: [
            ShareType.url: .url(URL(string: "https://example.com/a")!),
            ShareType.text: .text("A title"),
        ])
        let share = try await ShareExtractor().extract(from: [provider], source: .ios)
        XCTAssertEqual(share.link?.absoluteString, "https://example.com/a")
        XCTAssertEqual(share.sharedText, "A title")
        XCTAssertNil(share.image)
        XCTAssertEqual(share.source, .ios)
    }

    func testImageIsPreferredOverASiblingFile() async throws {
        let provider = FakeProvider(
            items: [
                ShareType.image: .data(Data("img".utf8)),
                ShareType.fileURL: .url(URL(fileURLWithPath: "/tmp/ignored.jpg")),
            ],
            suggestedName: "shot.png"
        )
        let share = try await ShareExtractor().extract(from: [provider], source: .macos)
        XCTAssertEqual(share.image?.data, Data("img".utf8))
        XCTAssertEqual(share.image?.filename, "shot.png")
        XCTAssertNil(share.file)
        XCTAssertNil(share.link)
    }

    func testFileURLIsNotTreatedAsALink() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("pip-note-\(UUID().uuidString).txt")
        try Data("carry me".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let provider = FakeProvider(items: [
            ShareType.fileURL: .url(url),
            ShareType.url: .url(url),
        ])
        let share = try await ShareExtractor().extract(from: [provider], source: .ios)
        XCTAssertNil(share.link)
        XCTAssertEqual(share.file?.data, Data("carry me".utf8))
        XCTAssertEqual(share.file?.filename, url.lastPathComponent)
        XCTAssertEqual(share.file?.mimeType, "text/plain")
    }

    func testOversizedFileThrows() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("pip-big-\(UUID().uuidString).bin")
        try Data(repeating: 7, count: 32).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let provider = FakeProvider(items: [ShareType.fileURL: .url(url)])
        do {
            _ = try await ShareExtractor(maxFileBytes: 8).extract(from: [provider], source: .macos)
            XCTFail("expected the file to be too large")
        } catch let error as PayloadError {
            XCTAssertEqual(error, .tooLarge(limit: 8))
        }
    }
}

private final class FakeProvider: ShareProviding {
    enum Item {
        case data(Data)
        case text(String)
        case url(URL)
    }

    var suggestedName: String?
    var items: [String: Item]

    init(items: [String: Item], suggestedName: String? = nil) {
        self.items = items
        self.suggestedName = suggestedName
    }

    func contains(_ typeIdentifier: String) -> Bool {
        items[typeIdentifier] != nil
    }

    func loadData(typeIdentifier: String) async throws -> Data {
        guard case let .data(data) = items[typeIdentifier] else { throw PayloadError.unreadable }
        return data
    }

    func loadText(typeIdentifier: String) async throws -> String {
        guard case let .text(text) = items[typeIdentifier] else { throw PayloadError.unreadable }
        return text
    }

    func loadURL(typeIdentifier: String) async throws -> URL {
        guard case let .url(url) = items[typeIdentifier] else { throw PayloadError.unreadable }
        return url
    }
}
