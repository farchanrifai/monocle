import Foundation
import Observation
import StoreKit
import WidgetKit

/// The Pro subscription, from StoreKit 2. Products, prices and the trial live in App Store Connect;
/// `Configuration/Anka.storekit` mirrors them for local runs and tests.
@MainActor @Observable
final class ProStore {
    static let productIDs = ["com.farchan.anka.pro.yearly", "com.farchan.anka.pro.monthly"]

    private(set) var isPro: Bool
    /// Called after `isPro` changes; AppModel turns it into the ledger's plan.
    @ObservationIgnored var onChange: (@MainActor () -> Void)?
    @ObservationIgnored private var updates: Task<Void, Never>?
    @ObservationIgnored private let defaults: UserDefaults

    /// Starts from the last known state so launch doesn't flash Free, then asks StoreKit.
    init(defaults: UserDefaults = UserDefaults(suiteName: "group.com.farchan.anka") ?? .standard, listen: Bool = true) {
        self.defaults = defaults
        isPro = defaults.bool(forKey: Self.cacheKey)
        guard listen else { return }
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let transaction) = result { await transaction.finish() }
                await self?.refresh()
            }
        }
        Task { await refresh() }
    }

    /// The app group key widgets read to show Pro content.
    static let cacheKey = "isPro"

    func refresh() async {
        var active = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result, Self.productIDs.contains(transaction.productID), transaction.revocationDate == nil {
                active = true
            }
        }
        #if DEBUG
        // -ankaPro YES / NO forces a plan for local runs and UI tests.
        if let forced = UserDefaults.standard.object(forKey: "ankaPro") as? Bool { active = forced }
        #endif
        #if DEBUG && ANKA_FORCE_PRO
        active = true // the owner's free-team phone build: StoreKit can't sell to it
        #endif
        set(active)
    }

    /// Restore: asks the App Store to resend this Apple Account's transactions.
    func restore() async throws {
        try await AppStore.sync()
        await refresh()
    }

    private func set(_ value: Bool) {
        defaults.set(value, forKey: Self.cacheKey)
        guard value != isPro else { return }
        isPro = value
        WidgetCenter.shared.reloadAllTimelines() // widgets show Pro content or the lock
        onChange?()
    }
}
