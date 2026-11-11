import Foundation
import XCTest
@testable import PipCore

#if canImport(AppKit)
import AppKit
import ImageIO
import UniformTypeIdentifiers

final class ShareImageDecoderTests: XCTestCase {
    func testLargeNativeImageIsResizedBeforeIntermediateEncoding() throws {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 4032, pixelsHigh: 3024,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 4032 * 4, bitsPerPixel: 32
        ))
        let image = NSImage(size: NSSize(width: 4032, height: 3024))
        image.addRepresentation(bitmap)
        let data = try ShareImageDecoder.decode(image)
        XCTAssertLessThanOrEqual(data.count, ShareImageDecoder.maxInputBytes)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        let decoded = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(max(decoded.width, decoded.height), 1600)
    }

    func testNativeTextProviderConformsToDataWithoutBecomingBinary() async throws {
        let provider = NativeTextProvider()
        XCTAssertTrue(provider.contains(ShareType.data))
        XCTAssertTrue(provider.contains(ShareType.text))
        let share = try await ShareExtractor().extract(from: [provider], source: .macos)
        XCTAssertEqual(share.sharedText, "shared text")
        XCTAssertNil(share.file)
        XCTAssertNil(share.image)
    }

    func testLegacyImageProviderProducesEncodableImageBytes() async throws {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 8, pixelsHigh: 8,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 32, bitsPerPixel: 32
        ))
        let image = NSImage(size: NSSize(width: 8, height: 8))
        image.addRepresentation(bitmap)
        let provider = NSItemProvider(item: image, typeIdentifier: UTType.image.identifier)
        let item: NSSecureCoding = try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) { item, error in
                if let error { continuation.resume(throwing: error) }
                else if let item { continuation.resume(returning: item) }
                else { continuation.resume(throwing: PayloadError.unreadable) }
            }
        }
        let data = try ShareImageDecoder.decode(item)
        let encoded = try ImageIOEncoder().encodeJPEG(data: data, preferredFilename: "share.png")
        let jpeg = try XCTUnwrap(Data(base64Encoded: encoded.base64))
        XCTAssertEqual(Array(jpeg.prefix(2)), [0xff, 0xd8])
        XCTAssertEqual(encoded.mimeType, "image/jpeg")
    }

    func testImageFileRepresentationPreservesBytes() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let expected = Data([1, 2, 3])
        try expected.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(try ShareImageDecoder.decode(url), expected)
        XCTAssertEqual(try ShareImageDecoder.decode(expected as NSData), expected)
    }

    func testUnsupportedAndRemoteRepresentationsAreRejected() {
        for item: Any in [NSNumber(value: 42), URL(string: "https://example.test/image.png")!] {
            XCTAssertThrowsError(try ShareImageDecoder.decode(item)) {
                XCTAssertEqual($0 as? PayloadError, .unreadable)
            }
        }
    }

    func testOversizedImageDataIsRejected() {
        XCTAssertThrowsError(try ShareImageDecoder.decode(Data(repeating: 0, count: ShareImageDecoder.maxInputBytes + 1))) {
            XCTAssertEqual($0 as? PayloadError, .tooLarge(limit: ShareImageDecoder.maxInputBytes))
        }
    }
}

private struct NativeTextProvider: ShareProviding {
    let provider = NSItemProvider(item: "shared text" as NSString, typeIdentifier: UTType.utf8PlainText.identifier)
    var suggestedName: String? { nil }
    func contains(_ typeIdentifier: String) -> Bool {
        provider.hasItemConformingToTypeIdentifier(typeIdentifier)
    }
    func loadData(typeIdentifier: String) async throws -> Data { throw PayloadError.unreadable }
    func loadURL(typeIdentifier: String) async throws -> URL { throw PayloadError.unreadable }
    func loadText(typeIdentifier: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, error in
                if let error { continuation.resume(throwing: error) }
                else if let text = item as? String { continuation.resume(returning: text) }
                else if let data = item as? Data, let text = String(data: data, encoding: .utf8) {
                    continuation.resume(returning: text)
                } else { continuation.resume(throwing: PayloadError.unreadable) }
            }
        }
    }
}
#endif
