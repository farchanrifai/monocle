import XCTest
@testable import Monocle

@MainActor
final class WidgetSnapshotTests: XCTestCase {

    func testWidgetSnapshotCodableRoundTrip() throws {
        let original = WidgetSnapshot.sample
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: data)

        XCTAssertEqual(decoded.activeBook.id, original.activeBook.id)
        XCTAssertEqual(decoded.activeBook.name, original.activeBook.name)
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
        let snapshot = WidgetSnapshotStore.loadSnapshot()
        XCTAssertFalse(snapshot.activeBook.name.isEmpty)
        XCTAssertNotNil(snapshot.cycleBudget)
    }

    func testWidgetSnapshotUpdaterCalculations() throws {
        let book = BookProfile(id: UUID(), name: "Personal", kind: .real)
        let cat = ExpenseCategory(id: UUID(), name: "Coffee", symbol: "cup.and.saucer.fill")
        let stack = CardStack(id: UUID(), name: "Daily Living", icon: "bag.fill", cardIDs: [book.id])
        let todayStr = Day.string(.now)

        let expense1 = Expense(
            id: UUID(),
            amount: 35_000_00,
            day: todayStr,
            note: "Espresso",
            allocations: [Allocation(categoryID: cat.id, amount: 35_000_00)],
            source: "manual",
            createdAt: .now,
            bookID: book.id
        )

        let budget = BudgetVersion(
            id: UUID(),
            effectiveDay: "2026-01-01",
            overallLimit: 1_000_000_00,
            startDay: 1,
            bookID: book.id
        )

        let cycle = BudgetCycle.containing(.now, startDay: 1)

        WidgetSnapshotUpdater.update(
            activeBook: book,
            activeStack: stack,
            allBooks: [book],
            expenses: [expense1],
            stackExpenses: [expense1],
            categories: [cat],
            budget: budget,
            cycle: cycle
        )

        let snapshot = WidgetSnapshotStore.loadSnapshot()
        XCTAssertEqual(snapshot.activeBook.name, "Personal")
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
        XCTAssertEqual(snapshot.todaySpending.recentTransactions.first?.bookID, book.id)
    }

    func testWidgetDeepLinkNavigation() throws {
        let model = AppModel.shared
        let bookID = UUID()
        let stackID = UUID()

        // Test openCardInHome
        model.openCardInHome(id: bookID)
        XCTAssertEqual(model.selectedTab, 0)
        XCTAssertFalse(model.showEntry)
        XCTAssertEqual(model.selectedBookID, bookID)

        // Test openStackInHome
        model.createStack(name: "Test Stack", icon: "folder", cardIDs: [bookID])
        if let created = model.stacks.first(where: { $0.name == "Test Stack" }) {
            model.openStackInHome(id: created.id)
            XCTAssertEqual(model.selectedTab, 0)
            XCTAssertFalse(model.showEntry)
            XCTAssertNil(model.selectedBookID)
            XCTAssertEqual(model.activeStackID, created.id)
        }
    }

    func testSpendingSessionManagerLifecycle() {
        let manager = SpendingSessionManager.shared
        manager.startSession(name: "Morning Market", bookName: "Personal", budgetLimit: 200_000_00)

        XCTAssertTrue(manager.isSessionActive)
        XCTAssertEqual(manager.sessionName, "Morning Market")
        XCTAssertEqual(manager.sessionBudgetLimit, 200_000_00)
        XCTAssertEqual(manager.sessionSpent, 0)
        XCTAssertEqual(manager.sessionItemCount, 0)

        manager.recordExpense(amount: 45_000_00, note: "Fresh Bread", categorySymbol: "basket.fill")
        XCTAssertEqual(manager.sessionSpent, 45_000_00)
        XCTAssertEqual(manager.sessionItemCount, 1)
        XCTAssertEqual(manager.latestItemNote, "Fresh Bread")

        manager.recordExpense(amount: 30_000_00, note: "Fruit", categorySymbol: "apple.logo")
        XCTAssertEqual(manager.sessionSpent, 75_000_00)
        XCTAssertEqual(manager.sessionItemCount, 2)

        manager.endSession()
        XCTAssertFalse(manager.isSessionActive)
    }
}
