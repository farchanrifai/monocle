import StoreKit
import StoreKitTest
import XCTest
@testable import Ankka

/// The subscription against the local StoreKit configuration: no App Store, no account.
@MainActor
final class ProStoreTests: XCTestCase {
    private var session: SKTestSession!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        session = try SKTestSession(configurationFileNamed: "Ankka")
        session.resetToDefaultState()
        session.clearTransactions()
        session.disableDialogs = true
        defaults = UserDefaults(suiteName: UUID().uuidString)
    }

    /// StoreKit testing refuses unsigned and ad-hoc builds (`notEntitled`); it needs a team-signed build.
    private func requireStoreKitTesting() async throws {
        let products = try await Product.products(for: ProStore.productIDs)
        try XCTSkipIf(products.isEmpty, "StoreKit testing needs a build signed with a development team")
    }

    override func tearDown() async throws { session.clearTransactions() }

    func testBothPlansExistWithAFreeWeek() async throws {
        try await requireStoreKitTesting()
        let products = try await Product.products(for: ProStore.productIDs)
        XCTAssertEqual(Set(products.map(\.id)), Set(ProStore.productIDs))
        for product in products {
            XCTAssertEqual(product.subscription?.introductoryOffer?.paymentMode, .freeTrial, product.id)
            XCTAssertEqual(product.subscription?.introductoryOffer?.period.unit, .week, product.id)
            XCTAssertEqual(product.subscription?.introductoryOffer?.period.value, 1, product.id)
        }
    }

    func testPurchaseUnlocksProAndExpiryLocksIt() async throws {
        try await requireStoreKitTesting()
        let store = ProStore(defaults: defaults, listen: false)
        await store.refresh()
        XCTAssertFalse(store.isPro)

        // The test session buys without a payment sheet; Product.purchase() would wait for one.
        let yearly = "com.farchan.ankka.pro.yearly"
        try await session.buyProduct(identifier: yearly)
        await store.refresh()
        XCTAssertTrue(store.isPro)
        XCTAssertTrue(defaults.bool(forKey: ProStore.cacheKey), "widgets read the cached state")

        try session.expireSubscription(productIdentifier: yearly)
        await store.refresh()
        XCTAssertFalse(store.isPro)
    }

    func testTheModelsPlanFollowsTheStore() async throws {
        let repo = try ExpenseRepository(inMemory: true)
        try repo.prepareSampleCard()
        let service = try ExpenseService(store: repo)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = AppModel(expenses: service, state: FileLocalStateStore(directory: directory))
        XCTAssertNil(service.plan, "no store, no limits")
        XCTAssertTrue(model.isPro)

        model.pro = ProStore(defaults: defaults, listen: false)
        XCTAssertEqual(service.plan, Plan(isPro: false, keptCardID: model.keptCardID))
        XCTAssertFalse(model.requirePro("Analytics is part of Pro."))
        XCTAssertEqual(model.paywall, "Analytics is part of Pro.")

        model.report(PlanError.cardLimit)
        XCTAssertEqual(model.paywall, PlanError.cardLimit.localizedDescription)
        model.report(PlanError.sampleLimit)
        XCTAssertEqual(model.error, PlanError.sampleLimit.localizedDescription, "the Sample card cap is an alert, not an upsell")
    }
}
