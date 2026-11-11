import Foundation

#if canImport(ImageIO) && canImport(CoreGraphics)
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

public struct ImageIOEncoder: ImageEncoding {
    public var maxDimension: Int
    public var maxBytes: Int

    public init(maxDimension: Int = 1600, maxBytes: Int = PayloadLimits.standard.maxImageBytes) {
        self.maxDimension = maxDimension
        self.maxBytes = maxBytes
    }

    public func encodeJPEG(data: Data, preferredFilename: String?) throws -> EncodedImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              var image = ImageIOEncoder.thumbnail(from: source, maxPixel: maxDimension) else {
            throw PayloadError.unreadable
        }

        var quality = 0.72
        var jpeg = ImageIOEncoder.jpegData(from: image, quality: quality)
        while jpeg.count > maxBytes && quality > 0.22 {
            quality -= 0.12
            jpeg = ImageIOEncoder.jpegData(from: image, quality: quality)
        }

        var dimension = maxDimension
        while jpeg.count > maxBytes && dimension > 640 {
            dimension = max(640, dimension * 2 / 3)
            guard let smaller = ImageIOEncoder.scale(image, maxPixel: dimension) else { break }
            image = smaller
            quality = 0.62
            jpeg = ImageIOEncoder.jpegData(from: image, quality: quality)
            while jpeg.count > maxBytes && quality > 0.22 {
                quality -= 0.10
                jpeg = ImageIOEncoder.jpegData(from: image, quality: quality)
            }
        }

        guard !jpeg.isEmpty, jpeg.count <= maxBytes else {
            throw PayloadError.tooLarge(limit: maxBytes)
        }

        return EncodedImage(
            base64: jpeg.base64EncodedString(),
            filename: JPEGFilename.make(preferred: preferredFilename),
            mimeType: "image/jpeg"
        )
    }

    static func thumbnail(from source: CGImageSource, maxPixel: Int) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    static func jpegData(from image: CGImage, quality: Double) -> Data {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            return Data()
        }
        let properties = [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
        CGImageDestinationAddImage(destination, image, properties)
        guard CGImageDestinationFinalize(destination) else { return Data() }
        return output as Data
    }

    static func scale(_ image: CGImage, maxPixel: Int) -> CGImage? {
        let largest = max(image.width, image.height)
        guard largest > 0 else { return nil }
        let ratio = largest > maxPixel ? Double(maxPixel) / Double(largest) : 1
        let width = max(1, Int((Double(image.width) * ratio).rounded()))
        let height = max(1, Int((Double(image.height) * ratio).rounded()))
        let spaces = [image.colorSpace, CGColorSpaceCreateDeviceRGB()].compactMap { $0 }
        for space in spaces {
            guard let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { continue }
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            if let scaled = context.makeImage() { return scaled }
        }
        return nil
    }
}
#endif
