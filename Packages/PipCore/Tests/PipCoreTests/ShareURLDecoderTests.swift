import Foundation
import XCTest
@testable import PipCore

final class ShareURLDecoderTests: XCTestCase {
    func testNativeURLAndStringRepresentations() throws {
        let expected = URL(string: "https://example.com/path?q=hello%20world")!
        XCTAssertEqual(try ShareURLDecoder.decode(expected as NSURL), expected)
        XCTAssertEqual(try ShareURLDecoder.decode(expected.absoluteString as NSString), expected)
    }

    func testSafariDataURLSurvivesPayloadBuilding() throws {
        let expected = "https://example.com/path?q=hello%20world"
        let item = NSData(data: Data(expected.utf8))
        let link = try ShareURLDecoder.decode(item)
        let payload = try PayloadBuilder(images: UnexpectedImageEncoder()).build(InboundShare(link: link, source: .macos))
        XCTAssertEqual(payload.url, expected)
        XCTAssertEqual(payload.source, .macos)
    }

    func testFileURLDataRetainsItsFileScheme() throws {
        let expected = URL(fileURLWithPath: "/tmp/pip-test-image.png")
        XCTAssertEqual(try ShareURLDecoder.decode(Data(expected.absoluteString.utf8)), expected)
    }

    func testUnreadableRepresentationsAreRejected() {
        for item: Any in [Data([0xff, 0xfe]), NSNumber(value: 42), Data("https://[".utf8)] {
            XCTAssertThrowsError(try ShareURLDecoder.decode(item)) {
                XCTAssertEqual($0 as? PayloadError, .unreadable)
            }
        }
    }
}
