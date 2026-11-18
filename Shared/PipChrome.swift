import SwiftUI

enum PipPalette {
    static let background = Color(red: 0.07, green: 0.07, blue: 0.08)
    static let card = Color.white.opacity(0.06)
    static let ink = Color.white
    static let muted = Color.white.opacity(0.72)
    static let line = Color.white.opacity(0.14)
    static let accent = Color(red: 0.38, green: 0.78, blue: 0.98)
    static let iris = Color(red: 0.33, green: 0.27, blue: 0.78)
    static let coral = Color(red: 1.0, green: 0.55, blue: 0.62)
}

enum FieldHelp {
    static let name = "The name in the share sheet. Start a note with @Name to choose this bot. Pip removes that prefix before sending. Stored in the Keychain with the URL and key."
    static let webhookURL = "Where Pip POSTs shares. Only https URLs are accepted. Stored in the Keychain and shared with the share extension."
    static let key = "Bearer token sent as Authorization: Bearer. Stored in the Keychain and shared with the share extension."
}

enum StatusCopy {
    static let delivered = "Delivered! 📬"
    static let tripped = "Pip tripped, try again 🩹"
    static let needsWebhook = "Add a bot in Pip first 🔑"
    static let tooHeavy = "That parcel is too heavy 📦"
    static let empty = "Nothing to carry"
    static let saved = "Tucked in the Keychain 🔐"
    static let gathering = "Gathering…"
    static let sending = "On the way…"
}

struct BotAppearance: Equatable {
    var symbol: String
    var color: Color
}

enum BotMarks {
    private static let symbols = [
        "sparkles", "paperplane.fill", "bolt.fill", "moon.stars.fill",
        "leaf.fill", "flame.fill", "drop.fill", "hare.fill",
    ]
    private static let colors = [
        PipPalette.accent,
        PipPalette.coral,
        Color(red: 0.98, green: 0.78, blue: 0.35),
        Color(red: 0.45, green: 0.88, blue: 0.70),
        Color(red: 0.72, green: 0.58, blue: 1.0),
        Color(red: 1.0, green: 0.64, blue: 0.40),
        Color(red: 0.55, green: 0.78, blue: 1.0),
        Color(red: 0.95, green: 0.45, blue: 0.75),
    ]

    static func appearance(for name: String) -> BotAppearance {
        var hash: UInt = 0
        for scalar in name.unicodeScalars {
            hash = hash &* 33 &+ UInt(scalar.value)
        }
        let index = Int(hash % UInt(symbols.count))
        return BotAppearance(symbol: symbols[index], color: colors[index])
    }
}

struct PipButtonStyle: ButtonStyle {
    var prominent = true
    var fill: Color = .white
    var label: Color = .black

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(prominent ? label : PipPalette.ink)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 44)
            .background(prominent ? fill : Color.clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                if !prominent {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(PipPalette.line, lineWidth: 1)
                }
            }
            .opacity(configuration.isPressed ? 0.72 : 1)
    }
}

struct PipWordmark: View {
    var subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Pip")
                .font(.system(size: 28, weight: .semibold))
                .tracking(1.4)
                .foregroundStyle(PipPalette.ink)
            Text(subtitle)
                .font(.body)
                .foregroundStyle(PipPalette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

struct PipInfoButton: View {
    var title: String
    var text: String
    @State private var shown = false

    var body: some View {
        Button {
            shown.toggle()
        } label: {
            Image(systemName: "info.circle")
                .font(.body)
                .foregroundStyle(PipPalette.accent)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(text)
        .accessibilityLabel("About \(title)")
        .accessibilityHint(text)
        .popover(isPresented: $shown, arrowEdge: .top) {
            Text(text)
                .font(.callout)
                .foregroundStyle(PipPalette.ink)
                .padding(16)
                .frame(width: 280, alignment: .leading)
                .background(PipPalette.background)
        }
    }
}

struct PipLabeledField<Content: View>: View {
    var title: String
    var symbol: String
    var info: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: symbol)
                .font(.body)
                .foregroundStyle(PipPalette.accent)
                .frame(width: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(PipPalette.muted)
                content()
                    .textFieldStyle(.plain)
            }
            PipInfoButton(title: title, text: info)
        }
        .padding(.leading, 12)
        .padding(.vertical, 4)
        .frame(minHeight: 44)
        .background(PipPalette.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct PipHairline: View {
    var playful: Bool

    var body: some View {
        LinearGradient(
            colors: playful
                ? [PipPalette.coral, PipPalette.accent, PipPalette.iris]
                : [PipPalette.accent, PipPalette.iris],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(height: 3)
        .accessibilityHidden(true)
    }
}
