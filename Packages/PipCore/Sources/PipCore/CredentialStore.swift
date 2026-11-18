import Foundation

public struct IntakeCredentials: Equatable, Sendable {
    public var webhookURL: URL
    public var bearerToken: String

    public init(webhookURL: URL, bearerToken: String) {
        self.webhookURL = webhookURL
        self.bearerToken = bearerToken
    }
}

public enum CredentialError: Error, Equatable, Sendable {
    case invalidWebhookURL
    case emptyToken
    case invalidName
    case duplicateName
    case malformedRecord
}

public enum CredentialRules {
    public static func make(webhookURL: String, bearerToken: String) -> Result<IntakeCredentials, CredentialError> {
        let token = bearerToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty, token.count <= 4_096 else { return .failure(.emptyToken) }
        guard !token.contains(where: { $0.isNewline || $0 == "\u{0000}" }) else {
            return .failure(.emptyToken)
        }

        let trimmedURL = webhookURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmedURL),
              url.scheme?.lowercased() == "https",
              let host = url.host,
              !host.isEmpty,
              url.user == nil else {
            return .failure(.invalidWebhookURL)
        }
        return .success(IntakeCredentials(webhookURL: url, bearerToken: token))
    }
}

public protocol KeychainStoring: Sendable {
    func set(_ data: Data, account: String) throws
    func data(account: String) throws -> Data?
    func remove(account: String) throws
}

public final class InMemoryKeychain: KeychainStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String: Data] = [:]

    public init() {}

    public func set(_ data: Data, account: String) throws {
        lock.lock()
        items[account] = data
        lock.unlock()
    }

    public func data(account: String) throws -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return items[account]
    }

    public func remove(account: String) throws {
        lock.lock()
        items.removeValue(forKey: account)
        lock.unlock()
    }
}

public struct CredentialStore: Sendable {
    public static let account = "intake"

    private let keychain: any KeychainStoring

    public init(keychain: any KeychainStoring) {
        self.keychain = keychain
    }

    public func save(_ credentials: IntakeCredentials) throws {
        let checked = try CredentialRules.make(
            webhookURL: credentials.webhookURL.absoluteString,
            bearerToken: credentials.bearerToken
        ).get()
        var book = try loadBook()
        if book.destinations.isEmpty {
            let id = UUID()
            book.destinations = [
                IntakeDestination(
                    id: id,
                    name: DestinationBook.legacyName,
                    webhookURL: checked.webhookURL,
                    bearerToken: checked.bearerToken
                ),
            ]
            book.lastUsedID = id
        } else if let preferred = book.preferred,
                  let index = book.destinations.firstIndex(where: { $0.id == preferred.id }) {
            book.destinations[index].webhookURL = checked.webhookURL
            book.destinations[index].bearerToken = checked.bearerToken
        }
        try save(book)
    }

    public func load() throws -> IntakeCredentials? {
        try loadBook().preferred?.credentials
    }

    public func loadBook() throws -> DestinationBook {
        guard let data = try keychain.data(account: Self.account) else {
            return DestinationBook(destinations: [], lastUsedID: nil)
        }
        if let record = try? JSONDecoder().decode(BookRecord.self, from: data) {
            guard record.version == 2 else { throw CredentialError.malformedRecord }
            return try book(from: record)
        }
        let legacy: LegacyRecord
        do {
            legacy = try JSONDecoder().decode(LegacyRecord.self, from: data)
        } catch {
            throw CredentialError.malformedRecord
        }
        let credentials = try CredentialRules.make(
            webhookURL: legacy.webhookURL.absoluteString,
            bearerToken: legacy.bearerToken
        ).get()
        let id = LegacyDestinationIdentity.id(for: credentials.webhookURL)
        return DestinationBook(
            destinations: [
                IntakeDestination(
                    id: id,
                    name: DestinationBook.legacyName,
                    webhookURL: credentials.webhookURL,
                    bearerToken: credentials.bearerToken
                ),
            ],
            lastUsedID: id
        )
    }

    public func save(_ book: DestinationBook) throws {
        let stored = try record(from: book)
        let data = try JSONEncoder().encode(stored)
        try keychain.set(data, account: Self.account)
    }

    public func rememberLastUsed(_ id: UUID) throws {
        guard let data = try keychain.data(account: Self.account) else { return }
        let storedVersion = (try? JSONDecoder().decode(BookRecord.self, from: data))?.version
        var book = try loadBook()
        guard book.destinations.contains(where: { $0.id == id }) else { return }
        if storedVersion == 2, book.lastUsedID == id { return }
        book.lastUsedID = id
        try save(book)
    }

    public func clear() throws {
        try keychain.remove(account: Self.account)
    }

    private func record(from book: DestinationBook) throws -> BookRecord {
        var destinations: [DestinationRecord] = []
        var names: Set<String> = []
        var ids: Set<UUID> = []
        for destination in book.destinations {
            let name = try DestinationRules.normalizedName(destination.name).get()
            let credentials = try CredentialRules.make(
                webhookURL: destination.webhookURL.absoluteString,
                bearerToken: destination.bearerToken
            ).get()
            let folded = name.folding(options: .caseInsensitive, locale: Locale(identifier: "en_US_POSIX"))
            guard names.insert(folded).inserted else { throw CredentialError.duplicateName }
            guard ids.insert(destination.id).inserted else { throw CredentialError.malformedRecord }
            destinations.append(DestinationRecord(
                id: destination.id,
                name: name,
                webhookURL: credentials.webhookURL,
                bearerToken: credentials.bearerToken
            ))
        }
        let lastUsedID = book.lastUsedID.flatMap { ids.contains($0) ? $0 : nil }
        return BookRecord(version: 2, destinations: destinations, lastUsedID: lastUsedID)
    }

    private func book(from record: BookRecord) throws -> DestinationBook {
        var destinations: [IntakeDestination] = []
        var names: Set<String> = []
        var ids: Set<UUID> = []
        for stored in record.destinations {
            let name = try DestinationRules.normalizedName(stored.name).get()
            let credentials = try CredentialRules.make(
                webhookURL: stored.webhookURL.absoluteString,
                bearerToken: stored.bearerToken
            ).get()
            let folded = name.folding(options: .caseInsensitive, locale: Locale(identifier: "en_US_POSIX"))
            guard names.insert(folded).inserted else { throw CredentialError.malformedRecord }
            guard ids.insert(stored.id).inserted else { throw CredentialError.malformedRecord }
            destinations.append(IntakeDestination(
                id: stored.id,
                name: name,
                webhookURL: credentials.webhookURL,
                bearerToken: credentials.bearerToken
            ))
        }
        let lastUsedID = record.lastUsedID.flatMap { ids.contains($0) ? $0 : nil }
        return DestinationBook(destinations: destinations, lastUsedID: lastUsedID)
    }
}

private struct BookRecord: Codable {
    var version: Int
    var destinations: [DestinationRecord]
    var lastUsedID: UUID?
}

private struct DestinationRecord: Codable {
    var id: UUID
    var name: String
    var webhookURL: URL
    var bearerToken: String
}

private struct LegacyRecord: Codable {
    var webhookURL: URL
    var bearerToken: String
}

public enum KeychainAccessGroup {
    public static func normalized(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        guard !trimmed.hasPrefix(".") else { return nil }
        return trimmed
    }
}

public struct PipKeychainLocation: Equatable, Sendable {
    public var service: String
    public var accessGroup: String?

    public init(service: String, accessGroup: String?) {
        self.service = service
        self.accessGroup = accessGroup
    }

    public static func from(infoDictionary: [String: Any]) -> PipKeychainLocation {
        let service = (infoDictionary["PipKeychainService"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let group = KeychainAccessGroup.normalized(infoDictionary["PipKeychainAccessGroup"] as? String)
        return PipKeychainLocation(
            service: (service?.isEmpty == false) ? service! : "pip.intake",
            accessGroup: group
        )
    }
}
