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

    init(
        context: NSExtensionContext?,
        onContentHeight: @escaping (CGFloat) -> Void = { _ in },
        focusTrigger: ShareFocusTrigger? = nil
    ) {
        self.context = context
        self.onContentHeight = onContentHeight
        _focusTrigger = ObservedObject(wrappedValue: focusTrigger ?? ShareFocusTrigger(ready: true))
    }

    var body: some View {
        measured
            .background(PipPalette.background.ignoresSafeArea())
            .preferredColorScheme(.dark)
            .onExitCommand { session.close() }
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
                Menu {
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
            }
            if choice.usedPrefix, let picked = choice.destination?.name {
                Text("Note picks \(picked)")
                    .font(.footnote)
                    .foregroundStyle(PipPalette.accent)
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
                .onKeyPress(.return) { press in
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
        noteFocused = true
    }
}
