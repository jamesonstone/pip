import SwiftUI

enum PipPalette {
    static let background = Color(red: 0.07, green: 0.07, blue: 0.08)
    static let card = Color.white.opacity(0.06)
    static let ink = Color.white
    static let muted = Color.white.opacity(0.72)
    static let line = Color.white.opacity(0.14)
}

enum StatusCopy {
    static let delivered = "Delivered! 📬"
    static let tripped = "Pip tripped, try again 🩹"
    static let needsWebhook = "Set the webhook in Pip first 🔑"
    static let tooHeavy = "That parcel is too heavy 📦"
    static let empty = "Nothing to carry"
    static let saved = "Tucked in the Keychain 🔐"
    static let gathering = "Gathering…"
    static let sending = "On the way…"
}

struct PipButtonStyle: ButtonStyle {
    var prominent = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(prominent ? Color.black : PipPalette.ink)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 44)
            .background(prominent ? Color.white : Color.clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
