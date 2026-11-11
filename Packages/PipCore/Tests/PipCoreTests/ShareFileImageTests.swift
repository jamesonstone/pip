import Foundation
import XCTest
@testable import PipCore

#if canImport(ImageIO) && canImport(CoreGraphics)
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

final class ShareFileImageTests: XCTestCase {
    func testImageFileInputLimitIsEnforced() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).png")
        try Data(repeating: 1, count: 33).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        do {
            _ = try await ShareExtractor(maxImageInputBytes: 32)
                .extract(from: [FileURLProvider(url: url)], source: .macos)
            XCTFail("expected the input image to exceed the cap")
        } catch let error as PayloadError {
            XCTAssertEqual(error, .tooLarge(limit: 32))
        }
    }

    func testLargePNGFileURLIsCompressedAsAnImage() async throws {
        let data = try noisyPNG()
        XCTAssertGreaterThan(data.count, PayloadLimits.standard.maxFileBytes)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pip-image-\(UUID().uuidString).png")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let share = try await ShareExtractor().extract(from: [FileURLProvider(url: url)], source: .macos)
        XCTAssertNotNil(share.image)
        XCTAssertNil(share.file)
        let payload = try PayloadBuilder(images: ImageIOEncoder()).build(share)
        XCTAssertEqual(payload.mimeType, "image/jpeg")
        let encoded = try XCTUnwrap(payload.imageBase64)
        let jpeg = try XCTUnwrap(Data(base64Encoded: encoded))
        XCTAssertLessThanOrEqual(jpeg.count, PayloadLimits.standard.maxImageBytes)
        XCTAssertEqual(Array(jpeg.prefix(2)), [0xff, 0xd8])
    }

    private func noisyPNG() throws -> Data {
        let width = 1024
        let height = 1024
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        var seed: UInt32 = 42
        for index in bytes.indices {
            seed = seed &* 1_664_525 &+ 1_013_904_223
            bytes[index] = index % 4 == 3 ? 255 : UInt8(truncatingIfNeeded: seed >> 24)
        }
        let provider = try XCTUnwrap(CGDataProvider(data: Data(bytes) as CFData))
        let image = try XCTUnwrap(CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        ))
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(
            data, UTType.png.identifier as CFString, 1, nil
        ))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }
}

private struct FileURLProvider: ShareProviding {
    let url: URL
    var suggestedName: String? { nil }
    func contains(_ typeIdentifier: String) -> Bool {
        typeIdentifier == ShareType.fileURL || typeIdentifier == ShareType.url
    }
    func loadURL(typeIdentifier: String) async throws -> URL { url }
    func loadData(typeIdentifier: String) async throws -> Data { throw PayloadError.unreadable }
    func loadText(typeIdentifier: String) async throws -> String { throw PayloadError.unreadable }
}
#endif
