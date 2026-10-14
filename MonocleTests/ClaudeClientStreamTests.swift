import XCTest
@testable import Monocle

/// Serves canned bytes for any request, so `ClaudeClient.stream` runs its real SSE parsing without a network.
private final class CannedProtocol: URLProtocol {
    nonisolated(unsafe) static var status = 200
    nonisolated(unsafe) static var body = Data()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: ["content-type": "text/event-stream"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@MainActor
final class ClaudeClientStreamTests: XCTestCase {
    private var client: ClaudeClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CannedProtocol.self]
        return ClaudeClient(apiKey: "test", session: URLSession(configuration: configuration))
    }

    private func sse(_ events: [[String: Any]]) -> Data {
        Data(events.map { "event: \($0["type"] as? String ?? "")\ndata: \(String(data: try! JSONSerialization.data(withJSONObject: $0), encoding: .utf8)!)\n\n" }.joined().utf8)
    }

    func testStreamParsesServerSentEventsIntoAMessage() async throws {
        CannedProtocol.status = 200
        CannedProtocol.body = sse([
            ["type": "message_start", "message": ["role": "assistant"]],
            ["type": "content_block_start", "index": 0, "content_block": ["type": "text", "text": ""]],
            ["type": "content_block_delta", "index": 0, "delta": ["type": "text_delta", "text": "Hel"]],
            ["type": "content_block_delta", "index": 0, "delta": ["type": "text_delta", "text": "lo"]],
            ["type": "content_block_stop", "index": 0],
            ["type": "message_delta", "delta": ["stop_reason": "end_turn"]],
            ["type": "message_stop"],
        ])
        var deltas: [String] = []
        let data = try await client.stream(Data("{}".utf8)) { deltas.append($0) }
        XCTAssertEqual(deltas, ["Hel", "lo"])
        let message = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(message["stop_reason"] as? String, "end_turn")
        XCTAssertEqual(((message["content"] as? [[String: Any]])?.first)?["text"] as? String, "Hello")
    }

    func testStreamMapsHTTPAndStreamErrors() async throws {
        CannedProtocol.status = 401
        CannedProtocol.body = Data(#"{"error":{"message":"bad key"}}"#.utf8)
        do { _ = try await client.stream(Data("{}".utf8)) { _ in }; XCTFail("401 must throw") }
        catch ClaudeClient.ClientError.unauthorized {}

        CannedProtocol.status = 200
        CannedProtocol.body = sse([["type": "error", "error": ["type": "invalid_request_error", "message": "too long"]]])
        do { _ = try await client.stream(Data("{}".utf8)) { _ in }; XCTFail("an error event must throw") }
        catch ClaudeClient.ClientError.rejected(let message) { XCTAssertEqual(message, "too long") }
    }
}

final class LunaProxyTests: XCTestCase {
    func testProxyTokenRoutesToTheWorkerAndPersonalKeysStayDirect() {
        XCTAssertEqual(LunaProxy.messagesURL(for: "lt_abc").host, "luna-server.farchan.workers.dev")
        XCTAssertEqual(LunaProxy.messagesURL(for: "lt_abc").path, "/llm/v1/messages")
        XCTAssertEqual(LunaProxy.messagesURL(for: "sk-ant-xyz").absoluteString, "https://api.anthropic.com/v1/messages")
    }

    @MainActor
    func testProxyCapShowsItsOwnMessageInsteadOfBusy() async {
        CannedProtocol.status = 429
        CannedProtocol.body = Data(#"{"type":"error","error":{"type":"luna_cap_error","message":"Today's AI limit for this device is used up."}}"#.utf8)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CannedProtocol.self]
        let client = ClaudeClient(apiKey: "lt_test", session: URLSession(configuration: configuration))
        do { _ = try await client.stream(Data("{}".utf8)) { _ in }; XCTFail("expected a limit error") }
        catch { XCTAssertEqual(error.localizedDescription, "Today's AI limit for this device is used up.") }
    }

    @MainActor
    func testRevokedProxyTokenAsksToRegisterAgain() async {
        CannedProtocol.status = 401
        CannedProtocol.body = Data("{}".utf8)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CannedProtocol.self]
        let client = ClaudeClient(apiKey: "lt_test", session: URLSession(configuration: configuration))
        do { _ = try await client.stream(Data("{}".utf8)) { _ in }; XCTFail("expected a rejection") }
        catch ClaudeClient.ClientError.deviceRejected {}
        catch { XCTFail("wrong error \(error)") }
    }
}
