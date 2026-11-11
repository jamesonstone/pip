import XCTest
@testable import PipCore

#if canImport(Security)
import Security

final class SecurityKeychainTests: XCTestCase {
    func testSaveWritesGenericPasswordAttributes() throws {
        let client = RecordingKeychain()
        let store = SecurityKeychain(service: "pip.intake", accessGroup: "TEAMID.com.example.pip.shared", client: client)
        try store.set(Data("secret".utf8), account: "intake")

        let query = try XCTUnwrap(client.added.last)
        XCTAssertEqual(query[kSecClass as String] as? String, kSecClassGenericPassword as String)
        XCTAssertEqual(query[kSecAttrService as String] as? String, "pip.intake")
        XCTAssertEqual(query[kSecAttrAccount as String] as? String, "intake")
        XCTAssertEqual(query[kSecAttrAccessGroup as String] as? String, "TEAMID.com.example.pip.shared")
        XCTAssertEqual(query[kSecValueData as String] as? Data, Data("secret".utf8))
        XCTAssertEqual(query[kSecAttrAccessible as String] as? String, kSecAttrAccessibleAfterFirstUnlock as String)
        XCTAssertEqual(query[kSecUseDataProtectionKeychain as String] as? Bool, true)
    }

    func testDuplicateItemUpdatesTheExistingRecord() throws {
        let client = RecordingKeychain()
        client.addStatus = errSecDuplicateItem
        let store = SecurityKeychain(service: "pip.intake", accessGroup: nil, client: client)
        try store.set(Data("next".utf8), account: "intake")

        XCTAssertEqual(client.added.count, 1)
        XCTAssertNil(client.added[0][kSecAttrAccessGroup as String])
        let update = try XCTUnwrap(client.updated.last)
        XCTAssertEqual(update.attributes[kSecValueData as String] as? Data, Data("next".utf8))
        XCTAssertNil(update.query[kSecValueData as String])
    }

    func testLoadAndDelete() throws {
        let client = RecordingKeychain()
        let store = SecurityKeychain(service: "pip.intake", accessGroup: "TEAMID.group", client: client)
        XCTAssertNil(try store.data(account: "missing"))
        try store.set(Data("saved".utf8), account: "intake")
        XCTAssertEqual(try store.data(account: "intake"), Data("saved".utf8))
        try store.remove(account: "intake")
        XCTAssertNil(try store.data(account: "intake"))
        XCTAssertEqual(client.deleted.count, 1)
    }

    func testMissingEntitlementIsReported() {
        let client = RecordingKeychain()
        client.addStatus = errSecMissingEntitlement
        let store = SecurityKeychain(service: "pip.intake", accessGroup: "TEAMID.group", client: client)
        XCTAssertThrowsError(try store.set(Data("x".utf8), account: "intake")) { error in
            XCTAssertEqual(error as? KeychainError, .missingEntitlement)
        }
    }
}

private final class RecordingKeychain: KeychainItemClient, @unchecked Sendable {
    var added: [[String: Any]] = []
    var updated: [(query: [String: Any], attributes: [String: Any])] = []
    var deleted: [[String: Any]] = []
    var stored: [String: Data] = [:]
    var addStatus: OSStatus = errSecSuccess

    func add(_ query: CFDictionary) -> OSStatus {
        let dict = dictionary(query)
        added.append(dict)
        if addStatus != errSecSuccess { return addStatus }
        if let account = dict[kSecAttrAccount as String] as? String {
            stored[account] = dict[kSecValueData as String] as? Data
        }
        return errSecSuccess
    }

    func copyMatching(_ query: CFDictionary, result: UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus {
        let dict = dictionary(query)
        guard let account = dict[kSecAttrAccount as String] as? String, let data = stored[account] else {
            return errSecItemNotFound
        }
        result?.pointee = data as CFData
        return errSecSuccess
    }

    func update(_ query: CFDictionary, attributes: CFDictionary) -> OSStatus {
        let match = dictionary(query)
        let values = dictionary(attributes)
        updated.append((match, values))
        if let account = match[kSecAttrAccount as String] as? String, let data = values[kSecValueData as String] as? Data {
            stored[account] = data
        }
        return errSecSuccess
    }

    func delete(_ query: CFDictionary) -> OSStatus {
        let dict = dictionary(query)
        deleted.append(dict)
        if let account = dict[kSecAttrAccount as String] as? String {
            stored.removeValue(forKey: account)
        }
        return errSecSuccess
    }

    private func dictionary(_ query: CFDictionary) -> [String: Any] {
        query as NSDictionary as? [String: Any] ?? [:]
    }
}
#endif
