import Foundation

/// Pushes a `LunaSnapshot` to the owner's Luna server after changes (debounced), on foreground, and on demand.
/// Opt-in per part (Settings → Luna). Uses the proxy token already in the Keychain (`lt_…`); a personal API key can't share.
/// ponytail: no retry queue and no background task: the next snapshot repairs a failed one (PLAN §8).
@MainActor @Observable
final class LunaBridge {
    static let enabledKey = "lunaShareEnabled"
    static func partKey(_ part: LunaSnapshot.Part) -> String { "lunaShare" + part.rawValue.capitalized }

    private(set) var isSending = false
    private(set) var lastSync: Date?
    private(set) var lastError: String?

    @ObservationIgnored private weak var model: AppModel?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let session: URLSession
    @ObservationIgnored private var pending: Task<Void, Never>?

    init(model: AppModel, defaults: UserDefaults = .standard, session: URLSession = .shared) {
        self.model = model
        self.defaults = defaults
        self.session = session
        lastSync = defaults.object(forKey: "lunaLastSync") as? Date
    }

    var isEnabled: Bool { defaults.bool(forKey: Self.enabledKey) }

    /// All parts default to on once sharing is enabled.
    var shared: Set<LunaSnapshot.Part> {
        Set(LunaSnapshot.Part.allCases.filter { defaults.object(forKey: Self.partKey($0)) as? Bool ?? true })
    }

    private var storeID: String {
        if let id = defaults.string(forKey: "lunaStoreID") { return id }
        let id = UUID().uuidString
        defaults.set(id, forKey: "lunaStoreID")
        return id
    }

    /// Debounced push; every commit calls this.
    func schedule(after delay: Duration = .seconds(8)) {
        guard isEnabled else { return }
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.push()
        }
    }

    func push() async {
        guard isEnabled, !shared.isEmpty, let model else { return }
        guard let key = APIKeyStore.read(), LunaProxy.isProxyToken(key) else {
            lastError = "Register with an invite code in AI Chat first."
            return
        }
        isSending = true
        defer { isSending = false }
        var request = URLRequest(url: LunaProxy.baseURL.appendingPathComponent("ingest/monocle"))
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        do {
            request.httpBody = try LunaSnapshot.encoder.encode(LunaSnapshot.build(model: model, storeID: storeID, share: shared))
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                lastError = ((json?["error"] as? [String: Any])?["message"] as? String) ?? "Luna rejected the update."
                return
            }
            lastSync = .now
            lastError = nil
            defaults.set(lastSync, forKey: "lunaLastSync")
        } catch is URLError {
            lastError = "Couldn't reach Luna. It will retry on the next change."
        } catch {
            lastError = error.localizedDescription
        }
    }
}
