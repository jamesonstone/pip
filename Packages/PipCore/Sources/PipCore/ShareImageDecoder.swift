import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
import ImageIO
import UniformTypeIdentifiers
#endif

/// Converts the typed image objects returned by NSItemProvider.loadItem.
public enum ShareImageDecoder {
    public static let maxInputBytes = 25_000_000

    public static func decode(_ item: Any) throws -> Data {
        let data: Data
        if let bytes = item as? Data {
            data = bytes
        } else if let url = item as? URL {
            guard url.isFileURL else { throw PayloadError.unreadable }
            #if os(iOS) || os(macOS)
            let didAccess = url.startAccessingSecurityScopedResource()
            defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
            #endif
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            if let size = attributes[.size] as? NSNumber, size.intValue > maxInputBytes {
                throw PayloadError.tooLarge(limit: maxInputBytes)
            }
            data = try Data(contentsOf: url)
        } else {
            #if canImport(UIKit)
            guard let image = item as? UIImage, image.size.width > 0, image.size.height > 0 else {
                throw PayloadError.unreadable
            }
            let pixelWidth = image.size.width * image.scale
            let pixelHeight = image.size.height * image.scale
            let ratio = min(1, 1600 / max(pixelWidth, pixelHeight))
            let size = CGSize(width: max(1, pixelWidth * ratio), height: max(1, pixelHeight * ratio))
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
                image.draw(in: CGRect(origin: .zero, size: size))
            }
            guard let bytes = resized.pngData() else { throw PayloadError.unreadable }
            data = bytes
            #elseif canImport(AppKit)
            guard let image = item as? NSImage,
                  let bitmap = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
                  let resized = ImageIOEncoder.scale(bitmap, maxPixel: 1600) else {
                throw PayloadError.unreadable
            }
            let output = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else {
                throw PayloadError.unreadable
            }
            CGImageDestinationAddImage(destination, resized, nil)
            guard CGImageDestinationFinalize(destination) else { throw PayloadError.unreadable }
            data = output as Data
            #else
            throw PayloadError.unreadable
            #endif
        }
        guard data.count <= maxInputBytes else {
            throw PayloadError.tooLarge(limit: maxInputBytes)
        }
        return data
    }
}
