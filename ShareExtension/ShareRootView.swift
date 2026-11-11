import PipCore
import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

struct ShareRootView: View {
    let context: NSExtensionContext?
    @StateObject private var session = ShareSession()

    var body: some View {
        ZStack {
            PipPalette.background.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    PipWordmark(subtitle: session.subtitle)
                    Spacer()
                    Button("Close", action: session.close)
                        .font(.callout)
                        .foregroundStyle(PipPalette.muted)
                        .frame(minWidth: 44, minHeight: 44)
                        .accessibilityLabel("Close")
                }
                if let preview = session.previewImage {
                    preview
                        .resizable()
                        .scaledToFill()
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .accessibilityHidden(true)
                }
                if session.canCompose {
                    TextField("Add a note", text: $session.note, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(3, reservesSpace: true)
                        .padding(12)
                        .background(PipPalette.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .accessibilityLabel("Note")
                    Button(action: session.send) {
                        if session.isSending {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("Send")
                        }
                    }
                    .buttonStyle(PipButtonStyle())
                    .disabled(session.isSending)
                }
                if let status = session.status {
                    Text(status)
                        .font(.callout)
                        .foregroundStyle(PipPalette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel(status)
                }
                Spacer(minLength: 0)
            }
            .padding(22)
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .preferredColorScheme(.dark)
        .task { await session.load(from: context) }
    }
}

@MainActor
final class ShareSession: ObservableObject {
    @Published var note = ""
    @Published var subtitle = StatusCopy.gathering
    @Published var status: String?
    @Published var previewImage: Image?
    @Published var canCompose = false
    @Published var isSending = false

    private var share: InboundShare?
    private var context: NSExtensionContext?
    private var sendTask: Task<Void, Never>?
    private let store = PipRuntime.store()
    private let extractor = ShareExtractor()
    private let builder = PayloadBuilder(images: ImageIOEncoder())
    private let client = WebhookClient()

    func load(from context: NSExtensionContext?) async {
        self.context = context
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
            status = nil
        } catch {
            canCompose = false
            status = describe(error)
            subtitle = "Pip"
        }
    }

    func send() {
        guard !isSending, let share else { return }
        isSending = true
        status = StatusCopy.sending
        sendTask?.cancel()
        sendTask = Task { [note] in
            await deliver(share, note: note)
        }
    }

    func close() {
        sendTask?.cancel()
        context?.cancelRequest(withError: NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError))
    }

    private func deliver(_ share: InboundShare, note: String) async {
        defer { isSending = false }
        do {
            guard let credentials = try store.load() else {
                status = StatusCopy.needsWebhook
                return
            }
            var parcel = share
            parcel.note = note
            let payload = try builder.build(parcel)
            try await client.send(payload, using: credentials)
            guard !Task.isCancelled else { return }
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
        case CredentialError.malformedRecord, CredentialError.invalidWebhookURL, CredentialError.emptyToken:
            return StatusCopy.needsWebhook
        default:
            return StatusCopy.tripped
        }
    }
}
