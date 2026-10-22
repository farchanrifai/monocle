import XCTest
@testable import Anka

@MainActor
final class BillTests: XCTestCase {

    func testBillValidation() throws {
        let cardID = UUID()
        let catID = UUID()
        let categories = [ExpenseCategory(id: catID, name: "Bills", symbol: "bolt")]

        // Valid monthly bill
        let validRule = Bill(
            cardID: cardID,
            name: "Internet",
            amount: 350_000_00,
            categoryID: catID,
            recurrence: .monthly(day: 15)
        )
        XCTAssertNoThrow(try validRule.validate(categories: categories))

        // Empty name
        var invalidNameRule = validRule
        invalidNameRule.name = "   "
        XCTAssertThrowsError(try invalidNameRule.validate(categories: categories)) { error in
            XCTAssertEqual(error as? BillError, .invalidName)
        }

        // Name too long (> 40 chars)
        var longNameRule = validRule
        longNameRule.name = String(repeating: "A", count: 41)
        XCTAssertThrowsError(try longNameRule.validate(categories: categories)) { error in
            XCTAssertEqual(error as? BillError, .invalidName)
        }

        // Amount <= 0
        var zeroAmountRule = validRule
        zeroAmountRule.amount = 0
        XCTAssertThrowsError(try zeroAmountRule.validate(categories: categories)) { error in
            XCTAssertEqual(error as? BillError, .invalidAmount)
        }

        // Category not in card
        var missingCatRule = validRule
        missingCatRule.categoryID = UUID()
        XCTAssertThrowsError(try missingCatRule.validate(categories: categories)) { error in
            XCTAssertEqual(error as? BillError, .missingCategory)
        }

        // Invalid recurrence: day > 31
        var invalidDayRule = validRule
        invalidDayRule.recurrence = .monthly(day: 32)
        XCTAssertThrowsError(try invalidDayRule.validate(categories: categories)) { error in
            XCTAssertEqual(error as? BillError, .invalidRecurrence)
        }

        // Invalid reminder: > 30 lead days
        var invalidReminderRule = validRule
        invalidReminderRule.reminderLeadDays = 31
        XCTAssertThrowsError(try invalidReminderRule.validate(categories: categories)) { error in
            XCTAssertEqual(error as? BillError, .invalidReminder)
        }
    }

    func testReconciliationEngineDueDaysCalculation() throws {
        let cardID = UUID()
        let catID = UUID()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let start = try XCTUnwrap(Day.date("2026-01-01", calendar: calendar))
        let end = try XCTUnwrap(Day.date("2026-03-31", calendar: calendar))

        // Test Monthly on day 15
        let monthlyRule = Bill(
            cardID: cardID,
            name: "Gym",
            amount: 500_000_00,
            categoryID: catID,
            recurrence: .monthly(day: 15),
            createdAt: start
        )
        let monthlyDays = BillReconciliationEngine.dueDays(for: monthlyRule, from: start, to: end, calendar: calendar)
        XCTAssertEqual(monthlyDays, ["2026-01-15", "2026-02-15", "2026-03-15"])

        // Test Month-end clamping (day 31 in February)
        let monthEndRule = Bill(
            cardID: cardID,
            name: "Rent",
            amount: 5_000_000_00,
            categoryID: catID,
            recurrence: .monthly(day: 31),
            createdAt: start
        )
        let monthEndDays = BillReconciliationEngine.dueDays(for: monthEndRule, from: start, to: end, calendar: calendar)
        XCTAssertEqual(monthEndDays, ["2026-01-31", "2026-02-28", "2026-03-31"])

        // Test Weekly on Mondays (weekday: 2)
        let weekStart = try XCTUnwrap(Day.date("2026-09-01", calendar: calendar))
        let weekEnd = try XCTUnwrap(Day.date("2026-09-22", calendar: calendar))
        let weeklyRule = Bill(
            cardID: cardID,
            name: "Weekly Allowance",
            amount: 200_000_00,
            categoryID: catID,
            recurrence: .weekly(weekday: 2),
            createdAt: weekStart
        )
        let weeklyDays = BillReconciliationEngine.dueDays(for: weeklyRule, from: weekStart, to: weekEnd, calendar: calendar)
        XCTAssertEqual(weeklyDays, ["2026-09-07", "2026-09-14", "2026-09-21"])
    }

    func testReconciliationIdempotency() throws {
        let cardID = UUID()
        let catID = UUID()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let asOf = try XCTUnwrap(Day.date("2026-09-10", calendar: calendar))
        let created = try XCTUnwrap(Day.date("2026-09-01", calendar: calendar))

        let rule = Bill(
            cardID: cardID,
            name: "Streaming",
            amount: 150_000_00,
            categoryID: catID,
            recurrence: .monthly(day: 5),
            recordingMode: .automatic,
            createdAt: created
        )

        // First reconciliation: missed day 2026-09-05 produces 1 occurrence and 1 expense
        let firstResult = BillReconciliationEngine.reconcile(
            rule: rule,
            existingOccurrences: [],
            asOf: asOf,
            lookaheadDays: 14,
            calendar: calendar
        )

        XCTAssertFalse(firstResult.newOccurrences.isEmpty)
        XCTAssertEqual(firstResult.autoExpenses.count, 1)
        XCTAssertEqual(firstResult.autoExpenses.first?.day, "2026-09-05")

        // Second reconciliation with existing occurrences produces 0 new occurrences and 0 expenses
        let secondResult = BillReconciliationEngine.reconcile(
            rule: rule,
            existingOccurrences: firstResult.newOccurrences,
            asOf: asOf,
            lookaheadDays: 14,
            calendar: calendar
        )

        XCTAssertTrue(secondResult.newOccurrences.isEmpty)
        XCTAssertTrue(secondResult.autoExpenses.isEmpty)
    }

    func testAutomaticModeCreatesExpenseAndMarksOccurrenceRecorded() throws {
        let store = try ExpenseRepository(inMemory: true)
        try store.prepareSampleCard()
        let service = try ExpenseService(store: store)
        let cardID = service.activeCardID
        let catID = try XCTUnwrap(service.categories.first?.id)

        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: .now)!
        let yesterdayDay = Calendar.current.component(.day, from: yesterday)

        let bill = Bill(
            cardID: cardID,
            name: "Cloud Storage",
            amount: 45_000_00,
            categoryID: catID,
            recurrence: .monthly(day: yesterdayDay),
            recordingMode: .automatic,
            createdAt: yesterday
        )

        try service.saveBill(bill)

        // Verify occurrence is recorded and linked to an auto expense
        let occurrences = service.billOccurrences
        let recordedOcc = occurrences.first { $0.billRuleID == bill.id && $0.dueDay == Day.string(yesterday) }
        XCTAssertNotNil(recordedOcc)
        XCTAssertEqual(recordedOcc?.status, .recorded)
        XCTAssertNotNil(recordedOcc?.expenseID)

        // Verify expense is present in store
        let matchingExpense = service.expenses.first { $0.id == recordedOcc?.expenseID }
        XCTAssertNotNil(matchingExpense)
        XCTAssertEqual(matchingExpense?.amount, 45_000_00)
        XCTAssertEqual(matchingExpense?.source, "bill-automatic")
    }

    func testPauseDropsLookaheadAndResumeDoesNotBackfill() throws {
        let store = try ExpenseRepository(inMemory: true)
        try store.prepareSampleCard()
        let service = try ExpenseService(store: store)
        let start = Day.date("2026-01-01")!
        var bill = Bill(cardID: service.activeCardID, name: "Gym", amount: 300_000_00,
                            categoryID: try XCTUnwrap(service.categories.first?.id),
                            recurrence: .monthly(day: 15), recordingMode: .automatic, createdAt: start)
        try service.saveBill(bill, asOf: Day.date("2026-01-10")!)
        XCTAssertEqual(service.billOccurrences.filter { $0.status == .pending }.map(\.dueDay), ["2026-01-15"])

        bill.isActive = false
        try service.saveBill(bill, asOf: Day.date("2026-01-10")!)
        XCTAssertTrue(service.billOccurrences.isEmpty, "pausing removes upcoming occurrences")
        try service.reconcileBills(asOf: Day.date("2026-04-01")!)
        XCTAssertTrue(service.billOccurrences.isEmpty, "paused bills generate nothing")

        bill.isActive = true
        try service.saveBill(bill, asOf: Day.date("2026-04-01")!)
        XCTAssertTrue(service.expenses.filter { $0.source == "bill-automatic" }.isEmpty,
                      "Jan–Mar are not backfilled on resume")
        XCTAssertEqual(service.billOccurrences.map(\.dueDay), ["2026-04-15"])
    }

    func testClearingTransactionsDoesNotRecreateAutomaticBills() throws {
        let store = try ExpenseRepository(inMemory: true)
        try store.prepareSampleCard()
        let service = try ExpenseService(store: store)
        let due = Calendar.current.date(byAdding: .day, value: -1, to: .now)!
        let bill = Bill(
            cardID: service.activeCardID,
            name: "Cloud Storage",
            amount: 45_000_00,
            categoryID: try XCTUnwrap(service.categories.first?.id),
            recurrence: .monthly(day: Calendar.current.component(.day, from: due)),
            recordingMode: .automatic,
            createdAt: due
        )
        try service.saveBill(bill)
        XCTAssertFalse(service.expenses.isEmpty)

        try store.clearExpenses(in: service.activeCardID)
        try service.reload()
        try service.reconcileBills()

        XCTAssertTrue(service.expenses.isEmpty)
        let occurrence = try XCTUnwrap(service.billOccurrences.first { $0.billRuleID == bill.id && $0.dueDay == Day.string(due) })
        XCTAssertEqual(occurrence.status, .skipped)
        XCTAssertNil(occurrence.expenseID)
    }

    func testPendingModeRequiresConfirmationAndSkippingWorks() throws {
        let store = try ExpenseRepository(inMemory: true)
        try store.prepareSampleCard()
        let service = try ExpenseService(store: store)
        let cardID = service.activeCardID
        let catID = try XCTUnwrap(service.categories.first?.id)

        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: .now)!
        let yesterdayDay = Calendar.current.component(.day, from: yesterday)

        let bill = Bill(
            cardID: cardID,
            name: "Electricity",
            amount: 850_000_00,
            categoryID: catID,
            recurrence: .monthly(day: yesterdayDay),
            recordingMode: .pending,
            createdAt: yesterday
        )

        try service.saveBill(bill)

        // Pending mode should NOT produce an expense immediately
        XCTAssertTrue(service.expenses.isEmpty)

        let pendingOcc = try XCTUnwrap(service.billOccurrences.first { $0.billRuleID == bill.id })
        XCTAssertEqual(pendingOcc.status, .pending)
        XCTAssertNil(pendingOcc.expenseID)

        // Confirm occurrence
        let expense = try service.confirmBillOccurrence(pendingOcc.id)
        XCTAssertEqual(expense.amount, 850_000_00)
        XCTAssertEqual(expense.source, "bill-confirmed")
        XCTAssertEqual(service.expenses.count, 1)

        let updatedOcc = try XCTUnwrap(service.billOccurrences.first { $0.id == pendingOcc.id })
        XCTAssertEqual(updatedOcc.status, .recorded)
        XCTAssertEqual(updatedOcc.expenseID, expense.id)

        // Test Skipping another bill occurrence
        let bill2 = Bill(
            cardID: cardID,
            name: "Magazine",
            amount: 50_000_00,
            categoryID: catID,
            recurrence: .monthly(day: yesterdayDay),
            recordingMode: .pending,
            createdAt: yesterday
        )
        try service.saveBill(bill2)

        let occ2 = try XCTUnwrap(service.billOccurrences.first { $0.billRuleID == bill2.id })
        XCTAssertEqual(occ2.status, .pending)

        try service.skipBillOccurrence(occ2.id)

        let skippedOcc = try XCTUnwrap(service.billOccurrences.first { $0.id == occ2.id })
        XCTAssertEqual(skippedOcc.status, .skipped)

        // Re-reconcile to ensure skipped occurrence remains skipped and is not re-created
        try service.reconcileBills()
        let postReconcileOcc = try XCTUnwrap(service.billOccurrences.first { $0.id == occ2.id })
        XCTAssertEqual(postReconcileOcc.status, .skipped)
    }

    func testMultiCardBillIsolation() throws {
        let store = try ExpenseRepository(inMemory: true)
        let cardA = try store.createCard(named: "Book A")
        let cardB = try store.createCard(named: "Book B")

        let catA = try XCTUnwrap(try store.categories(in: cardA.id).first)
        let catB = try XCTUnwrap(try store.categories(in: cardB.id).first)

        let billA = Bill(
            cardID: cardA.id,
            name: "Bill in A",
            amount: 100_000_00,
            categoryID: catA.id,
            recurrence: .monthly(day: 1)
        )
        let billB = Bill(
            cardID: cardB.id,
            name: "Bill in B",
            amount: 200_000_00,
            categoryID: catB.id,
            recurrence: .monthly(day: 15)
        )

        try store.saveBill(billA, in: cardA.id)
        try store.saveBill(billB, in: cardB.id)

        let billsInA = try store.bills(in: cardA.id)
        let billsInB = try store.bills(in: cardB.id)

        XCTAssertEqual(billsInA.count, 1)
        XCTAssertEqual(billsInA.first?.name, "Bill in A")
        XCTAssertEqual(billsInB.count, 1)
        XCTAssertEqual(billsInB.first?.name, "Bill in B")

        // Deleting card A removes bill A
        try store.deleteCard(id: cardA.id)
        let remainingBillsInB = try store.bills(in: cardB.id)
        XCTAssertEqual(remainingBillsInB.count, 1)
        XCTAssertEqual(remainingBillsInB.first?.name, "Bill in B")
    }

    func testWorkspaceBackupFormatSixRoundTrip() throws {
        let store = try ExpenseRepository(inMemory: true)
        try store.prepareSampleCard()
        let service = try ExpenseService(store: store)
        let cardID = service.activeCardID
        let catID = try XCTUnwrap(service.categories.first?.id)

        let bill = Bill(
            cardID: cardID,
            name: "Water Utility",
            amount: 120_000_00,
            categoryID: catID,
            recurrence: .monthly(day: 20),
            recordingMode: .pending
        )
        try service.saveBill(bill)

        let occ = BillOccurrence(
            billRuleID: bill.id,
            cardID: cardID,
            dueDay: "2026-09-20",
            status: .pending
        )
        try store.saveOccurrence(occ, in: cardID)

        let backupService = BackupService(
            directory: FileManager.default.temporaryDirectory,
            repository: store,
            state: FileLocalStateStore(directory: FileManager.default.temporaryDirectory),
            expenses: service
        )

        let snapshot = try backupService.workspaceSnapshot(currentDraft: ExpenseDraft(), settings: PrototypeSettings())
        XCTAssertEqual(snapshot.formatVersion, WorkspaceBackup.currentFormat)

        // Encode and decode
        let encodedData = try snapshot.encoded()
        let decoded = try WorkspaceBackup.decode(encodedData)
        XCTAssertEqual(decoded.formatVersion, WorkspaceBackup.currentFormat)

        let restoredCard = try XCTUnwrap(decoded.cards.first { $0.card.id == cardID })
        XCTAssertEqual(restoredCard.bills?.count, 1)
        XCTAssertEqual(restoredCard.bills?.first?.name, "Water Utility")

        // Restore into clean repository
        let newStore = try ExpenseRepository(inMemory: true)
        try newStore.replace(with: decoded)

        let restoredBills = try newStore.bills(in: cardID)
        let restoredOccurrences = try newStore.billOccurrences(in: cardID)

        XCTAssertEqual(restoredBills.count, 1)
        XCTAssertEqual(restoredBills.first?.name, "Water Utility")
        XCTAssertFalse(restoredOccurrences.isEmpty)
    }

    func testFormatFiveBackupBackwardCompatibility() throws {
        // Construct a legacy Format 5 WorkspaceBackup (which had no bills)
        let card = Card(id: UUID(), name: "Legacy Book")
        let item = CardBackupItem(
            card: card,
            categories: ExpenseCategory.defaults,
            expenses: [],
            budgets: [],
            draft: nil,
            bills: nil,
            billOccurrences: nil
        )
        let legacyBackup = WorkspaceBackup(
            formatVersion: 5,
            exportedAt: .now,
            currency: "IDR",
            minorUnitScale: 2,
            cards: [item]
        )

        let encoded = try legacyBackup.encoded()
        let decoded = try WorkspaceBackup.decode(encoded)
        XCTAssertEqual(decoded.formatVersion, 5)
        XCTAssertEqual(decoded.cards.first?.bills, nil)
    }
}

extension BillTests {
    func testAutomaticLookaheadPromotesPendingWhenDue() throws {
        let card = UUID(), category = UUID()
        let created = try XCTUnwrap(Day.date("2026-09-01"))
        let due = try XCTUnwrap(Day.date("2026-09-15"))
        let rule = Bill(cardID: card, name: "Rent", amount: 10000, categoryID: category,
                            recurrence: .monthly(day: 15), recordingMode: .automatic, createdAt: created)
        let preview = BillReconciliationEngine.reconcile(rule: rule, existingOccurrences: [], asOf: created)
        let pending = try XCTUnwrap(preview.newOccurrences.first)
        XCTAssertEqual(pending.status, .pending)
        let result = BillReconciliationEngine.reconcile(rule: rule, existingOccurrences: preview.newOccurrences, asOf: due)
        XCTAssertEqual(result.autoExpenses.count, 1)
        XCTAssertEqual(result.newOccurrences.first?.id, pending.id)
        XCTAssertEqual(result.newOccurrences.first?.status, .recorded)
        let again = BillReconciliationEngine.reconcile(rule: rule, existingOccurrences: result.newOccurrences, asOf: due)
        XCTAssertTrue(again.autoExpenses.isEmpty)
    }

    func testResolvedBillCannotBeRecordedOrSkippedAgain() throws {
        let store = try ExpenseRepository(inMemory: true)
        try store.prepareSampleCard()
        let service = try ExpenseService(store: store)
        let bill = Bill(cardID: service.activeCardID, name: "Rent", amount: 10000,
                            categoryID: try XCTUnwrap(service.categories.first?.id), recurrence: .monthly(day: 1))
        try service.saveBill(bill)
        let occurrence = BillOccurrence(billRuleID: bill.id, cardID: bill.cardID, dueDay: Day.string(.now))
        try store.saveOccurrence(occurrence)
        _ = try service.confirmBillOccurrence(occurrence.id)
        XCTAssertThrowsError(try service.confirmBillOccurrence(occurrence.id))
        XCTAssertThrowsError(try service.skipBillOccurrence(occurrence.id))
        XCTAssertEqual(service.expenses.count, 1)
    }

    func testOccurrenceDeletionIsScopedToCard() throws {
        let store = try ExpenseRepository(inMemory: true)
        let a = try store.createCard(named: "A"), b = try store.createCard(named: "B")
        let rule = Bill(cardID: a.id, name: "Rent", amount: 10000,
                            categoryID: try XCTUnwrap(store.categories(in: a.id).first?.id), recurrence: .monthly(day: 1))
        try store.saveBill(rule)
        let occurrence = BillOccurrence(billRuleID: rule.id, cardID: a.id, dueDay: "2026-09-01")
        try store.saveOccurrence(occurrence)
        try store.deleteOccurrence(occurrence.id, in: b.id)
        XCTAssertEqual(try store.billOccurrences(in: a.id).count, 1)
        XCTAssertThrowsError(try store.deleteCategory(rule.categoryID, in: a.id))
    }

    func testBatchImportRollsBackEarlierRowsOnFailure() throws {
        let store = try ExpenseRepository(inMemory: true)
        try store.prepareSampleCard()
        let service = try ExpenseService(store: store)
        let category = try XCTUnwrap(service.categories.first?.id)
        let valid = Expense(amount: 10000, day: "2026-09-01", note: "Valid",
                            splits: [.init(categoryID: category, amount: 10000)])
        var invalid = valid
        invalid.id = UUID()
        invalid.amount = -1
        XCTAssertThrowsError(try service.saveExpenses([valid, invalid]))
        XCTAssertTrue(try store.expenses().isEmpty)
        XCTAssertTrue(service.expenses.isEmpty)
    }
}
