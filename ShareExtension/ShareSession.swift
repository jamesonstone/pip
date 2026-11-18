import PipCore
import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

@MainActor
final class ShareSession: ObservableObject {
    @Published var note = ""
    @Published var subtitle = StatusCopy.gathering
    @Published var status: String?
    @Published var previewImage: Image?
    @Published var canCompose = false
    @Published var isSending = false
    @Published var book = DestinationBook(destinations: [], lastUsedID: nil)
    @Published var selectedID: UUID?

    private var share: InboundShare?
    private var context: NSExtensionContext?
    private var sendTask: Task<Void, Never>?
    private let store = PipRuntime.store()
    private let extractor = ShareExtractor()
    private let builder = PayloadBuilder(images: ImageIOEncoder())
    private let client = WebhookClient()

    var choice: DestinationChoice {
        book.choice(for: note, selectedID: selectedID)
    }

    var canSend: Bool {
        canCompose && !isSending && choice.destination != nil
    }

    func load(from context: NSExtensionContext?) async {
        self.context = context
        do {
            book = try store.loadBook()
            selectedID = book.preferred?.id
        } catch {
            book = DestinationBook(destinations: [], lastUsedID: nil)
            canCompose = false
            status = describe(error)
            subtitle = "Pip"
            return
        }

        let items = context?.inputItems as? [NSExtensionItem] ?? []
        let inlineText = items.compactMap { $0.attributedContentText?.string }.joined(separator: "\n")
        let providers = items
            .flatMap { $0.attachments ?? [] }
            .map { ExtensionAttachment(provider: $0) }
        do {
            let loaded = try await extractor.extract(
                from: providers, source: PipRuntime.source, fallbackText: inlineText
            )
            share = loaded
            subtitle = preview(for: loaded)
            previewImage = thumbnail(for: loaded.image?.data)
            canCompose = true
            status = book.destinations.isEmpty ? StatusCopy.needsWebhook : nil
        } catch {
            canCompose = false
            status = describe(error)
            subtitle = "Pip"
        }
    }

    func select(_ id: UUID) {
        let current = book.choice(for: note, selectedID: selectedID)
        if current.usedPrefix, current.destination?.id != id {
            note = current.note
        }
        selectedID = id
    }

    func send() {
        guard !isSending, canCompose, let share else { return }
        let current = book.choice(for: note, selectedID: selectedID)
        guard let destination = current.destination else {
            status = StatusCopy.needsWebhook
            return
        }
        isSending = true
        status = StatusCopy.sending
        sendTask?.cancel()
        let deliveredNote = current.note
        let credentials = destination.credentials
        let destinationID = destination.id
        sendTask = Task {
            await deliver(share, note: deliveredNote, credentials: credentials, destinationID: destinationID)
        }
    }

    func close() {
        sendTask?.cancel()
        context?.cancelRequest(withError: NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError))
    }

    private func deliver(
        _ share: InboundShare,
        note: String,
        credentials: IntakeCredentials,
        destinationID: UUID
    ) async {
        defer { isSending = false }
        do {
            var parcel = share
            parcel.note = note
            let payload = try builder.build(parcel)
            try await client.send(payload, using: credentials)
            guard !Task.isCancelled else { return }
            try? store.rememberLastUsed(destinationID)
            canCompose = false
            status = StatusCopy.delivered
            subtitle = "Sent"
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard !Task.isCancelled else { return }
            context?.completeRequest(returningItems: [], completionHandler: nil)
        } catch {
            guard !Task.isCancelled else { return }
            status = describe(error)
        }
    }

    private func preview(for share: InboundShare) -> String {
        if let host = share.link?.host, !host.isEmpty { return host }
        if share.sharedText != nil { return "Text" }
        if let name = share.image?.filename ?? share.file?.filename, !name.isEmpty { return name }
        if share.image != nil { return "Image" }
        if share.file != nil { return "File" }
        return "Ready"
    }

    private func thumbnail(for data: Data?) -> Image? {
        guard let data else { return nil }
        #if os(iOS)
        guard let image = UIImage(data: data) else { return nil }
        return Image(uiImage: image)
        #else
        guard let image = NSImage(data: data) else { return nil }
        return Image(nsImage: image)
        #endif
    }

    private func describe(_ error: Error) -> String {
        switch error {
        case PayloadError.empty:
            return StatusCopy.empty
        case PayloadError.tooLarge:
            return StatusCopy.tooHeavy
        case WebhookError.rejected(let status):
            return "\(StatusCopy.tripped)\nThe webhook answered \(status)."
        case KeychainError.missingEntitlement:
            return "Turn on Keychain Sharing for this team, then try again."
        case CredentialError.malformedRecord:
            return "The saved bots could not be read. Open Pip and save them again."
        case CredentialError.invalidWebhookURL, CredentialError.emptyToken,
             CredentialError.invalidName, CredentialError.duplicateName:
            return StatusCopy.needsWebhook
        default:
            return StatusCopy.tripped
        }
    }
}
