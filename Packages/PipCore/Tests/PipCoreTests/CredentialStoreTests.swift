import XCTest
@testable import PipCore

final class CredentialStoreTests: XCTestCase {
    func testSaveLoadReplaceAndClear() throws {
        let store = CredentialStore(keychain: InMemoryKeychain())
        XCTAssertNil(try store.load())

        let first = try CredentialRules.make(
            webhookURL: " https://intake.example.test/hook ",
            bearerToken: " test-token "
        ).get()
        try store.save(first)
        XCTAssertEqual(try store.load(), IntakeCredentials(
            webhookURL: URL(string: "https://intake.example.test/hook")!,
            bearerToken: "test-token"
        ))

        let second = try CredentialRules.make(
            webhookURL: "https://intake.example.test/other",
            bearerToken: "next-token"
        ).get()
        try store.save(second)
        XCTAssertEqual(try store.load()?.bearerToken, "next-token")
        XCTAssertEqual(try store.load()?.webhookURL.host, "intake.example.test")

        try store.clear()
        XCTAssertNil(try store.load())
    }

    func testRejectsInsecureAndEmptySecrets() {
        XCTAssertEqual(
            CredentialRules.make(webhookURL: "http://intake.example.test", bearerToken: "token"),
            .failure(.invalidWebhookURL)
        )
        XCTAssertEqual(
            CredentialRules.make(webhookURL: "https://user:pass@intake.example.test", bearerToken: "token"),
            .failure(.invalidWebhookURL)
        )
        XCTAssertEqual(
            CredentialRules.make(webhookURL: "https://intake.example.test", bearerToken: "   "),
            .failure(.emptyToken)
        )
        XCTAssertEqual(
            CredentialRules.make(webhookURL: "https://intake.example.test", bearerToken: "line\nbreak"),
            .failure(.emptyToken)
        )
    }

    func testMalformedRecordThrows() throws {
        let keychain = InMemoryKeychain()
        try keychain.set(Data("not-json".utf8), account: CredentialStore.account)
        let store = CredentialStore(keychain: keychain)
        XCTAssertThrowsError(try store.load()) { error in
            XCTAssertEqual(error as? CredentialError, .malformedRecord)
        }
    }

    func testAccessGroupNormalization() {
        XCTAssertNil(KeychainAccessGroup.normalized(nil))
        XCTAssertNil(KeychainAccessGroup.normalized("  "))
        XCTAssertNil(KeychainAccessGroup.normalized(".com.example.pip.shared"))
        XCTAssertEqual(
            KeychainAccessGroup.normalized(" TEAMID.com.example.pip.shared "),
            "TEAMID.com.example.pip.shared"
        )
    }

    func testLocationFromInfoDictionary() {
        let missing = PipKeychainLocation.from(infoDictionary: [:])
        XCTAssertEqual(missing.service, "pip.intake")
        XCTAssertNil(missing.accessGroup)

        let configured = PipKeychainLocation.from(infoDictionary: [
            "PipKeychainService": "com.example.pip.intake",
            "PipKeychainAccessGroup": "TEAMID.com.example.pip.shared",
        ])
        XCTAssertEqual(configured.service, "com.example.pip.intake")
        XCTAssertEqual(configured.accessGroup, "TEAMID.com.example.pip.shared")
    }
}
