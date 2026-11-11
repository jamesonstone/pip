import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum WebhookError: Error, Equatable, Sendable {
    case invalidResponse
    case rejected(statusCode: Int)
    case transport
}

public enum RedirectPolicy {
    public static func request(from proposed: URLRequest, originalHost: String?) -> URLRequest? {
        guard let originalHost, let nextHost = proposed.url?.host, originalHost == nextHost else {
            return nil
        }
        return proposed
    }
}

public struct WebhookClient {
    private let session: URLSession

    public init(session: URLSession = WebhookClient.makeSession()) {
        self.session = session
    }

    public func send(_ payload: IntakePayload, using credentials: IntakeCredentials) async throws {
        var request = URLRequest(url: credentials.webhookURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(credentials.bearerToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder.pip.encode(payload)

        let response: URLResponse
        do {
            (_, response) = try await session.data(for: request)
        } catch {
            throw WebhookError.transport
        }
        guard let http = response as? HTTPURLResponse else {
            throw WebhookError.invalidResponse
        }
        guard (200 ... 299).contains(http.statusCode) else {
            throw WebhookError.rejected(statusCode: http.statusCode)
        }
    }

    public static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        return URLSession(configuration: configuration, delegate: RedirectGuard(), delegateQueue: nil)
    }
}

private final class RedirectGuard: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(RedirectPolicy.request(from: request, originalHost: task.originalRequest?.url?.host))
    }
}
