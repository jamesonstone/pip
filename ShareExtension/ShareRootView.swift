import PipCore
import SwiftUI

final class ShareFocusTrigger: ObservableObject {
    @Published var ready: Bool

    init(ready: Bool = false) {
        self.ready = ready
    }
}

private struct ShareHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct ShareRootView: View {
    let context: NSExtensionContext?
    var onContentHeight: (CGFloat) -> Void
    @ObservedObject var focusTrigger: ShareFocusTrigger
    @StateObject private var session = ShareSession()
    @FocusState private var noteFocused: Bool
    #if os(macOS)
    @State private var botMenuHover = false
    @FocusState private var botMenuFocused: Bool
    #endif

    init(
        context: NSExtensionContext?,
        onContentHeight: @escaping (CGFloat) -> Void = { _ in },
        focusTrigger: ShareFocusTrigger? = nil
    ) {
        self.context = context
        self.onContentHeight = onContentHeight
        _focusTrigger = ObservedObject(wrappedValue: focusTrigger ?? ShareFocusTrigger(ready: true))
    }

    @ViewBuilder
    var body: some View {
        #if os(macOS)
        chrome.onExitCommand { session.close() }
        #else
        chrome
        #endif
    }

    private var chrome: some View {
        measured
            .background(PipPalette.background.ignoresSafeArea())
            .preferredColorScheme(.dark)
            .onPreferenceChange(ShareHeightKey.self) { height in
                guard height > 1 else { return }
                onContentHeight(height)
            }
            .task { await session.load(from: context) }
            .onChange(of: session.canCompose) { _, compose in
                focusNote(compose)
            }
            .onChange(of: focusTrigger.ready) { _, _ in
                focusNote(session.canCompose)
            }
    }

    @ViewBuilder
    private var measured: some View {
        #if os(macOS)
        sheet.frame(width: 400).fixedSize(horizontal: true, vertical: true)
        #else
        sheet.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        #endif
    }

    private var sheet: some View {
        VStack(spacing: 0) {
            PipHairline(playful: true)
            fields
        }
        .background {
            GeometryReader { proxy in
                Color.clear.preference(key: ShareHeightKey.self, value: proxy.size.height)
            }
        }
    }

    private var fields: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if let preview = session.previewImage {
                preview
                    .resizable()
                    .scaledToFill()
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityHidden(true)
            }
            if session.canCompose {
                botPicker
                noteField
                sendButton
            }
            if let status = session.status {
                Text(status)
                    .font(.callout)
                    .foregroundStyle(PipPalette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(status)
            }
            #if !os(macOS)
            Spacer(minLength: 0)
            #endif
        }
        .padding(20)
        .frame(maxWidth: 400, alignment: .leading)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "sparkles")
                .font(.title3)
                .foregroundStyle(PipPalette.coral)
                .frame(width: 44, height: 44)
                .background(
                    LinearGradient(colors: [PipPalette.iris, PipPalette.accent.opacity(0.85)], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
                .accessibilityHidden(true)
            PipWordmark(subtitle: session.subtitle)
            Spacer(minLength: 0)
            Button("Close", action: session.close)
                .font(.callout)
                .foregroundStyle(PipPalette.muted)
                .frame(minWidth: 44, minHeight: 44)
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel("Close")
        }
    }

    private var botPicker: some View {
        let choice = session.choice
        let name = choice.destination?.name ?? "No bot yet"
        let appearance = BotMarks.appearance(for: choice.destination?.name ?? "")
        return VStack(alignment: .leading, spacing: 6) {
            if session.book.destinations.isEmpty {
                Label(name, systemImage: "questionmark.circle")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(PipPalette.muted)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .padding(.horizontal, 12)
                    .background(PipPalette.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityLabel("No bot yet")
            } else {
                botMenu(name: name, appearance: appearance, choice: choice)
            }
            if choice.usedPrefix, let picked = choice.destination?.name {
                Text("Note picks \(picked)")
                    .font(.footnote)
                    .foregroundStyle(PipPalette.accent)
            }
        }
    }

    @ViewBuilder
    private func botMenu(name: String, appearance: BotAppearance, choice: DestinationChoice) -> some View {
        #if os(macOS)
        // default macOS Menu draws a bordered popup and a second chevron around its label.
        // this row is the card. the menu button draws only its label, so hover is the card stroke.
        botMenuLabel(name: name, appearance: appearance)
            .accessibilityHidden(true)
            .background(PipPalette.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(botMenuHover || botMenuFocused ? 0.55 : 0), lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .overlay {
                GeometryReader { proxy in
                    Menu {
                        botMenuItems(choice: choice)
                    } label: {
                        Color.clear
                            .frame(width: proxy.size.width, height: proxy.size.height)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(ShareBotMenuButtonStyle())
                    .menuIndicator(.hidden)
                    .menuStyle(.button)
                    .focusEffectDisabled()
                    .focused($botMenuFocused)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
                    .accessibilityLabel("Bot, \(name)")
                }
            }
            .onHover { botMenuHover = $0 }
        #else
        Menu {
            botMenuItems(choice: choice)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: appearance.symbol)
                    .foregroundStyle(appearance.color)
                Text(name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(PipPalette.ink)
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(PipPalette.muted)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background(PipPalette.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .accessibilityLabel("Bot, \(name)")
        #endif
    }

    #if os(macOS)
    private func botMenuLabel(name: String, appearance: BotAppearance) -> some View {
        HStack(spacing: 8) {
            Image(systemName: appearance.symbol)
                .foregroundStyle(appearance.color)
            Text(name)
                .font(.body.weight(.semibold))
                .foregroundStyle(PipPalette.ink)
                .lineLimit(1)
            Spacer(minLength: 8)
            Image(systemName: "chevron.up.chevron.down")
                .font(.caption.weight(.semibold))
                .foregroundStyle(PipPalette.muted)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
    #endif

    @ViewBuilder
    private func botMenuItems(choice: DestinationChoice) -> some View {
        ForEach(session.book.destinations) { destination in
            Button {
                session.select(destination.id)
            } label: {
                if destination.id == choice.destination?.id {
                    Label(destination.name, systemImage: "checkmark")
                } else {
                    Text(destination.name)
                }
            }
        }
    }

    private var noteField: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "note.text")
                .foregroundStyle(PipPalette.accent)
                .padding(.top, 2)
                .accessibilityHidden(true)
            TextField("Add a note", text: $session.note, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(3, reservesSpace: true)
                .focused($noteFocused)
                .onKeyPress { press in
                    guard press.key == .return else { return .ignored }
                    if press.modifiers.contains(.shift) { return .ignored }
                    session.send()
                    return .handled
                }
                .accessibilityLabel("Note")
        }
        .padding(12)
        .background(PipPalette.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var sendButton: some View {
        Button(action: session.send) {
            if session.isSending {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white)
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "paperplane.fill")
                    Text("Send")
                }
            }
        }
        .buttonStyle(PipButtonStyle(fill: PipPalette.iris, label: .white))
        .disabled(!session.canSend)
        .keyboardShortcut(.defaultAction)
        .accessibilityLabel("Send")
    }

    private func focusNote(_ compose: Bool) {
        guard compose, focusTrigger.ready else { return }
        Task { @MainActor in
            noteFocused = true
        }
    }
}

#if os(macOS)
private struct ShareBotMenuButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}
#endif
