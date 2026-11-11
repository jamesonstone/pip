import Foundation
@testable import PipCore

/// Text and URL tests must not invoke image encoding, including on Linux.
struct UnexpectedImageEncoder: ImageEncoding {
    func encodeJPEG(data: Data, preferredFilename: String?) throws -> EncodedImage {
        throw PayloadError.unreadable
    }
}
