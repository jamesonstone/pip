import PipCore
import SwiftUI

struct SettingsScreen: View {
    @StateObject private var model = SettingsModel()

    var body: some View {
        ZStack {
            PipPalette.background.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 22) {
                PipWordmark(subtitle: "Where should Pip deliver?")
                VStack(alignment: .leading, spacing: 8) {
                    Text("Webhook URL")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(PipPalette.muted)
                    TextField("https://", text: $model.webhookURL)
                        .textFieldStyle(.plain)
                        .textContentType(.URL)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        #endif
                        .padding(12)
                        .frame(minHeight: 44)
                        .background(PipPalette.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .accessibilityLabel("Webhook URL")
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Key")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(PipPalette.muted)
                    SecureField("Bearer token", text: $model.token)
                        .textFieldStyle(.plain)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                        .padding(12)
                        .frame(minHeight: 44)
                        .background(PipPalette.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .accessibilityLabel("Bearer token")
                }
                Button("Save", action: model.save)
                    .buttonStyle(PipButtonStyle())
                    .disabled(model.isSaving)
                if let status = model.status {
                    Text(status)
                        .font(.callout)
                        .foregroundStyle(PipPalette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Text("Kept in the Keychain on this device. The share extension reads the same item.")
                    .font(.footnote)
                    .foregroundStyle(PipPalette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(24)
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .preferredColorScheme(.dark)
        .task { model.load() }
    }
}

@MainActor
final class SettingsModel: ObservableObject {
    @Published var webhookURL = ""
    @Published var token = ""
    @Published var status: String?
    @Published var isSaving = false

    private let store = PipRuntime.store()

    func load() {
        do {
            guard let saved = try store.load() else { return }
            webhookURL = saved.webhookURL.absoluteString
            token = saved.bearerToken
        } catch CredentialError.malformedRecord {
            status = "The saved key could not be read. Save it again."
        } catch {
            status = StatusCopy.tripped
        }
    }

    func save() {
        isSaving = true
        defer { isSaving = false }
        switch CredentialRules.make(webhookURL: webhookURL, bearerToken: token) {
        case let .success(credentials):
            do {
                try store.save(credentials)
                token = credentials.bearerToken
                webhookURL = credentials.webhookURL.absoluteString
                status = StatusCopy.saved
            } catch {
                status = message(for: error)
            }
        case let .failure(error):
            status = message(for: error)
        }
    }

    private func message(for error: Error) -> String {
        switch error {
        case CredentialError.invalidWebhookURL:
            return "Pip only carries https webhooks."
        case CredentialError.emptyToken:
            return "The key is empty."
        case KeychainError.missingEntitlement:
            return "Turn on Keychain Sharing for this team, then try again."
        default:
            return StatusCopy.tripped
        }
    }
}
