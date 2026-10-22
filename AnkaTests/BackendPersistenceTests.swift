import CoreData
import Darwin
import XCTest
@testable import Anka

@MainActor
final class BackendPersistenceTests: XCTestCase {
    private func fixture() throws -> (URL, ExpenseRepository) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("backend-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return (directory, try ExpenseRepository(url: directory.appendingPathComponent("ledger.sqlite")))
    }

    private func reopen(_ repository: ExpenseRepository, directory: URL) throws -> ExpenseRepository {
        repository.container.viewContext.reset()
        for store in repository.container.persistentStoreCoordinator.persistentStores {
            try repository.container.persistentStoreCoordinator.remove(store)
        }
        return try ExpenseRepository(url: directory.appendingPathComponent("ledger.sqlite"))
    }

    private func expense(card: UUID, category: UUID, amount: Int64 = 10_000, day: String = "2026-01-15") -> Expense {
        Expense(amount: amount, day: day, note: "Fixture", splits: [.init(categoryID: category, amount: amount)], cardID: card)
    }

    func testBudgetOnlyCategoryRetainsEveryHistoricalReferenceAfterReopenAndExport() throws {
        let (directory, repository) = try fixture()
        let card = try repository.createCard(named: "History")
        let category = ExpenseCategory(id: UUID(), name: "Historical", symbol: "book")
        try repository.saveCategory(category, in: card.id)
        for day in ["2026-01-01", "2026-02-01"] {
            try repository.save(BudgetVersion(effectiveDay: day, overallLimit: 100_000, startDay: 1,
                categoryLimits: [.init(categoryID: category.id, limit: 50_000)], cardID: card.id), in: card.id)
        }
        try repository.deactivateCategory(category.id, in: card.id)
        XCTAssertThrowsError(try repository.deleteCategory(category.id, in: card.id))
        let reopened = try reopen(repository, directory: directory)
        XCTAssertTrue(try reopened.categories(in: card.id).contains { $0.id == category.id })
        XCTAssertEqual(try reopened.budgets(in: card.id).count, 2)
        let service = try ExpenseService(store: reopened)
        let backups = BackupService(directory: directory, repository: reopened,
                                    state: FileLocalStateStore(directory: directory), expenses: service)
        var settings = PrototypeSettings(); settings.card = card
        var draft = ExpenseDraft(); draft.cardID = card.id
        let snapshot = try backups.workspaceSnapshot(currentDraft: draft, settings: settings)
        XCTAssertNoThrow(try WorkspaceBackup.decode(snapshot.encoded()))
    }

    func testBillExpenseDeleteSuppressesRecreationAndUndoRestoresOriginalLinkOnDisk() throws {
        let (directory, repository) = try fixture()
        let card = try repository.createCard(named: "Bills")
        let category = try XCTUnwrap(repository.categories(in: card.id).first)
        let service = try ExpenseService(store: repository)
        let january = try XCTUnwrap(Day.date("2026-01-15"))
        let rule = Bill(cardID: card.id, name: "Rent", amount: 10_000, categoryID: category.id,
                            recurrence: .monthly(day: 15), recordingMode: .automatic,
                            hasReminder: false, createdAt: try XCTUnwrap(Day.date("2026-01-01")))
        try service.saveBill(rule, asOf: january)
        let recorded = try XCTUnwrap(repository.expenses(in: card.id).first)
        let originalLinks = try repository.billOccurrences(in: card.id).filter { $0.expenseID == recorded.id }
        try service.delete(recorded.id, in: card.id)
        XCTAssertEqual(try repository.billOccurrences(in: card.id).first { $0.id == originalLinks[0].id }?.status, .skipped)
        try service.reconcileBills(asOf: january)
        XCTAssertTrue(try repository.expenses(in: card.id).isEmpty)
        try service.restoreExpense(recorded, occurrences: originalLinks, in: card.id)
        let reopened = try reopen(repository, directory: directory)
        XCTAssertEqual(try reopened.expenses(in: card.id).map(\.id), [recorded.id])
        XCTAssertEqual(try reopened.billOccurrences(in: card.id).first { $0.id == originalLinks[0].id }?.expenseID, recorded.id)
        let backups = BackupService(directory: directory, repository: reopened,
            state: FileLocalStateStore(directory: directory), expenses: try ExpenseService(store: reopened))
        var settings = PrototypeSettings(); settings.card = card
        var draft = ExpenseDraft(); draft.cardID = card.id
        XCTAssertNoThrow(try backups.workspaceSnapshot(currentDraft: draft, settings: settings).validate())
    }

    func testSamplePromotionDetachesRecordedBillsAndPreservesHistory() throws {
        let (directory, repository) = try fixture()
        try repository.prepareSampleCard()
        let owner = Card.demo.id
        let category = try XCTUnwrap(repository.categories(in: owner).first)
        let rule = Bill(cardID: owner, name: "Sample rent", amount: 10_000, categoryID: category.id,
                            recurrence: .monthly(day: 15), recordingMode: .automatic, hasReminder: false)
        let value = expense(card: owner, category: category.id)
        let occurrence = BillOccurrence(billRuleID: rule.id, cardID: owner, dueDay: value.day,
                                        status: .recorded, expenseID: value.id)
        try repository.transaction {
            try repository.saveBill(rule, in: owner)
            try repository.save(value, in: owner)
            try repository.saveOccurrence(occurrence, in: owner)
        }
        let real = try Card.real(named: "Real")
        try repository.startEmptyRealCard(real)
        let reopened = try reopen(repository, directory: directory)
        XCTAssertTrue(try reopened.expenses(in: real.id).isEmpty)
        let preserved = try XCTUnwrap(reopened.billOccurrences(in: real.id).first)
        XCTAssertEqual(preserved.status, .skipped)
        XCTAssertNil(preserved.expenseID)
        XCTAssertEqual(try reopened.bills(in: real.id).first?.cardID, real.id)
    }

    func testCategoryMigrationScopesReusedLegacyIDsToTheirOwnCard() throws {
        let (directory, repository) = try fixture()
        let legacyID = UUID()
        let food = GlobalCategory(id: UUID(), name: "Food", symbol: "fork.knife")
        let travel = GlobalCategory(id: UUID(), name: "Travel", symbol: "airplane")
        var cards: [Card] = []
        for category in [food, travel] {
            let card = try repository.createCard(named: category.name, initialCategories: [])
            cards.append(card)
            try repository.saveCategory(.init(id: legacyID, name: category.name, symbol: category.symbol), in: card.id)
            try repository.save(expense(card: card.id, category: legacyID), in: card.id)
            try repository.save(BudgetVersion(effectiveDay: "2026-01-01", overallLimit: 100_000, startDay: 1,
                categoryLimits: [.init(categoryID: legacyID, limit: 50_000)], cardID: card.id), in: card.id)
            try repository.saveBill(Bill(cardID: card.id, name: "Bill", amount: 1_000, categoryID: legacyID,
                                            recurrence: .monthly(day: 15), hasReminder: false), in: card.id)
        }
        let mapping = try repository.categoryMigrationMapping(to: [food, travel])
        XCTAssertEqual(mapping[cards[0].id]?[legacyID], food.id)
        XCTAssertEqual(mapping[cards[1].id]?[legacyID], travel.id)
        try repository.unifyCategoriesToGlobalCatalog([food, travel])
        let reopened = try reopen(repository, directory: directory)
        for (card, canonical) in zip(cards, [food, travel]) {
            XCTAssertEqual(try reopened.expenses(in: card.id).first?.splits.first?.categoryID, canonical.id)
            XCTAssertEqual(try reopened.budgets(in: card.id).first?.categoryLimits.first?.categoryID, canonical.id)
            XCTAssertEqual(try reopened.bills(in: card.id).first?.categoryID, canonical.id)
        }
    }

    func testScheduleEditsAreProspectiveAndRetireObsoleteLookaheadAcrossFrequencies() throws {
        let (directory, repository) = try fixture()
        for recurrence in [BillRecurrence.monthly(day: 20), .weekly(weekday: 2), .yearly(month: 1, day: 20)] {
            let card = try repository.createCard(named: "Schedule")
            let category = try XCTUnwrap(repository.categories(in: card.id).first)
            let service = try ExpenseService(store: repository)
            var rule = Bill(cardID: card.id, name: "Rent", amount: 10_000, categoryID: category.id,
                recurrence: .monthly(day: 15), recordingMode: .automatic, hasReminder: false,
                createdAt: try XCTUnwrap(Day.date("2026-01-01")))
            try service.saveBill(rule, asOf: try XCTUnwrap(Day.date("2026-04-10")))
            let priorExpenses = Set(try repository.expenses(in: card.id).map(\.id))
            XCTAssertEqual(priorExpenses.count, 3)
            let oldPending = try repository.billOccurrences(in: card.id).filter { $0.status == .pending }
            rule.recurrence = recurrence
            try service.saveBill(rule, asOf: try XCTUnwrap(Day.date("2026-04-10")))
            let after = try repository.billOccurrences(in: card.id)
            XCTAssertTrue(Set(oldPending.map(\.id)).isDisjoint(with: Set(after.map(\.id))))
            XCTAssertEqual(Set(try repository.expenses(in: card.id).map(\.id)), priorExpenses)
            XCTAssertEqual(try repository.bills(in: card.id).first?.scheduleEffectiveDay, "2026-04-10")
            XCTAssertEqual(try repository.bills(in: card.id).first?.scheduleRevision, 1)
            try service.reconcileBills(asOf: try XCTUnwrap(Day.date("2026-05-30")), in: card.id)
            let newExpenses = try repository.expenses(in: card.id).filter { !priorExpenses.contains($0.id) }
            XCTAssertTrue(newExpenses.allSatisfy { $0.day >= "2026-04-10" })
            XCTAssertFalse(newExpenses.contains { $0.day == "2026-04-15" || $0.day == "2026-05-15" })
        }
        let reopened = try reopen(repository, directory: directory)
        for card in try reopened.cards() { XCTAssertEqual(try reopened.bills(in: card.id).first?.scheduleRevision, 1) }
    }

    func testWorkspaceReconciliationRecordsInactiveCardAndRemainsIdempotentAfterReopen() throws {
        let (directory, repository) = try fixture()
        let cards = try [repository.createCard(named: "A"), repository.createCard(named: "B")]
        for card in cards {
            let category = try XCTUnwrap(repository.categories(in: card.id).first)
            try repository.saveBill(Bill(cardID: card.id, name: "Rent", amount: 10_000, categoryID: category.id,
                recurrence: .monthly(day: 15), recordingMode: .automatic, hasReminder: false,
                createdAt: try XCTUnwrap(Day.date("2026-01-01"))), in: card.id)
        }
        let service = try ExpenseService(store: repository)
        try service.selectCard(cards[0].id)
        let due = try XCTUnwrap(Day.date("2026-01-15"))
        try service.reconcileBills(asOf: due)
        try service.reconcileBills(asOf: due)
        XCTAssertEqual(service.activeCardID, cards[0].id)
        let reopened = try reopen(repository, directory: directory)
        let nextService = try ExpenseService(store: reopened)
        try nextService.reconcileBills(asOf: due)
        for card in cards { XCTAssertEqual(try reopened.expenses(in: card.id).count, 1) }
    }

    func testDamagedPersistedRuleFailsClosedWithoutAddingExpenses() throws {
        let (directory, repository) = try fixture()
        let card = try repository.createCard(named: "Evidence")
        let category = try XCTUnwrap(repository.categories(in: card.id).first)
        try repository.saveBill(Bill(cardID: card.id, name: "Rent", amount: 10_000, categoryID: category.id,
                                         recurrence: .monthly(day: 15), hasReminder: false), in: card.id)
        let rows = try repository.container.viewContext.fetch(NSFetchRequest<NSManagedObject>(entityName: "BillRuleRecord"))
        try XCTUnwrap(rows.first).setValue("unknown", forKey: "recurrenceType")
        try repository.container.viewContext.save()
        let reopened = try reopen(repository, directory: directory)
        XCTAssertThrowsError(try reopened.bills(in: card.id))
        XCTAssertThrowsError(try ExpenseService(store: reopened))
        XCTAssertTrue(try reopened.expenses(in: card.id).isEmpty)
        let raw = try reopened.container.viewContext.fetch(NSFetchRequest<NSManagedObject>(entityName: "BillRuleRecord"))
        XCTAssertEqual(raw.first?.value(forKey: "recurrenceType") as? String, "unknown")
    }

    func testDamagedOccurrenceCannotDisappearAndDuplicateItsRecordedCharge() throws {
        let (directory, repository) = try fixture()
        let card = try repository.createCard(named: "Evidence")
        let category = try XCTUnwrap(repository.categories(in: card.id).first)
        let rule = Bill(cardID: card.id, name: "Rent", amount: 10_000, categoryID: category.id,
                            recurrence: .monthly(day: 15), recordingMode: .automatic, hasReminder: false,
                            createdAt: try XCTUnwrap(Day.date("2026-01-01")))
        let value = expense(card: card.id, category: category.id)
        let occurrence = BillOccurrence(billRuleID: rule.id, cardID: card.id, dueDay: value.day,
                                        status: .recorded, expenseID: value.id)
        try repository.transaction {
            try repository.saveBill(rule, in: card.id)
            try repository.save(value, in: card.id)
            try repository.saveOccurrence(occurrence, in: card.id)
        }
        let rows = try repository.container.viewContext.fetch(NSFetchRequest<NSManagedObject>(entityName: "BillOccurrenceRecord"))
        try XCTUnwrap(rows.first).setValue("unknown", forKey: "status")
        try repository.container.viewContext.save()
        let reopened = try reopen(repository, directory: directory)
        XCTAssertThrowsError(try reopened.billOccurrences(in: card.id))
        XCTAssertThrowsError(try ExpenseService(store: reopened))
        XCTAssertEqual(try reopened.expenses(in: card.id).map(\.id), [value.id])
    }

    func testDuplicateOrInconsistentOccurrenceWritePreservesOriginalRows() throws {
        let (_, repository) = try fixture()
        let card = try repository.createCard(named: "Graph")
        let category = try XCTUnwrap(repository.categories(in: card.id).first)
        let rule = Bill(cardID: card.id, name: "Rent", amount: 10_000, categoryID: category.id,
                            recurrence: .monthly(day: 15), hasReminder: false)
        try repository.saveBill(rule, in: card.id)
        let pending = BillOccurrence(billRuleID: rule.id, cardID: card.id, dueDay: "2026-01-15")
        try repository.saveOccurrence(pending, in: card.id)
        XCTAssertThrowsError(try repository.saveOccurrence(.init(billRuleID: rule.id, cardID: card.id, dueDay: pending.dueDay), in: card.id))
        var invalid = pending
        invalid.status = .recorded
        XCTAssertThrowsError(try repository.saveOccurrence(invalid, in: card.id))
        XCTAssertEqual(try repository.billOccurrences(in: card.id), [pending])
    }

    func testOuterWorkspaceTransactionPublishesOnceAndRollsBackAllCommands() throws {
        let (_, repository) = try fixture()
        let card = try repository.createCard(named: "Atomic")
        let category = try XCTUnwrap(repository.categories(in: card.id).first)
        let service = try ExpenseService(store: repository)
        var publications = 0
        service.onCommit = { publications += 1 }
        let first = expense(card: card.id, category: category.id)
        let second = expense(card: card.id, category: category.id)
        try service.performTransaction {
            try service.save(first)
            try service.save(second)
            XCTAssertEqual(publications, 0)
        }
        XCTAssertEqual(publications, 1)
        let revision = service.committedRevision
        enum Expected: Error { case rollback }
        XCTAssertThrowsError(try service.performTransaction {
            try service.delete(first.id)
            try service.renameCard(id: card.id, to: "Changed")
            throw Expected.rollback
        })
        XCTAssertEqual(publications, 1)
        XCTAssertEqual(service.committedRevision, revision)
        XCTAssertEqual(try repository.expenses(in: card.id).count, 2)
        XCTAssertEqual(try repository.cards().first?.name, "Atomic")
    }

    func testWorkspaceAggregateAdmissionRejectsOverflowWithoutPartialDiskWrites() throws {
        let (directory, repository) = try fixture()
        let card = try repository.createCard(named: "Boundary")
        let category = try XCTUnwrap(repository.categories(in: card.id).first)
        try repository.transaction {
            for _ in 0..<1_024 { try repository.save(expense(card: card.id, category: category.id, amount: Money.maximum), in: card.id) }
        }
        XCTAssertThrowsError(try repository.save(expense(card: card.id, category: category.id, amount: Money.maximum), in: card.id))
        let reopened = try reopen(repository, directory: directory)
        XCTAssertEqual(try reopened.expenses(in: card.id).count, 1_024)
        XCTAssertNoThrow(try ExpenseService(store: reopened))
    }

    func testCaughtInnerTransactionFailureStillPreventsOuterCommit() throws {
        let (directory, repository) = try fixture()
        let card = try repository.createCard(named: "Atomic")
        let category = try XCTUnwrap(repository.categories(in: card.id).first)
        enum Expected: Error { case failure }
        XCTAssertThrowsError(try repository.transaction {
            try repository.save(expense(card: card.id, category: category.id), in: card.id)
            do { try repository.transaction { throw Expected.failure } }
            catch { /* A caught inner failure poisons the whole outer transaction. */ }
            try repository.renameCard(id: card.id, to: "Must roll back")
        })
        let reopened = try reopen(repository, directory: directory)
        XCTAssertTrue(try reopened.expenses(in: card.id).isEmpty)
        XCTAssertEqual(try reopened.cards().first?.name, "Atomic")
    }

    func testRangePagesAreScopedStableAndUseInclusiveStartExclusiveEnd() throws {
        let (_, repository) = try fixture()
        let cards = try [repository.createCard(named: "A"), repository.createCard(named: "B")]
        for card in cards {
            let category = try XCTUnwrap(repository.categories(in: card.id).first)
            let batch = ["2026-01-14", "2026-01-15", "2026-01-15", "2026-01-16", "2026-01-17"].map {
                expense(card: card.id, category: category.id, day: $0)
            }
            try repository.saveExpenses(batch, in: card.id)
        }
        let first = try repository.expenses(in: cards[0].id, from: "2026-01-15", to: "2026-01-17", limit: 2)
        let second = try repository.expenses(in: cards[0].id, from: "2026-01-15", to: "2026-01-17", limit: 2, offset: 2)
        XCTAssertEqual(first.count, 2)
        XCTAssertEqual(second.count, 1)
        XCTAssertEqual(Set((first + second).map(\.id)).count, 3)
        XCTAssertTrue((first + second).allSatisfy { $0.cardID == cards[0].id && $0.day >= "2026-01-15" && $0.day < "2026-01-17" })
        XCTAssertEqual(try repository.expenses(in: cards[0].id, from: "2026-01-15", to: "2026-01-17", limit: 2), first)
        XCTAssertThrowsError(try repository.expenses(in: cards[0].id, from: "2026-01-17", to: "2026-01-15"))
        XCTAssertThrowsError(try repository.expenses(in: cards[0].id, from: "2026-01-15", to: "2026-01-17", limit: 0))
    }

    func testBatchCrossCardIdentityConflictRollsBackEveryRow() throws {
        let (directory, repository) = try fixture()
        let cards = try [repository.createCard(named: "A"), repository.createCard(named: "B")]
        let category = try XCTUnwrap(repository.categories(in: cards[0].id).first)
        let existing = expense(card: cards[0].id, category: category.id)
        try repository.save(existing, in: cards[0].id)
        let fresh = expense(card: cards[1].id, category: category.id)
        var conflicting = existing; conflicting.cardID = cards[1].id
        XCTAssertThrowsError(try repository.saveExpenses([fresh, conflicting], in: cards[1].id))
        let reopened = try reopen(repository, directory: directory)
        XCTAssertTrue(try reopened.expenses(in: cards[1].id).isEmpty)
        XCTAssertEqual(try reopened.expenses(in: cards[0].id).map(\.id), [existing.id])
    }

    func testTenThousandRowBatchAndBoundedPageBenchmark() throws { try benchmark(rows: 10_000) }

    func testFiftyThousandRowOptionalBenchmark() throws {
        guard ProcessInfo.processInfo.environment["ANKA_RUN_LARGE_BENCHMARK"] == "1" else {
            throw XCTSkip("Run explicitly with ANKA_RUN_LARGE_BENCHMARK=1 for the large synthetic fixture.")
        }
        try benchmark(rows: 50_000)
    }

    private func cpuSeconds() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec)
            + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
    }

    private func benchmark(rows: Int) throws {
        var timings: [(wall: Double, cpu: Double)] = []
        // The quadratic per-row comparison is measured at 10k. The scheduled
        // 50k fixture exercises the supported batch path within the CI budget.
        for batched in rows <= 10_000 ? [false, true] : [true] {
            let (_, repository) = try fixture()
            let card = try repository.createCard(named: "Benchmark")
            let category = try XCTUnwrap(repository.categories(in: card.id).first)
            let values = (0..<rows).map { _ in expense(card: card.id, category: category.id, amount: 100) }
            let wallStart = ProcessInfo.processInfo.systemUptime, cpuStart = cpuSeconds()
            if batched { try repository.saveExpenses(values, in: card.id) }
            else { try repository.transaction { for value in values { try repository.save(value, in: card.id) } } }
            timings.append((ProcessInfo.processInfo.systemUptime - wallStart, cpuSeconds() - cpuStart))
            let pageStart = ProcessInfo.processInfo.systemUptime
            let page = try repository.expenses(in: card.id, from: "2026-01-01", to: "2026-02-01", limit: 100)
            let pageSeconds = ProcessInfo.processInfo.systemUptime - pageStart
            XCTAssertEqual(page.count, 100)
            XCTAssertEqual(try repository.expenses(in: card.id).count, rows)
            print("BackendBenchmark rows=\(rows) path=\(batched ? "batch" : "per-row") wallSeconds=\(timings.last!.wall) cpuSeconds=\(timings.last!.cpu) pageSeconds=\(pageSeconds)")
        }
        // Timing is evidence, not a correctness assertion: simulator scheduling and SQL cache state vary.
    }

    func testV3DiskMigrationRetainsBillsAndDefaultsScheduleRevision() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("migration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let modelDirectory = try XCTUnwrap(Bundle.main.url(forResource: "Anka", withExtension: "momd"))
        let model = try XCTUnwrap(NSManagedObjectModel(contentsOf: modelDirectory.appendingPathComponent("AnkaV3.mom")))
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        let store = try coordinator.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil,
                                                       at: directory.appendingPathComponent("ledger.sqlite"))
        let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
        let cardID = UUID(), categoryID = UUID(), billID = UUID()
        let card = NSEntityDescription.insertNewObject(forEntityName: "Book", into: context)
        card.setValue(cardID, forKey: "id"); card.setValue("Legacy", forKey: "name")
        let category = NSEntityDescription.insertNewObject(forEntityName: "CategoryRecord", into: context)
        category.setValue(categoryID, forKey: "id"); category.setValue("Bills", forKey: "name")
        category.setValue("bolt", forKey: "symbol"); category.setValue(card, forKey: "book")
        let bill = NSEntityDescription.insertNewObject(forEntityName: "BillRuleRecord", into: context)
        bill.setValue(billID, forKey: "id"); bill.setValue("Rent", forKey: "name")
        bill.setValue(10_000, forKey: "amount"); bill.setValue(categoryID, forKey: "categoryID")
        bill.setValue("monthly", forKey: "recurrenceType"); bill.setValue(15, forKey: "recurrenceDay")
        bill.setValue(Date.now, forKey: "createdAt"); bill.setValue(card, forKey: "book")
        try context.save()
        context.reset()
        try coordinator.remove(store)
        let migrated = try ExpenseRepository(url: directory.appendingPathComponent("ledger.sqlite"))
        let value = try XCTUnwrap(migrated.bills(in: cardID).first)
        XCTAssertEqual(value.id, billID)
        XCTAssertEqual(value.scheduleRevision, 0)
        XCTAssertNil(value.scheduleEffectiveDay)
        XCTAssertEqual(try migrated.cards().first?.colorIndex, 0)
    }

    func testV4DiskMigrationKeepsDataAndLeavesModelBFieldsEmpty() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("migration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let modelDirectory = try XCTUnwrap(Bundle.main.url(forResource: "Anka", withExtension: "momd"))
        let model = try XCTUnwrap(NSManagedObjectModel(contentsOf: modelDirectory.appendingPathComponent("AnkaV4.mom")))
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        let store = try coordinator.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil,
                                                       at: directory.appendingPathComponent("ledger.sqlite"))
        let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
        let cardID = UUID(), categoryID = UUID(), expenseID = UUID()
        let card = NSEntityDescription.insertNewObject(forEntityName: "Book", into: context)
        card.setValue(cardID, forKey: "id"); card.setValue("Daily", forKey: "name"); card.setValue(2, forKey: "colorIndex")
        let category = NSEntityDescription.insertNewObject(forEntityName: "CategoryRecord", into: context)
        category.setValue(categoryID, forKey: "id"); category.setValue("Food", forKey: "name")
        category.setValue("fork.knife", forKey: "symbol"); category.setValue(card, forKey: "book")
        let expense = NSEntityDescription.insertNewObject(forEntityName: "ExpenseRecord", into: context)
        expense.setValue(expenseID, forKey: "id"); expense.setValue(Int64(2_800_000), forKey: "amount")
        expense.setValue("2026-10-09", forKey: "day"); expense.setValue("Kopi", forKey: "note")
        expense.setValue("manual", forKey: "source"); expense.setValue(Date.now, forKey: "createdAt"); expense.setValue(card, forKey: "book")
        let split = NSEntityDescription.insertNewObject(forEntityName: "AllocationRecord", into: context)
        split.setValue(Int64(2_800_000), forKey: "amount"); split.setValue(category, forKey: "category"); split.setValue(expense, forKey: "expense")
        let budget = NSEntityDescription.insertNewObject(forEntityName: "BudgetRecord", into: context)
        budget.setValue(UUID(), forKey: "id"); budget.setValue("2026-10-01", forKey: "effectiveDay")
        budget.setValue(Int64(500_000_000), forKey: "overallLimit"); budget.setValue(1, forKey: "startDay"); budget.setValue(card, forKey: "book")
        try context.save()
        context.reset()
        try coordinator.remove(store)

        let migrated = try ExpenseRepository(url: directory.appendingPathComponent("ledger.sqlite"))
        let migratedCard = try XCTUnwrap(migrated.cards().first)
        XCTAssertEqual(migratedCard.colorIndex, 2)
        XCTAssertNil(migratedCard.currency); XCTAssertNil(migratedCard.spendingCurrency); XCTAssertNil(migratedCard.defaultPaidWithID)
        let value = try XCTUnwrap(migrated.expenses(in: cardID).first)
        XCTAssertEqual(value.id, expenseID)
        XCTAssertEqual(value.amount, 2_800_000)
        XCTAssertNil(value.paidWithID); XCTAssertNil(value.originalCurrency); XCTAssertNil(value.rateSource)
        XCTAssertNil(try migrated.budgets(in: cardID).first?.totalUntilDay)

        var updated = value
        updated.paidWithID = UUID()
        try migrated.save(updated, in: cardID)
        XCTAssertEqual(try migrated.expenses(in: cardID).first?.paidWithID, updated.paidWithID)
    }
}
