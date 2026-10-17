import Foundation

/// The owner's Luna Worker as Anthropic proxy (CHAT_SPEC §8). A proxy token (`lt_…`, from an invite code) is kept in the same
/// Keychain slot as a personal key; the prefix decides where requests go, so personal-key mode keeps working.
enum LunaProxy {
    static let baseURL = URL(string: "https://luna-server.farchan.workers.dev")!
    static let tokenPrefix = "lt_"

    static func isProxyToken(_ key: String) -> Bool { key.hasPrefix(tokenPrefix) }

    static func messagesURL(for key: String) -> URL {
        isProxyToken(key) ? baseURL.appendingPathComponent("llm/v1/messages") : URL(string: "https://api.anthropic.com/v1/messages")!
    }

    enum RegisterError: LocalizedError {
        case offline, unreachable(String), rejected(String)
        var errorDescription: String? {
            switch self {
            case .offline: "Needs internet to register."
            case .unreachable(let reason): "Couldn't reach the Luna server: \(reason)"
            case .rejected(let message): message
            }
        }
    }

    /// Exchanges an invite code for a device token.
    static func register(inviteCode: String, deviceLabel: String, session: URLSession = .shared) async throws -> String {
        var request = URLRequest(url: baseURL.appendingPathComponent("register"))
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["invite_code": inviteCode, "device_label": deviceLabel])
        let data: Data, response: URLResponse
        do { (data, response) = try await session.data(for: request) }
        catch let error as URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff: throw RegisterError.offline
            default: throw RegisterError.unreachable(error.localizedDescription)
            }
        }
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard (response as? HTTPURLResponse)?.statusCode == 200, let token = json?["token"] as? String else {
            throw RegisterError.rejected(((json?["error"] as? [String: Any])?["message"] as? String) ?? "Registration failed.")
        }
        return token
    }
}
