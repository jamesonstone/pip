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
        let record = StoredCredentials(webhookURL: checked.webhookURL, bearerToken: checked.bearerToken)
        let data = try JSONEncoder().encode(record)
        try keychain.set(data, account: Self.account)
    }

    public func load() throws -> IntakeCredentials? {
        guard let data = try keychain.data(account: Self.account) else { return nil }
        let stored: StoredCredentials
        do {
            stored = try JSONDecoder().decode(StoredCredentials.self, from: data)
        } catch {
            throw CredentialError.malformedRecord
        }
        return try CredentialRules.make(
            webhookURL: stored.webhookURL.absoluteString,
            bearerToken: stored.bearerToken
        ).get()
    }

    public func clear() throws {
        try keychain.remove(account: Self.account)
    }
}

private struct StoredCredentials: Codable {
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
