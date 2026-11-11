import XCTest
@testable import PipCore

#if canImport(ImageIO) && canImport(CoreGraphics)
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

final class ImageIOEncoderTests: XCTestCase {
    func testLargeImageShrinksUnderTheCap() throws {
        let png = try pngData(width: 2400, height: 1800)
        let encoded = try ImageIOEncoder(maxDimension: 1600, maxBytes: 750_000)
            .encodeJPEG(data: png, preferredFilename: "Vacation Photo.HEIC")
        let jpeg = try XCTUnwrap(Data(base64Encoded: encoded.base64))
        XCTAssertLessThanOrEqual(jpeg.count, 750_000)
        XCTAssertEqual(Array(jpeg.prefix(2)), [0xFF, 0xD8])
        XCTAssertEqual(encoded.mimeType, "image/jpeg")
        XCTAssertEqual(encoded.filename, "Vacation Photo.jpg")

        let source = try XCTUnwrap(CGImageSourceCreateWithData(jpeg as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertLessThanOrEqual(max(image.width, image.height), 1600)
        XCTAssertGreaterThan(image.width, 0)
    }

    func testGarbageIsUnreadable() {
        XCTAssertThrowsError(try ImageIOEncoder().encodeJPEG(data: Data("nope".utf8), preferredFilename: nil)) { error in
            XCTAssertEqual(error as? PayloadError, .unreadable)
        }
    }

    private func pngData(width: Int, height: Int) throws -> Data {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            XCTFail("could not draw")
            return Data()
        }
        context.setFillColor(CGColor(red: 0.15, green: 0.45, blue: 0.85, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let image = context.makeImage() else {
            XCTFail("could not read the bitmap")
            return Data()
        }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            XCTFail("could not encode png")
            return Data()
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            XCTFail("could not finish png")
            return Data()
        }
        return data as Data
    }
}
#endif
