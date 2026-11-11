import Foundation

#if canImport(Security)
import Security

public enum KeychainError: Error, Equatable, Sendable {
    case missingEntitlement
    case status(Int32)
}

public protocol KeychainItemClient: Sendable {
    func add(_ query: CFDictionary) -> OSStatus
    func copyMatching(_ query: CFDictionary, result: UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus
    func update(_ query: CFDictionary, attributes: CFDictionary) -> OSStatus
    func delete(_ query: CFDictionary) -> OSStatus
}

public struct LiveKeychainClient: KeychainItemClient {
    public init() {}

    public func add(_ query: CFDictionary) -> OSStatus {
        SecItemAdd(query, nil)
    }

    public func copyMatching(_ query: CFDictionary, result: UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus {
        SecItemCopyMatching(query, result)
    }

    public func update(_ query: CFDictionary, attributes: CFDictionary) -> OSStatus {
        SecItemUpdate(query, attributes)
    }

    public func delete(_ query: CFDictionary) -> OSStatus {
        SecItemDelete(query)
    }
}

public struct SecurityKeychain: KeychainStoring {
    public var service: String
    public var accessGroup: String?
    public var client: any KeychainItemClient

    public init(service: String, accessGroup: String?, client: any KeychainItemClient = LiveKeychainClient()) {
        self.service = service
        self.accessGroup = KeychainAccessGroup.normalized(accessGroup)
        self.client = client
    }

    public func set(_ data: Data, account: String) throws {
        var query = baseQuery(account: account)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = client.add(query as CFDictionary)
        if status == errSecDuplicateItem {
            var match = baseQuery(account: account)
            match[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let attributes: [String: Any] = [
                kSecValueData as String: data,
            ]
            try check(client.update(match as CFDictionary, attributes: attributes as CFDictionary))
            return
        }
        try check(status)
    }

    public func data(account: String) throws -> Data? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = client.copyMatching(query as CFDictionary, result: &result)
        if status == errSecItemNotFound { return nil }
        try check(status)
        guard let data = result as? Data else { throw KeychainError.status(errSecDecode) }
        return data
    }

    public func remove(account: String) throws {
        let status = client.delete(baseQuery(account: account) as CFDictionary)
        if status == errSecItemNotFound { return }
        try check(status)
    }

    func baseQuery(account: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: true,
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }

    private func check(_ status: OSStatus) throws {
        if status == errSecSuccess { return }
        if status == errSecMissingEntitlement { throw KeychainError.missingEntitlement }
        throw KeychainError.status(status)
    }
}
#endif
