import Foundation

/// One non-streaming Messages API request (CHAT_SPEC §5). Request and response stay raw JSON so the
/// agent can append response content back unchanged, thinking blocks included.
struct ClaudeClient: Sendable {
    static let model = "claude-haiku-5-5"

    enum ClientError: LocalizedError {
        case offline, unauthorized, busy, rejected(String), invalidResponse

        var errorDescription: String? {
            switch self {
            case .offline: "Chat needs internet. You can still add expenses with the + button."
            case .unauthorized: "Your API key was rejected. Check it in Settings → AI Chat."
            case .busy: "Claude is busy right now. Try again in a moment."
            case .rejected(let message): "Request failed: \(message)"
            case .invalidResponse: "Claude sent a reply the app couldn't read."
            }
        }
    }

    let apiKey: String
    var session: URLSession = .shared

    func send(_ body: Data) async throws -> Data {
        do { return try await attempt(body) }
        catch ClientError.busy { try await Task.sleep(for: .seconds(2)) }
        catch ClientError.offline { try await Task.sleep(for: .seconds(1)) }
        // One retry for transient failures; everything else surfaces immediately.
        return try await attempt(body)
    }

    private func attempt(_ body: Data) async throws -> Data {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.httpBody = body
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let data: Data, response: URLResponse
        do { (data, response) = try await session.data(for: request) }
        catch is URLError { throw ClientError.offline }
        guard let status = (response as? HTTPURLResponse)?.statusCode else { throw ClientError.invalidResponse }
        switch status {
        case 200: return data
        case 401, 403: throw ClientError.unauthorized
        case 429, 500...599: throw ClientError.busy
        default: throw ClientError.rejected(Self.message(in: data) ?? "HTTP \(status)")
        }
    }

    private static func message(in data: Data) -> String? {
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        return (json?["error"] as? [String: Any])?["message"] as? String
    }
}
