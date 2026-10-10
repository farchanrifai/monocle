import XCTest
@testable import Monocle

@MainActor
final class WidgetSnapshotTests: XCTestCase {

    func testWidgetSnapshotCodableRoundTrip() throws {
        let original = WidgetSnapshot.sample
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: data)

        XCTAssertEqual(decoded.activeCard.id, original.activeCard.id)
        XCTAssertEqual(decoded.activeCard.name, original.activeCard.name)
        XCTAssertEqual(decoded.activeStack?.id, original.activeStack?.id)
        XCTAssertEqual(decoded.activeStack?.name, original.activeStack?.name)
        XCTAssertEqual(decoded.activeStack?.cardCount, original.activeStack?.cardCount)
        XCTAssertEqual(decoded.cycleBudget?.limit, original.cycleBudget?.limit)
        XCTAssertEqual(decoded.cycleBudget?.spent, original.cycleBudget?.spent)
        XCTAssertEqual(decoded.cycleBudget?.remaining, original.cycleBudget?.remaining)
        XCTAssertEqual(decoded.todaySpending.totalSpent, original.todaySpending.totalSpent)
        XCTAssertEqual(decoded.todaySpending.recentTransactions.count, original.todaySpending.recentTransactions.count)
        XCTAssertEqual(decoded.quickCategories.count, original.quickCategories.count)
    }

    func testWidgetSnapshotStoreFallbackWhenEmpty() {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let snapshot = WidgetSnapshotStore.loadSnapshot(from: missing)
        XCTAssertFalse(snapshot.activeCard.name.isEmpty)
        XCTAssertNotNil(snapshot.unavailableReason)
        XCTAssertNil(snapshot.cycleBudget)
    }

    func testWidgetSnapshotUpdaterCalculations() throws {
        let card = Card(id: UUID(), name: "Personal", kind: .real)
        let cat = ExpenseCategory(id: UUID(), name: "Coffee", symbol: "cup.and.saucer.fill")
        let stack = Stack(id: UUID(), name: "Daily Living", icon: "bag.fill", cardIDs: [card.id])
        let todayStr = Day.string(.now)

        let expense1 = Expense(
            id: UUID(),
            amount: 35_000_00,
            day: todayStr,
            note: "Espresso",
            splits: [Split(categoryID: cat.id, amount: 35_000_00)],
            source: "manual",
            createdAt: .now,
            cardID: card.id
        )

        let budget = BudgetVersion(
            id: UUID(),
            effectiveDay: "2026-01-01",
            overallLimit: 1_000_000_00,
            startDay: 1,
            cardID: card.id
        )

        let cycle = Cycle.containing(.now, startDay: 1)

        let snapshot = WidgetSnapshotUpdater.update(
            activeCard: card,
            activeStack: stack,
            allCards: [card],
            expenses: [expense1],
            stackExpenses: [expense1],
            categories: [cat],
            budget: budget,
            cycle: cycle
        )

        XCTAssertEqual(snapshot.activeCard.name, "Personal")
        XCTAssertEqual(snapshot.activeStack?.name, "Daily Living")
        XCTAssertEqual(snapshot.activeStack?.totalSpent, 35_000_00)
        XCTAssertEqual(snapshot.activeStack?.cardCount, 1)
        XCTAssertEqual(snapshot.activeStack?.cardNames, ["Personal"])
        if let cycleBudget = snapshot.cycleBudget {
            XCTAssertEqual(cycleBudget.limit, 1_000_000_00)
            XCTAssertEqual(cycleBudget.spent, 35_000_00)
            XCTAssertEqual(cycleBudget.remaining, 965_000_00)
            XCTAssertGreaterThan(cycleBudget.daysRemaining, 0)
        }
        XCTAssertEqual(snapshot.todaySpending.totalSpent, 35_000_00)
        XCTAssertEqual(snapshot.todaySpending.transactionCount, 1)
        XCTAssertEqual(snapshot.todaySpending.recentTransactions.first?.title, "Espresso")
        XCTAssertEqual(snapshot.todaySpending.recentTransactions.first?.cardID, card.id)
    }

    func testWidgetDeepLinkNavigation() throws {
        let model = AppModel.shared
        let cardID = try XCTUnwrap(model.cards.first?.id)
        let stackID = UUID()

        // Test openCardInHome
        model.openCardInHome(id: cardID)
        XCTAssertEqual(model.selectedTab, 0)
        XCTAssertFalse(model.showEntry)
        XCTAssertEqual(model.selectedCardID, cardID)

        // Test openStackInHome
        try model.createStack(name: "Test Stack", icon: "folder", cardIDs: [cardID])
        if let created = model.stacks.first(where: { $0.name == "Test Stack" }) {
            model.openStackInHome(id: created.id)
            XCTAssertEqual(model.selectedTab, 0)
            XCTAssertFalse(model.showEntry)
            XCTAssertNil(model.selectedCardID)
            XCTAssertEqual(model.activeStackID, created.id)
        }
    }

    func testSpendingSessionManagerLifecycle() {
        let manager = SpendingSessionManager.shared
        let cardID = UUID()
        manager.startSession(name: "Morning Market", cardName: "Personal", cardID: cardID, budgetLimit: 200_000_00)

        XCTAssertTrue(manager.isSessionActive)
        XCTAssertEqual(manager.sessionName, "Morning Market")
        XCTAssertEqual(manager.sessionBudgetLimit, 200_000_00)
        XCTAssertEqual(manager.sessionSpent, 0)
        XCTAssertEqual(manager.sessionItemCount, 0)

        manager.recordExpense(amount: 45_000_00, note: "Other card", categorySymbol: "basket.fill", cardID: UUID())
        XCTAssertEqual(manager.sessionSpent, 0)
        XCTAssertEqual(manager.sessionItemCount, 0)

        manager.recordExpense(amount: 45_000_00, note: "Fresh Bread", categorySymbol: "basket.fill", cardID: cardID)
        XCTAssertEqual(manager.sessionSpent, 45_000_00)
        XCTAssertEqual(manager.sessionItemCount, 1)
        XCTAssertEqual(manager.latestItemNote, "Fresh Bread")

        manager.recordExpense(amount: 30_000_00, note: "Fruit", categorySymbol: "apple.logo", cardID: cardID)
        XCTAssertEqual(manager.sessionSpent, 75_000_00)
        XCTAssertEqual(manager.sessionItemCount, 2)

        manager.endSession()
        XCTAssertFalse(manager.isSessionActive)
    }
}
