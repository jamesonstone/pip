import Foundation

public struct IntakeDestination: Equatable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var webhookURL: URL
    public var bearerToken: String

    public init(id: UUID, name: String, webhookURL: URL, bearerToken: String) {
        self.id = id
        self.name = name
        self.webhookURL = webhookURL
        self.bearerToken = bearerToken
    }

    public var credentials: IntakeCredentials {
        IntakeCredentials(webhookURL: webhookURL, bearerToken: bearerToken)
    }
}

public struct DestinationBook: Equatable, Sendable {
    public static let legacyName = "Default"

    public var destinations: [IntakeDestination]
    public var lastUsedID: UUID?

    public init(destinations: [IntakeDestination], lastUsedID: UUID?) {
        self.destinations = destinations
        self.lastUsedID = lastUsedID
    }

    public var preferred: IntakeDestination? {
        if let lastUsedID, let match = destination(id: lastUsedID) {
            return match
        }
        return destinations.first
    }

    public func destination(id: UUID) -> IntakeDestination? {
        destinations.first { $0.id == id }
    }

    public func choice(for note: String, selectedID: UUID?, usePrefix: Bool = true) -> DestinationChoice {
        if usePrefix {
            let routed = NoteRouter.route(note: note, destinations: destinations)
            if let id = routed.destinationID, let match = destination(id: id) {
                return DestinationChoice(destination: match, note: routed.note, usedPrefix: true)
            }
        }
        let selected = selectedID.flatMap { destination(id: $0) } ?? preferred
        return DestinationChoice(destination: selected, note: note, usedPrefix: false)
    }
}

public struct DestinationChoice: Equatable, Sendable {
    public var destination: IntakeDestination?
    public var note: String
    public var usedPrefix: Bool

    public init(destination: IntakeDestination?, note: String, usedPrefix: Bool) {
        self.destination = destination
        self.note = note
        self.usedPrefix = usedPrefix
    }
}

public enum DestinationRules {
    public static let maxNameLength = 40

    public static func normalizedName(_ raw: String) -> Result<String, CredentialError> {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= maxNameLength else { return .failure(.invalidName) }
        guard !name.hasPrefix("@") else { return .failure(.invalidName) }
        guard name.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else {
            return .failure(.invalidName)
        }
        return .success(name)
    }
}

public struct RoutedNote: Equatable, Sendable {
    public var destinationID: UUID?
    public var note: String

    public init(destinationID: UUID?, note: String) {
        self.destinationID = destinationID
        self.note = note
    }
}

public enum NoteRouter {
    public static func route(note: String, destinations: [IntakeDestination]) -> RoutedNote {
        let body = note.drop { $0.isWhitespace }
        guard body.first == "@" else {
            return RoutedNote(destinationID: nil, note: note)
        }
        let afterAt = body.dropFirst()
        let ordered = destinations.sorted { lhs, rhs in
            if lhs.name.count != rhs.name.count { return lhs.name.count > rhs.name.count }
            return lhs.id.uuidString < rhs.id.uuidString
        }
        for destination in ordered {
            guard let rest = remainder(afterMatching: destination.name, in: afterAt) else { continue }
            let stripped = rest.drop { $0.isWhitespace }
            return RoutedNote(destinationID: destination.id, note: String(stripped))
        }
        return RoutedNote(destinationID: nil, note: note)
    }

    private static func remainder(afterMatching name: String, in text: Substring) -> Substring? {
        guard text.count >= name.count else { return nil }
        let prefix = String(text.prefix(name.count))
        let locale = Locale(identifier: "en_US_POSIX")
        guard prefix.compare(name, options: [.caseInsensitive], locale: locale) == .orderedSame else { return nil }
        let rest = text.dropFirst(name.count)
        if let next = rest.first, !next.isWhitespace { return nil }
        return rest
    }
}

enum LegacyDestinationIdentity {
    static func id(for webhookURL: URL) -> UUID {
        var digest = [UInt8](repeating: 0, count: 16)
        for (index, byte) in webhookURL.absoluteString.utf8.enumerated() {
            digest[index % 16] = digest[index % 16] &+ byte &+ UInt8(index & 0xFF)
        }
        digest[6] = (digest[6] & 0x0F) | 0x50
        digest[8] = (digest[8] & 0x3F) | 0x80
        return UUID(uuid: (
            digest[0], digest[1], digest[2], digest[3],
            digest[4], digest[5], digest[6], digest[7],
            digest[8], digest[9], digest[10], digest[11],
            digest[12], digest[13], digest[14], digest[15]
        ))
    }
}
