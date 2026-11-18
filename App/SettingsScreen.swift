import PipCore
import SwiftUI

struct SettingsScreen: View {
    @StateObject private var model = SettingsModel()

    var body: some View {
        VStack(spacing: 0) {
            PipHairline(playful: false)
            screen
        }
        .background(PipPalette.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .confirmationDialog(
            "Remove \(model.pendingRemoval?.name ?? "this bot")?",
            isPresented: removalPresented,
            titleVisibility: .visible
        ) {
            if let pending = model.pendingRemoval {
                Button("Remove", role: .destructive) { model.confirmRemove(pending) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Pip deletes this bot's URL and key from the Keychain. You cannot undo that.")
        }
        .task { model.load() }
    }

    private var removalPresented: Binding<Bool> {
        Binding(
            get: { model.pendingRemoval != nil },
            set: { if !$0 { model.pendingRemoval = nil } }
        )
    }

    @ViewBuilder
    private var screen: some View {
        #if os(macOS)
        form.padding(24).frame(width: 420).fixedSize(horizontal: true, vertical: true)
        #else
        ScrollView {
            form.padding(24).frame(maxWidth: 480).frame(maxWidth: .infinity)
        }
        #endif
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.title3)
                    .foregroundStyle(PipPalette.accent)
                    .frame(width: 44, height: 44)
                    .background(PipPalette.iris.opacity(0.45), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .accessibilityHidden(true)
                PipWordmark(subtitle: "Which bots can Pip reach?")
            }
            if !model.destinations.isEmpty {
                VStack(spacing: 8) {
                    ForEach(model.destinations) { destination in
                        botRow(destination)
                    }
                }
            }
            PipLabeledField(title: "Name", symbol: "person", info: FieldHelp.name) {
                TextField("Work Bot", text: $model.name)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.words)
                    #endif
                    .accessibilityLabel("Bot name")
            }
            PipLabeledField(title: "Webhook URL", symbol: "link", info: FieldHelp.webhookURL) {
                TextField("https://", text: $model.webhookURL)
                    .textContentType(.URL)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    #endif
                    .accessibilityLabel("Webhook URL")
            }
            PipLabeledField(title: "Key", symbol: "key", info: FieldHelp.key) {
                SecureField("Bearer token", text: $model.token)
                    .textContentType(.password)
                    .autocorrectionDisabled()
                    .accessibilityLabel("Bearer token")
            }
            Button("Save", action: model.save)
                .buttonStyle(PipButtonStyle(fill: PipPalette.iris, label: .white))
                .disabled(model.isSaving)
            if model.editingID != nil || !model.destinations.isEmpty {
                HStack(spacing: 10) {
                    Button("New bot", action: model.beginNew)
                        .buttonStyle(PipButtonStyle(prominent: false))
                    if model.editingID != nil {
                        Button("Remove") { model.pendingRemoval = model.destinations.first { $0.id == model.editingID } }
                            .buttonStyle(PipButtonStyle(prominent: false))
                    }
                }
            }
            if let status = model.status {
                Text(status)
                    .font(.callout)
                    .foregroundStyle(PipPalette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Kept in the Keychain on this device. The share extension reads the same item.")
                .font(.footnote)
                .foregroundStyle(PipPalette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func botRow(_ destination: IntakeDestination) -> some View {
        let appearance = BotMarks.appearance(for: destination.name)
        let selected = destination.id == model.editingID
        return Button {
            model.beginEdit(destination)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: appearance.symbol)
                    .foregroundStyle(appearance.color)
                    .frame(width: 22)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(destination.name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(PipPalette.ink)
                    Text(destination.webhookURL.host ?? destination.webhookURL.absoluteString)
                        .font(.footnote)
                        .foregroundStyle(PipPalette.muted)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if selected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(PipPalette.accent)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background(PipPalette.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                if selected {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(PipPalette.accent.opacity(0.8), lineWidth: 1)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(destination.name), \(destination.webhookURL.host ?? "webhook")")
        .accessibilityAddTraits(selected ? .isSelected : AccessibilityTraits())
    }
}
