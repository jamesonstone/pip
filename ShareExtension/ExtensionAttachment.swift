import Foundation
import PipCore

struct ExtensionAttachment: ShareProviding {
    let provider: NSItemProvider

    var suggestedName: String? { provider.suggestedName }

    func contains(_ typeIdentifier: String) -> Bool {
        provider.hasItemConformingToTypeIdentifier(typeIdentifier)
    }

    func loadData(typeIdentifier: String) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
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
        if let url = item as? URL { return url }
        if let text = item as? String, let url = URL(string: text) { return url }
        throw PayloadError.unreadable
    }

    private func loadItem(_ typeIdentifier: String) async throws -> NSSecureCoding {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let item = item as? NSSecureCoding else {
                    continuation.resume(throwing: PayloadError.unreadable)
                    return
                }
                continuation.resume(returning: item)
            }
        }
    }
}
