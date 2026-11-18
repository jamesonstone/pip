import Foundation
import XCTest
@testable import PipCore

final class DestinationBookTests: XCTestCase {
    func testLegacyRecordBecomesOneNamedDestination() throws {
        let keychain = InMemoryKeychain()
        let raw = #"{"bearerToken":"test-token","webhookURL":"https://intake.example.test/hook"}"#
        try keychain.set(Data(raw.utf8), account: CredentialStore.account)
        let store = CredentialStore(keychain: keychain)

        let first = try store.loadBook()
        let second = try store.loadBook()
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.destinations.count, 1)
        XCTAssertEqual(first.destinations[0].name, "Default")
        XCTAssertEqual(first.lastUsedID, first.destinations[0].id)
        XCTAssertEqual(try store.load(), IntakeCredentials(
            webhookURL: URL(string: "https://intake.example.test/hook")!,
            bearerToken: "test-token"
        ))

        try store.rememberLastUsed(first.destinations[0].id)
        let saved = try XCTUnwrap(keychain.data(account: CredentialStore.account))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: saved) as? [String: Any])
        XCTAssertEqual(json["version"] as? Int, 2)
        XCTAssertEqual(try store.loadBook(), first)
    }

    func testBookRoundTripKeepsLastUsedAndDoesNotDropSiblings() throws {
        let store = CredentialStore(keychain: InMemoryKeychain())
        let work = destination(name: "Work", host: "work.example.test", token: "work-token")
        let home = destination(name: "Home", host: "home.example.test", token: "home-token")
        try store.save(DestinationBook(destinations: [work, home], lastUsedID: home.id))

        let loaded = try store.loadBook()
        XCTAssertEqual(loaded.destinations.map(\.name), ["Work", "Home"])
        XCTAssertEqual(loaded.preferred?.id, home.id)
        XCTAssertEqual(loaded.preferred?.bearerToken, "home-token")

        let replacement = try CredentialRules.make(
            webhookURL: "https://work.example.test/next",
            bearerToken: "next-token"
        ).get()
        try store.rememberLastUsed(work.id)
        try store.save(replacement)
        let after = try store.loadBook()
        XCTAssertEqual(after.destinations.count, 2)
        XCTAssertEqual(after.preferred?.bearerToken, "next-token")
        XCTAssertEqual(after.preferred?.webhookURL.host, "work.example.test")
        XCTAssertEqual(after.destinations.first { $0.id == home.id }?.bearerToken, "home-token")
    }

    func testInvalidBookIsRejected() throws {
        let store = CredentialStore(keychain: InMemoryKeychain())
        let url = URL(string: "https://intake.example.test")!
        XCTAssertThrowsError(try store.save(DestinationBook(destinations: [
            destination(name: "Work", host: "intake.example.test", token: "test-token"),
            destination(name: " work ", host: "other.example.test", token: "other-token"),
        ], lastUsedID: nil))) { error in
            XCTAssertEqual(error as? CredentialError, .duplicateName)
        }
        XCTAssertThrowsError(try store.save(DestinationBook(destinations: [
            IntakeDestination(id: UUID(), name: "@secret", webhookURL: url, bearerToken: "test-token"),
        ], lastUsedID: nil))) { error in
            XCTAssertEqual(error as? CredentialError, .invalidName)
        }
        XCTAssertThrowsError(try store.save(DestinationBook(destinations: [
            IntakeDestination(id: UUID(), name: "Work", webhookURL: URL(string: "http://intake.example.test")!, bearerToken: "test-token"),
        ], lastUsedID: nil))) { error in
            XCTAssertEqual(error as? CredentialError, .invalidWebhookURL)
        }
        XCTAssertNil(try store.load())
    }

    func testBrokenJSONAndUnknownVersionThrow() throws {
        let broken = InMemoryKeychain()
        try broken.set(Data("not-json".utf8), account: CredentialStore.account)
        XCTAssertThrowsError(try CredentialStore(keychain: broken).loadBook()) { error in
            XCTAssertEqual(error as? CredentialError, .malformedRecord)
        }

        let future = InMemoryKeychain()
        let raw = #"{"version":9,"destinations":[]}"#
        try future.set(Data(raw.utf8), account: CredentialStore.account)
        XCTAssertThrowsError(try CredentialStore(keychain: future).loadBook()) { error in
            XCTAssertEqual(error as? CredentialError, .malformedRecord)
        }
    }

    func testNotePrefixSelectsTheLongestNameAndStripsIt() {
        let work = destination(name: "Work", host: "work.example.test", token: "work-token")
        let workBot = destination(name: "Work Bot", host: "bot.example.test", token: "bot-token")
        let book = DestinationBook(destinations: [work, workBot], lastUsedID: work.id)

        let prefixed = book.choice(for: "@work bot  hello", selectedID: work.id)
        XCTAssertEqual(prefixed.destination?.id, workBot.id)
        XCTAssertEqual(prefixed.note, "hello")
        XCTAssertTrue(prefixed.usedPrefix)

        let shorter = book.choice(for: "@Work\nlater", selectedID: workBot.id)
        XCTAssertEqual(shorter.destination?.id, work.id)
        XCTAssertEqual(shorter.note, "later")

        let unmatched = book.choice(for: "@Workshop keep", selectedID: work.id)
        XCTAssertEqual(unmatched.destination?.id, work.id)
        XCTAssertEqual(unmatched.note, "@Workshop keep")
        XCTAssertFalse(unmatched.usedPrefix)

        let exact = NoteRouter.route(note: "@Work Bot", destinations: book.destinations)
        XCTAssertEqual(exact.destinationID, workBot.id)
        XCTAssertEqual(exact.note, "")

        let middle = NoteRouter.route(note: "see @Work", destinations: book.destinations)
        XCTAssertNil(middle.destinationID)
        XCTAssertEqual(middle.note, "see @Work")
    }

    func testStrippedPrefixIsThePayloadNote() throws {
        let work = destination(name: "Work", host: "work.example.test", token: "work-token")
        let book = DestinationBook(destinations: [work], lastUsedID: work.id)
        let choice = book.choice(for: "@Work read later", selectedID: nil)
        let payload = try PayloadBuilder(images: UnexpectedImageEncoder()).build(InboundShare(
            link: URL(string: "https://example.test/story")!,
            note: choice.note,
            source: .macos
        ))
        XCTAssertEqual(payload.text, "read later")
        XCTAssertEqual(payload.url, "https://example.test/story")
    }

    private func destination(name: String, host: String, token: String) -> IntakeDestination {
        IntakeDestination(
            id: UUID(),
            name: name,
            webhookURL: URL(string: "https://\(host)/hook")!,
            bearerToken: token
        )
    }
}
