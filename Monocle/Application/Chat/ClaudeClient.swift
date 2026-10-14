import Foundation

/// One Messages API request, streamed or not (CHAT_SPEC §5). Request and response stay raw JSON so the
/// agent can append response content back unchanged, thinking blocks included.
struct ClaudeClient: Sendable {
    static let model = "claude-haiku-5-5"

    enum ClientError: LocalizedError {
        case offline, unauthorized, deviceRejected, busy, limit(String), rejected(String), invalidResponse

        var errorDescription: String? {
            switch self {
            case .offline: "Chat needs internet. You can still add expenses with the + button."
            case .unauthorized: "Your API key was rejected. Check it in Settings → AI Chat."
            case .deviceRejected: "This device's Luna registration was rejected. Remove it and register again in Settings → AI Chat."
            case .busy: "Claude is busy right now. Try again in a moment."
            case .limit(let message): message
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

    /// Same request with `"stream": true`: `onText` gets each text delta as it arrives, and the result is the complete message
    /// assembled from the events, in the shape of a non-streaming response, so the agent treats both alike.
    /// Retries once only while nothing has been shown yet (a retry would repeat text the user already saw).
    func stream(_ body: Data, onText: @escaping @MainActor @Sendable (String) -> Void) async throws -> Data {
        final class Shown: @unchecked Sendable { var any = false }
        let shown = Shown()
        let track: @MainActor @Sendable (String) -> Void = { shown.any = true; onText($0) }
        do { return try await streamAttempt(body, onText: track) }
        catch ClientError.busy where !shown.any { try await Task.sleep(for: .seconds(2)) }
        catch ClientError.offline where !shown.any { try await Task.sleep(for: .seconds(1)) }
        return try await streamAttempt(body, onText: track)
    }

    private func streamAttempt(_ body: Data, onText: @escaping @MainActor @Sendable (String) -> Void) async throws -> Data {
        let request = makeRequest(body)
        let bytes: URLSession.AsyncBytes, response: URLResponse
        do { (bytes, response) = try await session.bytes(for: request) }
        catch is URLError { throw ClientError.offline }
        guard let status = (response as? HTTPURLResponse)?.statusCode else { throw ClientError.invalidResponse }
        guard status == 200 else {
            var data = Data()
            for try await byte in bytes { data.append(byte) }
            throw failure(status: status, data: data)
        }
        var assembler = StreamAssembler()
        do {
            for try await line in bytes.lines {
                guard line.hasPrefix("data:"), let data = line.dropFirst(5).trimmingCharacters(in: .whitespaces).data(using: .utf8),
                      let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                if event["type"] as? String == "error" {
                    let error = event["error"] as? [String: Any]
                    if error?["type"] as? String == "overloaded_error" { throw ClientError.busy }
                    throw ClientError.rejected(error?["message"] as? String ?? "stream error")
                }
                if let delta = assembler.add(event) { await onText(delta) }
            }
        } catch is URLError { throw ClientError.offline }
        guard let result = assembler.message else { throw ClientError.invalidResponse }
        return result
    }

    private func makeRequest(_ body: Data) -> URLRequest {
        var request = URLRequest(url: LunaProxy.messagesURL(for: apiKey))
        request.httpMethod = "POST"
        request.httpBody = body
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        return request
    }

    private func attempt(_ body: Data) async throws -> Data {
        let request = makeRequest(body)
        let data: Data, response: URLResponse
        do { (data, response) = try await session.data(for: request) }
        catch is URLError { throw ClientError.offline }
        guard let status = (response as? HTTPURLResponse)?.statusCode else { throw ClientError.invalidResponse }
        if status == 200 { return data }
        throw failure(status: status, data: data)
    }

    private func failure(status: Int, data: Data) -> ClientError {
        // The Luna proxy marks its spend caps so they show their message instead of a retry (CHAT_SPEC §8).
        if status == 429, let error = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? [String: Any],
           error["type"] as? String == "luna_cap_error", let message = error["message"] as? String { return .limit(message) }
        return switch status {
        case 401, 403: LunaProxy.isProxyToken(apiKey) ? .deviceRejected : .unauthorized
        case 429, 500...599: .busy
        default: .rejected(Self.message(in: data) ?? "HTTP \(status)")
        }
    }

    private static func message(in data: Data) -> String? {
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        return (json?["error"] as? [String: Any])?["message"] as? String
    }
}

/// Builds the complete message out of Messages API stream events. Text, tool_use input (partial JSON) and thinking
/// (with its signature) all come back exactly as a non-streaming response would carry them.
struct StreamAssembler {
    private(set) var message: Data?
    private var head: [String: Any] = [:]
    private var blocks: [Int: [String: Any]] = [:]
    private var partialJSON: [Int: String] = [:]

    /// Feeds one event; returns the text delta when the event carried one.
    mutating func add(_ event: [String: Any]) -> String? {
        let index = event["index"] as? Int ?? 0
        switch event["type"] as? String {
        case "message_start":
            head = event["message"] as? [String: Any] ?? [:]
            head["content"] = nil
        case "content_block_start":
            blocks[index] = event["content_block"] as? [String: Any] ?? [:]
        case "content_block_delta":
            let delta = event["delta"] as? [String: Any] ?? [:]
            switch delta["type"] as? String {
            case "text_delta":
                let text = delta["text"] as? String ?? ""
                blocks[index, default: [:]]["text"] = (blocks[index]?["text"] as? String ?? "") + text
                return text.isEmpty ? nil : text
            case "input_json_delta": partialJSON[index, default: ""] += delta["partial_json"] as? String ?? ""
            case "thinking_delta": blocks[index, default: [:]]["thinking"] = (blocks[index]?["thinking"] as? String ?? "") + (delta["thinking"] as? String ?? "")
            case "signature_delta": blocks[index, default: [:]]["signature"] = delta["signature"] as? String ?? ""
            default: break
            }
        case "content_block_stop":
            if let json = partialJSON.removeValue(forKey: index) {
                blocks[index, default: [:]]["input"] = json.isEmpty ? [String: Any]() : ((try? JSONSerialization.jsonObject(with: Data(json.utf8))) ?? [String: Any]())
            }
        case "message_delta":
            let delta = event["delta"] as? [String: Any] ?? [:]
            if let reason = delta["stop_reason"] { head["stop_reason"] = reason }
        case "message_stop":
            head["content"] = blocks.sorted { $0.key < $1.key }.map(\.value)
            message = try? JSONSerialization.data(withJSONObject: head)
        default: break
        }
        return nil
    }
}
