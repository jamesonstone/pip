import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import PipCore

final class WebhookClientTests: XCTestCase {
    override func tearDown() {
        StubURLProtocol.handler = nil
        super.tearDown()
    }

    func testPostsJSONWithABearerToken() async throws {
        let payload = IntakePayload(
            url: "https://example.com/story",
            text: "later",
            imageBase64: nil,
            filename: nil,
            mimeType: nil,
            source: .ios
        )
        let credentials = try CredentialRules.make(
            webhookURL: "https://intake.example.test/hook",
            bearerToken: "test-token"
        ).get()
        StubURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.absoluteString, "https://intake.example.test/hook")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
            let body = try JSONDecoder().decode(IntakePayload.self, from: request.bodyData)
            XCTAssertEqual(body, payload)
            XCTAssertFalse(String(decoding: request.bodyData, as: UTF8.self).contains("test-token"))
            let response = HTTPURLResponse(url: request.url!, statusCode: 204, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        try await WebhookClient(session: stubSession()).send(payload, using: credentials)
    }

    func testRejectedStatusThrows() async {
        StubURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (response, Data("nope".utf8))
        }
        let credentials = IntakeCredentials(
            webhookURL: URL(string: "https://intake.example.test")!,
            bearerToken: "test-token"
        )
        let payload = IntakePayload(url: "hello", text: nil, imageBase64: nil, filename: nil, mimeType: nil, source: .macos)
        do {
            try await WebhookClient(session: stubSession()).send(payload, using: credentials)
            XCTFail("expected the webhook to reject the request")
        } catch let error as WebhookError {
            XCTAssertEqual(error, .rejected(statusCode: 401))
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func testTransportFailureThrows() async {
        StubURLProtocol.handler = { _ in
            throw URLError(.cannotConnectToHost)
        }
        let credentials = IntakeCredentials(
            webhookURL: URL(string: "https://intake.example.test")!,
            bearerToken: "test-token"
        )
        let payload = IntakePayload(url: "hello", text: nil, imageBase64: nil, filename: nil, mimeType: nil, source: .ios)
        do {
            try await WebhookClient(session: stubSession()).send(payload, using: credentials)
            XCTFail("expected a transport failure")
        } catch let error as WebhookError {
            XCTAssertEqual(error, .transport)
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func testRedirectDropsTheTokenWhenTheHostChanges() {
        var request = URLRequest(url: URL(string: "https://evil.example/hook")!)
        request.setValue("Bearer test-token", forHTTPHeaderField: "Authorization")
        XCTAssertNil(RedirectPolicy.request(from: request, originalHost: "intake.example.test"))

        let sameHost = URLRequest(url: URL(string: "https://intake.example.test/next")!)
        XCTAssertNotNil(RedirectPolicy.request(from: sameHost, originalHost: "intake.example.test"))
    }

    private func stubSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

private final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private extension URLRequest {
    var bodyData: Data {
        if let httpBody { return httpBody }
        guard let stream = httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 1024)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let count = stream.read(buffer, maxLength: 1024)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}
