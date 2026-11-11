import Foundation
import PipCore

struct ExtensionAttachment: ShareProviding {
    let provider: NSItemProvider

    var suggestedName: String? { provider.suggestedName }

    func contains(_ typeIdentifier: String) -> Bool {
        provider.hasItemConformingToTypeIdentifier(typeIdentifier)
    }

    func loadData(typeIdentifier: String) async throws -> Data {
        if typeIdentifier == ShareType.image {
            // loadDataRepresentation can archive an NSImage instead of returning image bytes.
            return try ShareImageDecoder.decode(await loadItem(typeIdentifier))
        }
        return try await withCheckedThrowingContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let data else {
                    continuation.resume(throwing: PayloadError.unreadable)
                    return
                }
                continuation.resume(returning: data)
            }
        }
    }

    func loadText(typeIdentifier: String) async throws -> String {
        let item = try await loadItem(typeIdentifier)
        if let text = item as? String { return text }
        if let data = item as? Data, let text = String(data: data, encoding: .utf8) { return text }
        throw PayloadError.unreadable
    }

    func loadURL(typeIdentifier: String) async throws -> URL {
        let item = try await loadItem(typeIdentifier)
        return try ShareURLDecoder.decode(item)
    }

    private func loadItem(_ typeIdentifier: String) async throws -> NSSecureCoding {
        return try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let item else {
                    continuation.resume(throwing: PayloadError.unreadable)
                    return
                }
                continuation.resume(returning: item)
            }
        }
    }
}
