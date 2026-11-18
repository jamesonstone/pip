import PipCore
import SwiftUI

@MainActor
final class SettingsModel: ObservableObject {
    @Published var destinations: [IntakeDestination] = []
    @Published var editingID: UUID?
    @Published var name = ""
    @Published var webhookURL = ""
    @Published var token = ""
    @Published var status: String?
    @Published var isSaving = false
    @Published var pendingRemoval: IntakeDestination?

    private let store = PipRuntime.store()

    func load() {
        do {
            let book = try store.loadBook()
            apply(book)
            if let preferred = book.preferred {
                beginEdit(preferred)
            } else {
                beginNew()
            }
        } catch CredentialError.malformedRecord {
            destinations = []
            beginNew()
            status = "The saved bots could not be read. Save them again."
        } catch {
            status = message(for: error)
        }
    }

    func beginNew() {
        editingID = nil
        name = ""
        webhookURL = ""
        token = ""
        status = nil
    }

    func beginEdit(_ destination: IntakeDestination) {
        editingID = destination.id
        name = destination.name
        webhookURL = destination.webhookURL.absoluteString
        token = destination.bearerToken
        status = nil
    }

    func save() {
        isSaving = true
        defer { isSaving = false }
        guard case let .success(cleanName) = DestinationRules.normalizedName(name) else {
            status = message(for: CredentialError.invalidName)
            return
        }
        switch CredentialRules.make(webhookURL: webhookURL, bearerToken: token) {
        case let .success(credentials):
            do {
                var book = try store.loadBook()
                let id = editingID ?? UUID()
                let destination = IntakeDestination(
                    id: id,
                    name: cleanName,
                    webhookURL: credentials.webhookURL,
                    bearerToken: credentials.bearerToken
                )
                if let index = book.destinations.firstIndex(where: { $0.id == id }) {
                    book.destinations[index] = destination
                } else {
                    book.destinations.append(destination)
                }
                if book.lastUsedID == nil {
                    book.lastUsedID = id
                }
                try store.save(book)
                name = cleanName
                webhookURL = credentials.webhookURL.absoluteString
                token = credentials.bearerToken
                editingID = id
                apply(book)
                status = StatusCopy.saved
            } catch {
                status = message(for: error)
            }
        case let .failure(error):
            status = message(for: error)
        }
    }

    func confirmRemove(_ pending: IntakeDestination) {
        do {
            var book = try store.loadBook()
            book.destinations.removeAll { $0.id == pending.id }
            if book.lastUsedID == pending.id {
                book.lastUsedID = book.destinations.first?.id
            }
            try store.save(book)
            pendingRemoval = nil
            apply(book)
            if let preferred = book.preferred {
                beginEdit(preferred)
            } else {
                beginNew()
            }
            status = "Removed \(pending.name)."
        } catch {
            status = message(for: error)
        }
    }

    private func apply(_ book: DestinationBook) {
        destinations = book.destinations
    }

    private func message(for error: Error) -> String {
        switch error {
        case CredentialError.invalidWebhookURL:
            return "Pip only carries https webhooks."
        case CredentialError.emptyToken:
            return "The key is empty."
        case CredentialError.invalidName:
            return "Give the bot a name, up to 40 characters, with no @ at the start."
        case CredentialError.duplicateName:
            return "That name is already a bot."
        case CredentialError.malformedRecord:
            return "The saved bots could not be read. Save them again."
        case KeychainError.missingEntitlement:
            return "Turn on Keychain Sharing for this team, then try again."
        default:
            return StatusCopy.tripped
        }
    }
}
