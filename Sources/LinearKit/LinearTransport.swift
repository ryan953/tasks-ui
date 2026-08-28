import Foundation

public enum LinearError: LocalizedError, Equatable {
    case notConfigured
    case unauthorized
    case rateLimited
    case http(status: Int, body: String)
    case graphQL([String])
    case decoding(String)
    case network(String)

    public var errorDescription: String? {
        switch self {
        case .notConfigured:
            "No Linear API key. Add one in Settings (⌘,)."
        case .unauthorized:
            "Linear rejected the API key. Create a new one at linear.app → Settings → API."
        case .rateLimited:
            "Linear is rate limiting requests. Try again shortly."
        case let .http(status, body):
            body.isEmpty ? "Linear returned HTTP \(status)." : "Linear returned HTTP \(status): \(body)"
        case let .graphQL(messages):
            messages.joined(separator: "\n")
        case let .decoding(detail):
            "Could not read Linear's response: \(detail)"
        case let .network(detail):
            "Could not reach Linear: \(detail)"
        }
    }
}

/// Sends a GraphQL request body and returns the raw response.
///
/// Injectable so the query and mutation layer can be tested against recorded
/// responses rather than the live workspace.
public protocol LinearTransport: Sendable {
    func send(body: Data, apiKey: String) async throws -> Data
}

public struct URLSessionLinearTransport: LinearTransport {
    public static let endpoint = URL(string: "https://api.linear.app/graphql")!

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(body: Data, apiKey: String) async throws -> Data {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // A personal API key goes in Authorization verbatim — no "Bearer" prefix.
        request.setValue(apiKey, forHTTPHeaderField: "Authorization")
        request.httpBody = body
        request.timeoutInterval = 30

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw LinearError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else { return data }
        switch http.statusCode {
        case 200...299:
            return data
        case 401, 403:
            throw LinearError.unauthorized
        case 429:
            throw LinearError.rateLimited
        default:
            throw LinearError.http(
                status: http.statusCode,
                body: String(decoding: data.prefix(500), as: UTF8.self)
            )
        }
    }
}
