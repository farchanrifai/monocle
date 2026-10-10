import CoreData
import Foundation

@MainActor
final class ExpenseRepository: ExpenseStore {
    let container: NSPersistentContainer
    private var context: NSManagedObjectContext { container.viewContext }

    private var transactionDepth = 0
    private var transactionFailure: (any Error)?
    private var bookCache: [UUID: NSManagedObject] = [:]
    private var categoryCache: [UUID: [UUID: NSManagedObject]] = [:]
    private var expenseCache: [UUID: NSManagedObject] = [:]
    private var prefetchedExpenseIDs = Set<UUID>()
    private var changedBillBooks = Set<UUID>()

    func transaction(_ operation: () throws -> Void) throws {
        let outer = transactionDepth == 0
        if outer { resetTransactionState() }
        transactionDepth += 1
        defer {
            transactionDepth -= 1
            if outer { resetTransactionState() }
        }
        do {
            try operation()
            if let failure = transactionFailure { throw failure }
            if outer {
                try BackendDiagnostics.measure("RepositoryCommit") {
                    try validateChangedBillGraphs()
                    try validateAggregate()
                    try context.save()
                }
            }
        } catch {
            transactionFailure = transactionFailure ?? error
            context.rollback()
            throw error
        }
    }

    private func resetTransactionState() {
        transactionFailure = nil
        bookCache.removeAll()
        categoryCache.removeAll()
        expenseCache.removeAll()
        prefetchedExpenseIDs.removeAll()
        changedBillBooks.removeAll()
    }

    private func commitIfNeeded() throws {
        if transactionDepth == 0 && context.hasChanges {
            defer { resetTransactionState() }
            try validateChangedBillGraphs()
            try validateAggregate()
            try context.save()
        }
    }

    private func validateChangedBillGraphs() throws {
        for bookID in changedBillBooks { _ = try billOccurrences(in: bookID) }
    }

    private func writeModelBFields(of profile: BookProfile, to row: NSManagedObject) {
        row.setValue(profile.currency, forKey: "currency")
        row.setValue(profile.spendingCurrency, forKey: "spendingCurrency")
        row.setValue(profile.defaultPaidWithID, forKey: "defaultPaidWithID")
    }

    private func writeModelBFields(of expense: Expense, to row: NSManagedObject) {
        row.setValue(expense.paidWithID, forKey: "paidWithID")
        row.setValue(expense.originalAmount.map { NSNumber(value: $0) }, forKey: "originalAmount")
        row.setValue(expense.originalCurrency, forKey: "originalCurrency")
        row.setValue(expense.rate, forKey: "rate")
        row.setValue(expense.rateSource?.rawValue, forKey: "rateSource")
    }

    init(url: URL? = nil, inMemory: Bool = false) throws {
        guard let modelURL = Bundle.main.url(forResource: "Monocle", withExtension: "momd"),
              let model = NSManagedObjectModel(contentsOf: modelURL) else { throw EntryError.corruptStore }
        container = NSPersistentContainer(name: "Monocle", managedObjectModel: model)
        let storeURL = inMemory ? nil : url
        try container.persistentStoreCoordinator.addPersistentStore(ofType: inMemory ? NSInMemoryStoreType : NSSQLiteStoreType, configurationName: nil, at: storeURL, options: [NSMigratePersistentStoresAutomaticallyOption: true, NSInferMappingModelAutomaticallyOption: true])
        context.undoManager = nil
        context.mergePolicy = NSMergePolicy(merge: .errorMergePolicyType)
    }

    func prepareSampleBook(categories: [ExpenseCategory] = ExpenseCategory.defaults) throws {
        guard try objects("Book").isEmpty else { return }
        do {
            let book = NSEntityDescription.insertNewObject(forEntityName: "Book", into: context)
            book.setValue(BookProfile.sample.id, forKey: "id")
            book.setValue(BookProfile.sample.name, forKey: "name")
            book.setValue(BookProfile.sample.colorIndex, forKey: "colorIndex")
            for category in categories {
                let row = NSEntityDescription.insertNewObject(forEntityName: "CategoryRecord", into: context)
                row.setValue(category.id, forKey: "id"); row.setValue(category.name, forKey: "name")
                row.setValue(category.symbol, forKey: "symbol"); row.setValue(book, forKey: "book")
            }
            try commitIfNeeded()
        } catch { context.rollback(); throw error }
    }

    func books() throws -> [BookProfile] {
        try objects("Book").map { row in
            guard let id = row.value(forKey: "id") as? UUID,
                  let name = row.value(forKey: "name") as? String else { throw EntryError.corruptStore }
            let kind: BookKind = (id == BookProfile.sample.id) ? .sample : .real
            let colorIndex = (row.value(forKey: "colorIndex") as? NSNumber)?.intValue ?? 0
            return BookProfile(id: id, name: name, kind: kind, colorIndex: colorIndex,
                               currency: row.value(forKey: "currency") as? String,
                               spendingCurrency: row.value(forKey: "spendingCurrency") as? String,
                               defaultPaidWithID: row.value(forKey: "defaultPaidWithID") as? UUID)
        }
    }

    func createBook(named name: String) throws -> BookProfile {
        try createBook(named: name, initialCategories: nil)
    }

    func createBook(named name: String, initialCategories: [GlobalCategory]?) throws -> BookProfile {
        let profile = try BookProfile.real(named: name)
        do {
            let book = NSEntityDescription.insertNewObject(forEntityName: "Book", into: context)
            book.setValue(profile.id, forKey: "id")
            book.setValue(profile.name, forKey: "name")
            book.setValue(profile.colorIndex, forKey: "colorIndex")
            let catsToSeed = initialCategories ?? GlobalCategory.defaults
            for cat in catsToSeed {
                let row = NSEntityDescription.insertNewObject(forEntityName: "CategoryRecord", into: context)
                row.setValue(cat.id, forKey: "id")
                row.setValue(cat.name, forKey: "name")
                row.setValue(cat.symbol, forKey: "symbol")
                row.setValue(book, forKey: "book")
            }
            try commitIfNeeded()
            return profile
        } catch { context.rollback(); throw error }
    }

    func renameBook(id: UUID, to name: String) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 40 else { throw BackupError.invalid }
        do {
            let book = try bookRow(for: id)
            book.setValue(trimmed, forKey: "name")
            try commitIfNeeded()
        } catch { context.rollback(); throw error }
    }

    func deleteBook(id: UUID) throws {
        let allBooks = try self.books()
        guard allBooks.count > 1 else { throw BackupError.invalid }
        do {
            let book = try bookRow(for: id)
            context.delete(book)
            try commitIfNeeded()
        } catch { context.rollback(); throw error }
    }

    func categories(in bookID: UUID) throws -> [ExpenseCategory] {
        let book = try bookRow(for: bookID)
        let set = (book.value(forKey: "categories") as? Set<NSManagedObject>) ?? []
        return try set.map { row in
            guard let id = row.value(forKey: "id") as? UUID, let name = row.value(forKey: "name") as? String,
                  let symbol = row.value(forKey: "symbol") as? String else { throw EntryError.corruptStore }
            return ExpenseCategory(id: id, name: name, symbol: symbol)
        }.sorted { $0.id.uuidString < $1.id.uuidString }
    }

    func categories() throws -> [ExpenseCategory] {
        try categories(in: defaultBookID())
    }

    func expenses(in bookID: UUID) throws -> [Expense] {
        try fetchExpenses(in: bookID, startDay: nil, endDay: nil, limit: nil, offset: 0)
    }

    /// A stable page with inclusive start and exclusive end civil days. Callers keep their chosen bounds.
    func expenses(in bookID: UUID, from startDay: String, to endDay: String,
                  limit: Int = 200, offset: Int = 0) throws -> [Expense] {
        guard Day.date(startDay) != nil, Day.date(endDay) != nil, startDay < endDay,
              (1...1_000).contains(limit), offset >= 0 else { throw EntryError.invalidDate }
        return try fetchExpenses(in: bookID, startDay: startDay, endDay: endDay, limit: limit, offset: offset)
    }

    private func fetchExpenses(in bookID: UUID, startDay: String?, endDay: String?, limit: Int?, offset: Int) throws -> [Expense] {
        try BackendDiagnostics.measure("ExpenseFetch") {
            let book = try bookRow(for: bookID)
            let categories = try categories(in: bookID)
            let request = NSFetchRequest<NSManagedObject>(entityName: "ExpenseRecord")
            if let startDay, let endDay {
                request.predicate = NSPredicate(format: "book == %@ AND day >= %@ AND day < %@", book, startDay, endDay)
            } else { request.predicate = NSPredicate(format: "book == %@", book) }
            request.sortDescriptors = [NSSortDescriptor(key: "day", ascending: false),
                                       NSSortDescriptor(key: "createdAt", ascending: false),
                                       NSSortDescriptor(key: "id", ascending: true)]
            request.relationshipKeyPathsForPrefetching = ["allocations", "allocations.category"]
            request.fetchBatchSize = min(limit ?? 200, 200)
            request.fetchOffset = offset
            if let limit { request.fetchLimit = limit }
            let values = try context.fetch(request).map { try expenseValue($0, in: bookID, categories: categories) }
            guard Set(values.map(\.id)).count == values.count else { throw EntryError.corruptStore }
            return values
        }
    }

    private func expenseValue(_ row: NSManagedObject, in bookID: UUID, categories: [ExpenseCategory]) throws -> Expense {
        guard let id = row.value(forKey: "id") as? UUID, let day = row.value(forKey: "day") as? String,
              let createdAt = row.value(forKey: "createdAt") as? Date,
              let amount = row.value(forKey: "amount") as? Int64,
              let allocations = row.value(forKey: "allocations") as? Set<NSManagedObject> else { throw EntryError.corruptStore }
        let values = try allocations.map { allocation -> Allocation in
            guard let category = allocation.value(forKey: "category") as? NSManagedObject,
                  let categoryID = category.value(forKey: "id") as? UUID,
                  let categoryBook = category.value(forKey: "book") as? NSManagedObject,
                  categoryBook.value(forKey: "id") as? UUID == bookID,
                  let value = allocation.value(forKey: "amount") as? Int64 else { throw EntryError.corruptStore }
            return Allocation(categoryID: categoryID, amount: value)
        }.sorted { $0.categoryID.uuidString < $1.categoryID.uuidString }
        let expense = Expense(id: id, amount: amount, day: day, note: row.value(forKey: "note") as? String ?? "",
            allocations: values, source: row.value(forKey: "source") as? String ?? "manual", createdAt: createdAt, bookID: bookID,
            paidWithID: row.value(forKey: "paidWithID") as? UUID,
            originalAmount: (row.value(forKey: "originalAmount") as? NSNumber)?.int64Value,
            originalCurrency: row.value(forKey: "originalCurrency") as? String,
            rate: row.value(forKey: "rate") as? String,
            rateSource: (row.value(forKey: "rateSource") as? String).flatMap(Expense.RateSource.init(rawValue:)))
        try expense.validate(categories: categories)
        return expense
    }

    func expenses() throws -> [Expense] {
        try expenses(in: defaultBookID())
    }

    func budgets(in bookID: UUID) throws -> [BudgetVersion] {
        let book = try bookRow(for: bookID)
        let cats = try categories(in: bookID)
        let set = (book.value(forKey: "budgets") as? Set<NSManagedObject>) ?? []
        let values = try set.map { row -> BudgetVersion in
            guard let id = row.value(forKey: "id") as? UUID,
                  let effectiveDay = row.value(forKey: "effectiveDay") as? String,
                  let overallLimit = row.value(forKey: "overallLimit") as? Int64,
                  let startDay = (row.value(forKey: "startDay") as? NSNumber)?.intValue else { throw EntryError.corruptStore }
            let limits = try (row.value(forKey: "categoryLimits") as? Set<NSManagedObject> ?? []).map { value -> CategoryBudget in
                guard let categoryID = value.value(forKey: "categoryID") as? UUID,
                      let limit = value.value(forKey: "limit") as? Int64 else { throw EntryError.corruptStore }
                return CategoryBudget(categoryID: categoryID, limit: limit)
            }.sorted { $0.categoryID.uuidString < $1.categoryID.uuidString }
            let budget = BudgetVersion(id: id, effectiveDay: effectiveDay, overallLimit: overallLimit,
                                       startDay: startDay, categoryLimits: limits,
                                       transitionEndDay: row.value(forKey: "transitionEndDay") as? String,
                                       bookID: bookID,
                                       totalUntilDay: row.value(forKey: "totalUntilDay") as? String)
            try budget.validate(categories: cats)
            return budget
        }.sorted { $0.effectiveDay < $1.effectiveDay }
        guard Set(values.map(\.effectiveDay)).count == values.count else { throw EntryError.corruptStore }
        return values
    }

    func budgets() throws -> [BudgetVersion] {
        try budgets(in: defaultBookID())
    }

    func bills(in bookID: UUID) throws -> [BillRule] {
        let book = try bookRow(for: bookID)
        let categories = try categories(in: bookID)
        let set = (book.value(forKey: "bills") as? Set<NSManagedObject>) ?? []
        let values = try set.map { row -> BillRule in
            guard let id = row.value(forKey: "id") as? UUID,
                  let name = row.value(forKey: "name") as? String,
                  let amount = row.value(forKey: "amount") as? Int64,
                  let categoryID = row.value(forKey: "categoryID") as? UUID,
                  let createdAt = row.value(forKey: "createdAt") as? Date,
                  let recurrenceType = row.value(forKey: "recurrenceType") as? String,
                  let recurrenceDay = (row.value(forKey: "recurrenceDay") as? NSNumber)?.intValue,
                  let recurrenceMonth = (row.value(forKey: "recurrenceMonth") as? NSNumber)?.intValue,
                  let isAutomatic = (row.value(forKey: "isAutomatic") as? NSNumber)?.boolValue,
                  let hasReminder = (row.value(forKey: "hasReminder") as? NSNumber)?.boolValue,
                  let reminderLeadDays = (row.value(forKey: "reminderLeadDays") as? NSNumber)?.intValue,
                  let isActive = (row.value(forKey: "isActive") as? NSNumber)?.boolValue,
                  let scheduleRevision = (row.value(forKey: "scheduleRevision") as? NSNumber)?.intValue else {
                throw EntryError.corruptStore
            }
            let recurrence: BillRecurrence
            switch recurrenceType {
            case "monthly": recurrence = .monthly(day: recurrenceDay)
            case "weekly": recurrence = .weekly(weekday: recurrenceDay)
            case "yearly": recurrence = .yearly(month: recurrenceMonth, day: recurrenceDay)
            default: throw EntryError.corruptStore
            }
            let value = BillRule(id: id, bookID: bookID, name: name, amount: amount,
                categoryID: categoryID, recurrence: recurrence,
                recordingMode: isAutomatic ? .automatic : .pending,
                hasReminder: hasReminder, reminderLeadDays: reminderLeadDays,
                createdAt: createdAt, isActive: isActive,
                scheduleEffectiveDay: row.value(forKey: "scheduleEffectiveDay") as? String,
                scheduleRevision: scheduleRevision)
            do { try value.validate(categories: categories) }
            catch { throw EntryError.corruptStore }
            return value
        }.sorted { $0.createdAt < $1.createdAt }
        guard Set(values.map(\.id)).count == values.count else { throw EntryError.corruptStore }
        return values
    }

    func bills() throws -> [BillRule] {
        try bills(in: defaultBookID())
    }

    func billOccurrences(in bookID: UUID) throws -> [BillOccurrence] {
        let book = try bookRow(for: bookID)
        let rules = try bills(in: bookID)
        let expenses = try expenses(in: bookID)
        let request = NSFetchRequest<NSManagedObject>(entityName: "BillOccurrenceRecord")
        request.predicate = NSPredicate(format: "rule.book == %@ OR rule == nil", book)
        let occurrences = try context.fetch(request).map { row -> BillOccurrence in
            guard let rule = row.value(forKey: "rule") as? NSManagedObject,
                  let ruleID = rule.value(forKey: "id") as? UUID,
                  let id = row.value(forKey: "id") as? UUID,
                  let dueDay = row.value(forKey: "dueDay") as? String,
                  let statusStr = row.value(forKey: "status") as? String,
                  let status = BillOccurrenceStatus(rawValue: statusStr),
                  let createdAt = row.value(forKey: "createdAt") as? Date,
                  let updatedAt = row.value(forKey: "updatedAt") as? Date else { throw EntryError.corruptStore }
            return BillOccurrence(id: id, billRuleID: ruleID, bookID: bookID,
                dueDay: dueDay, status: status, expenseID: row.value(forKey: "expenseID") as? UUID,
                createdAt: createdAt, updatedAt: updatedAt)
        }
        try BillOccurrence.validate(occurrences, rules: rules, expenses: expenses, bookID: bookID)
        return occurrences.sorted { $0.dueDay < $1.dueDay }
    }

    func billOccurrences() throws -> [BillOccurrence] {
        try billOccurrences(in: defaultBookID())
    }

    func saveBill(_ bill: BillRule, in bookID: UUID) throws {
        let book = try bookRow(for: bookID)
        guard bill.bookID == bookID else { throw EntryError.corruptStore }
        try bill.validate(categories: categories(in: bookID))
        do {
            let existing = try findBillRule("BillRuleRecord", id: bill.id, in: book)
            if existing == nil, let globalExisting = try find("BillRuleRecord", id: bill.id),
               let existingBook = globalExisting.value(forKey: "book") as? NSManagedObject,
               let existingID = existingBook.value(forKey: "id") as? UUID, existingID != bookID {
                throw EntryError.corruptStore
            }
            let row = existing ?? NSEntityDescription.insertNewObject(forEntityName: "BillRuleRecord", into: context)
            row.setValue(bill.id, forKey: "id")
            row.setValue(bill.name, forKey: "name")
            row.setValue(bill.amount, forKey: "amount")
            row.setValue(bill.categoryID, forKey: "categoryID")
            switch bill.recurrence {
            case .monthly(let day):
                row.setValue("monthly", forKey: "recurrenceType")
                row.setValue(Int16(day), forKey: "recurrenceDay")
                row.setValue(Int16(1), forKey: "recurrenceMonth")
            case .weekly(let weekday):
                row.setValue("weekly", forKey: "recurrenceType")
                row.setValue(Int16(weekday), forKey: "recurrenceDay")
                row.setValue(Int16(1), forKey: "recurrenceMonth")
            case .yearly(let month, let day):
                row.setValue("yearly", forKey: "recurrenceType")
                row.setValue(Int16(day), forKey: "recurrenceDay")
                row.setValue(Int16(month), forKey: "recurrenceMonth")
            }
            row.setValue(bill.recordingMode == .automatic, forKey: "isAutomatic")
            row.setValue(bill.hasReminder, forKey: "hasReminder")
            row.setValue(Int16(bill.reminderLeadDays), forKey: "reminderLeadDays")
            row.setValue(bill.isActive, forKey: "isActive")
            row.setValue(bill.createdAt, forKey: "createdAt")
            row.setValue(bill.scheduleEffectiveDay, forKey: "scheduleEffectiveDay")
            row.setValue(bill.scheduleRevision, forKey: "scheduleRevision")
            row.setValue(book, forKey: "book")
            changedBillBooks.insert(bookID)
            try commitIfNeeded()
        } catch { context.rollback(); throw error }
    }

    func saveBill(_ bill: BillRule) throws {
        try saveBill(bill, in: bill.bookID)
    }

    func deleteBill(_ id: UUID, in bookID: UUID) throws {
        do {
            let book = try bookRow(for: bookID)
            if let row = try findBillRule("BillRuleRecord", id: id, in: book) {
                context.delete(row)
                try commitIfNeeded()
            }
        } catch { context.rollback(); throw error }
    }

    func deleteBill(_ id: UUID) throws {
        try deleteBill(id, in: defaultBookID())
    }

    func saveOccurrence(_ occurrence: BillOccurrence, in bookID: UUID) throws {
        let book = try bookRow(for: bookID)
        guard let ruleRow = try findBillRule("BillRuleRecord", id: occurrence.billRuleID, in: book) else {
            throw BillError.ruleNotFound
        }
        guard occurrence.bookID == bookID, Day.date(occurrence.dueDay) != nil,
              occurrence.createdAt.timeIntervalSince1970.isFinite,
              occurrence.updatedAt.timeIntervalSince1970.isFinite else { throw EntryError.corruptStore }
        switch occurrence.status {
        case .recorded:
            guard let expenseID = occurrence.expenseID, let expense = try expenseRow(id: expenseID),
                  (expense.value(forKey: "book") as? NSManagedObject) == book else { throw EntryError.corruptStore }
        case .pending, .skipped:
            guard occurrence.expenseID == nil else { throw EntryError.corruptStore }
        }
        let duplicate = NSFetchRequest<NSManagedObject>(entityName: "BillOccurrenceRecord")
        duplicate.predicate = NSPredicate(format: "rule == %@ AND dueDay == %@ AND id != %@", ruleRow, occurrence.dueDay, occurrence.id as NSUUID)
        duplicate.fetchLimit = 1
        guard try context.fetch(duplicate).isEmpty else { throw EntryError.corruptStore }
        if let globalExisting = try find("BillOccurrenceRecord", id: occurrence.id),
           (globalExisting.value(forKey: "rule") as? NSManagedObject) != ruleRow { throw EntryError.corruptStore }
        changedBillBooks.insert(bookID)
        do {
            let existing = try findOccurrence("BillOccurrenceRecord", id: occurrence.id, in: ruleRow)
            let row = existing ?? NSEntityDescription.insertNewObject(forEntityName: "BillOccurrenceRecord", into: context)
            row.setValue(occurrence.id, forKey: "id")
            row.setValue(occurrence.dueDay, forKey: "dueDay")
            row.setValue(occurrence.status.rawValue, forKey: "status")
            row.setValue(occurrence.expenseID, forKey: "expenseID")
            row.setValue(occurrence.createdAt, forKey: "createdAt")
            row.setValue(occurrence.updatedAt, forKey: "updatedAt")
            row.setValue(ruleRow, forKey: "rule")
            try commitIfNeeded()
        } catch { context.rollback(); throw error }
    }

    func saveOccurrence(_ occurrence: BillOccurrence) throws {
        try saveOccurrence(occurrence, in: occurrence.bookID)
    }

    func deleteOccurrence(_ id: UUID, in bookID: UUID) throws {
        do {
            let book = try bookRow(for: bookID)
            let request = NSFetchRequest<NSManagedObject>(entityName: "BillOccurrenceRecord")
            request.predicate = NSPredicate(format: "id == %@ AND rule.book == %@", id as NSUUID, book)
            request.fetchLimit = 1
            if let row = try context.fetch(request).first {
                context.delete(row)
                try commitIfNeeded()
            }
        } catch { context.rollback(); throw error }
    }

    func deleteOccurrence(_ id: UUID) throws {
        try deleteOccurrence(id, in: defaultBookID())
    }

    func prepareInitialBudget(settings: PrototypeSettings, in bookID: UUID? = nil) throws {
        let targetID = try bookID ?? defaultBookID()
        guard try budgets(in: targetID).isEmpty else { return }
        try save(BudgetVersion.initial(overallLimit: settings.budget, startDay: settings.startDay, bookID: targetID), in: targetID)
    }

    private func categoryRows(in book: NSManagedObject, bookID: UUID) throws -> [UUID: NSManagedObject] {
        if transactionDepth > 0, let cached = categoryCache[bookID] { return cached }
        let rows = (book.value(forKey: "categories") as? Set<NSManagedObject>) ?? []
        var result: [UUID: NSManagedObject] = [:]
        for row in rows where !row.isDeleted {
            guard let id = row.value(forKey: "id") as? UUID, result[id] == nil else { throw EntryError.corruptStore }
            result[id] = row
        }
        if transactionDepth > 0 { categoryCache[bookID] = result }
        return result
    }

    private func categoryValues(_ rows: [UUID: NSManagedObject]) throws -> [ExpenseCategory] {
        try rows.map { id, row in
            guard let name = row.value(forKey: "name") as? String,
                  let symbol = row.value(forKey: "symbol") as? String else { throw EntryError.corruptStore }
            return ExpenseCategory(id: id, name: name, symbol: symbol)
        }
    }

    private func expenseRow(id: UUID) throws -> NSManagedObject? {
        if prefetchedExpenseIDs.contains(id) {
            guard let row = expenseCache[id], !row.isDeleted else { return nil }
            return row
        }
        return try find("ExpenseRecord", id: id)
    }

    /// Category rows and candidate identities are loaded once, with bounded SQLite IN predicates.
    func saveExpenses(_ batch: [Expense], in bookID: UUID) throws {
        guard Set(batch.map(\.id)).count == batch.count else { throw EntryError.corruptStore }
        try BackendDiagnostics.measure("ExpenseBatch", count: batch.count) {
            try transaction {
                let book = try bookRow(for: bookID)
                _ = try categoryRows(in: book, bookID: bookID)
                let ids = batch.map(\.id)
                var fetchedIDs = Set<UUID>()
                for start in stride(from: 0, to: ids.count, by: 400) {
                    let chunk = Array(ids[start..<min(start + 400, ids.count)])
                    let request = NSFetchRequest<NSManagedObject>(entityName: "ExpenseRecord")
                    request.predicate = NSPredicate(format: "id IN %@", chunk.map { $0 as NSUUID })
                    for row in try context.fetch(request) {
                        guard let id = row.value(forKey: "id") as? UUID, fetchedIDs.insert(id).inserted else { throw EntryError.corruptStore }
                        expenseCache[id] = row
                    }
                    prefetchedExpenseIDs.formUnion(chunk)
                }
                for expense in batch { try save(expense, in: bookID) }
            }
        }
    }

    func save(_ expense: Expense, in bookID: UUID) throws {
        let book = try bookRow(for: bookID)
        let categoryRows = try categoryRows(in: book, bookID: bookID)
        guard expense.bookID == nil || expense.bookID == bookID else { throw EntryError.corruptStore }
        try expense.validate(categories: categoryValues(categoryRows))
        do {
            let existing = try expenseRow(id: expense.id)
            if let existing, let existingBook = existing.value(forKey: "book") as? NSManagedObject,
               let existingID = existingBook.value(forKey: "id") as? UUID, existingID != bookID {
                throw EntryError.corruptStore // Reject cross-book reparenting
            }
            let row = existing ?? NSEntityDescription.insertNewObject(forEntityName: "ExpenseRecord", into: context)
            if transactionDepth > 0 { expenseCache[expense.id] = row; prefetchedExpenseIDs.insert(expense.id) }
            row.setValue(expense.id, forKey: "id"); row.setValue(expense.amount, forKey: "amount")
            row.setValue(expense.day, forKey: "day"); row.setValue(expense.note, forKey: "note")
            row.setValue(expense.source, forKey: "source"); row.setValue(expense.createdAt, forKey: "createdAt")
            writeModelBFields(of: expense, to: row)
            row.setValue(book, forKey: "book")
            for allocation in row.value(forKey: "allocations") as? Set<NSManagedObject> ?? [] { context.delete(allocation) }
            for value in expense.allocations {
                guard let category = categoryRows[value.categoryID] else { throw EntryError.missingCategory }
                let allocation = NSEntityDescription.insertNewObject(forEntityName: "AllocationRecord", into: context)
                allocation.setValue(value.amount, forKey: "amount"); allocation.setValue(category, forKey: "category")
                allocation.setValue(row, forKey: "expense")
            }
            try commitIfNeeded()
        } catch { context.rollback(); throw error }
    }

    func save(_ expense: Expense) throws {
        try save(expense, in: expense.bookID ?? defaultBookID())
    }

    func save(_ budget: BudgetVersion, in bookID: UUID) throws {
        let book = try bookRow(for: bookID)
        try budget.validate(categories: categories(in: bookID))
        do {
            let existingBudgets = (book.value(forKey: "budgets") as? Set<NSManagedObject>) ?? []
            for row in existingBudgets where
                row.value(forKey: "effectiveDay") as? String == budget.effectiveDay &&
                row.value(forKey: "id") as? UUID != budget.id {
                context.delete(row)
            }
            let existingInBook = try findBudget("BudgetRecord", id: budget.id, in: book)
            if existingInBook == nil, let globalExisting = try find("BudgetRecord", id: budget.id),
               let existingBook = globalExisting.value(forKey: "book") as? NSManagedObject,
               let existingID = existingBook.value(forKey: "id") as? UUID, existingID != bookID,
               budget.id != BudgetVersion.legacyID {
                throw EntryError.corruptStore // Reject cross-book reparenting
            }
            let row = existingInBook ?? NSEntityDescription.insertNewObject(forEntityName: "BudgetRecord", into: context)
            row.setValue(budget.id, forKey: "id")
            row.setValue(budget.effectiveDay, forKey: "effectiveDay")
            row.setValue(budget.overallLimit, forKey: "overallLimit")
            row.setValue(budget.startDay, forKey: "startDay")
            row.setValue(budget.transitionEndDay, forKey: "transitionEndDay")
            row.setValue(budget.totalUntilDay, forKey: "totalUntilDay")
            row.setValue(book, forKey: "book")
            for value in row.value(forKey: "categoryLimits") as? Set<NSManagedObject> ?? [] { context.delete(value) }
            for categoryLimit in budget.categoryLimits {
                let value = NSEntityDescription.insertNewObject(forEntityName: "BudgetCategoryRecord", into: context)
                value.setValue(categoryLimit.categoryID, forKey: "categoryID")
                value.setValue(categoryLimit.limit, forKey: "limit")
                value.setValue(row, forKey: "budget")
            }
            try commitIfNeeded()
        } catch { context.rollback(); throw error }
    }

    func save(_ budget: BudgetVersion) throws {
        try save(budget, in: budget.bookID ?? defaultBookID())
    }

    func saveCategory(_ category: ExpenseCategory, in bookID: UUID) throws {
        categoryCache.removeValue(forKey: bookID)
        let book = try bookRow(for: bookID)
        let category = try category.validated(against: categories(in: bookID))
        do {
            let row = try findCategory("CategoryRecord", id: category.id, in: book) ?? NSEntityDescription.insertNewObject(forEntityName: "CategoryRecord", into: context)
            row.setValue(category.id, forKey: "id")
            row.setValue(category.name, forKey: "name")
            row.setValue(category.symbol, forKey: "symbol")
            row.setValue(book, forKey: "book")
            try commitIfNeeded()
        } catch { context.rollback(); throw error }
    }

    func saveCategory(_ category: ExpenseCategory) throws {
        try saveCategory(category, in: defaultBookID())
    }

    func deleteCategory(_ id: UUID, in bookID: UUID) throws {
        categoryCache.removeValue(forKey: bookID)
        guard try !bills(in: bookID).contains(where: { $0.categoryID == id }) else { throw CategoryError.inUse }
        guard try !expenses(in: bookID).contains(where: { $0.allocations.contains(where: { $0.categoryID == id }) }) else { throw CategoryError.inUse }
        guard try !budgets(in: bookID).contains(where: { $0.categoryLimits.contains(where: { $0.categoryID == id }) }) else { throw CategoryError.inUse }
        do {
            let book = try bookRow(for: bookID)
            if let row = try findCategory("CategoryRecord", id: id, in: book) {
                context.delete(row)
                try commitIfNeeded()
            }
        } catch { context.rollback(); throw error }
    }

    func deleteCategory(_ id: UUID) throws {
        try deleteCategory(id, in: defaultBookID())
    }

    func updateGlobalCategoryMetadata(id: UUID, name: String, symbol: String) throws {
        categoryCache.removeAll()
        let request = NSFetchRequest<NSManagedObject>(entityName: "CategoryRecord")
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        do {
            let rows = try context.fetch(request)
            for row in rows {
                row.setValue(name, forKey: "name")
                row.setValue(symbol, forKey: "symbol")
            }
            try commitIfNeeded()
        } catch {
            context.rollback()
            throw error
        }
    }

    func activateCategory(_ category: GlobalCategory, in bookID: UUID) throws {
        categoryCache.removeValue(forKey: bookID)
        let book = try bookRow(for: bookID)
        do {
            if let existing = try findCategory("CategoryRecord", id: category.id, in: book) {
                existing.setValue(category.name, forKey: "name")
                existing.setValue(category.symbol, forKey: "symbol")
            } else {
                let row = NSEntityDescription.insertNewObject(forEntityName: "CategoryRecord", into: context)
                row.setValue(category.id, forKey: "id")
                row.setValue(category.name, forKey: "name")
                row.setValue(category.symbol, forKey: "symbol")
                row.setValue(book, forKey: "book")
            }
            try commitIfNeeded()
        } catch {
            context.rollback()
            throw error
        }
    }

    func deactivateCategory(_ categoryID: UUID, in bookID: UUID) throws {
        categoryCache.removeValue(forKey: bookID)
        let book = try bookRow(for: bookID)
        let hasAllocations = try expenses(in: bookID).contains(where: { $0.allocations.contains(where: { $0.categoryID == categoryID }) })
        let hasBills = try bills(in: bookID).contains(where: { $0.categoryID == categoryID })
        let hasBudgets = try budgets(in: bookID).contains(where: { $0.categoryLimits.contains(where: { $0.categoryID == categoryID }) })
        do {
            if !hasAllocations && !hasBills && !hasBudgets {
                if let row = try findCategory("CategoryRecord", id: categoryID, in: book) {
                    context.delete(row)
                    try commitIfNeeded()
                }
            }
        } catch {
            context.rollback()
            throw error
        }
    }

    func categoryMigrationMapping(to catalog: [GlobalCategory]) throws -> [UUID: [UUID: UUID]] {
        func norm(_ name: String) -> String {
            name.trimmingCharacters(in: .whitespacesAndNewlines).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        }
        let byName = Dictionary(catalog.map { (norm($0.name), $0.id) }, uniquingKeysWith: { first, _ in first })
        var mapping: [UUID: [UUID: UUID]] = [:]
        for row in try objects("CategoryRecord") {
            guard let book = row.value(forKey: "book") as? NSManagedObject,
                  let bookID = book.value(forKey: "id") as? UUID,
                  let oldID = row.value(forKey: "id") as? UUID,
                  let name = row.value(forKey: "name") as? String,
                  let newID = byName[norm(name)], mapping[bookID]?[oldID] == nil else {
                throw EntryError.corruptStore
            }
            mapping[bookID, default: [:]][oldID] = newID
        }
        return mapping
    }

    func unifyCategoriesToGlobalCatalog(_ catalog: [GlobalCategory]) throws {
        categoryCache.removeAll()
        let mapping = try categoryMigrationMapping(to: catalog)
        let byID = Dictionary(catalog.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        try transaction {
            for profile in try books() {
                let book = try bookRow(for: profile.id)
                let rows = (book.value(forKey: "categories") as? Set<NSManagedObject>) ?? []
                var canonicalRows: [UUID: NSManagedObject] = [:]
                for row in rows {
                    guard let oldID = row.value(forKey: "id") as? UUID,
                          let newID = mapping[profile.id]?[oldID], let category = byID[newID] else {
                        throw EntryError.corruptStore
                    }
                    if let canonical = canonicalRows[newID] {
                        for allocation in row.value(forKey: "allocations") as? Set<NSManagedObject> ?? [] {
                            allocation.setValue(canonical, forKey: "category")
                        }
                        context.delete(row)
                    } else {
                        row.setValue(newID, forKey: "id")
                        row.setValue(category.name, forKey: "name")
                        row.setValue(category.symbol, forKey: "symbol")
                        canonicalRows[newID] = row
                    }
                }
                for budget in (book.value(forKey: "budgets") as? Set<NSManagedObject>) ?? [] {
                    for limit in (budget.value(forKey: "categoryLimits") as? Set<NSManagedObject>) ?? [] {
                        guard let oldID = limit.value(forKey: "categoryID") as? UUID,
                              let newID = mapping[profile.id]?[oldID] else { throw EntryError.corruptStore }
                        limit.setValue(newID, forKey: "categoryID")
                    }
                }
                for bill in (book.value(forKey: "bills") as? Set<NSManagedObject>) ?? [] {
                    guard let oldID = bill.value(forKey: "categoryID") as? UUID,
                          let newID = mapping[profile.id]?[oldID] else { throw EntryError.corruptStore }
                    bill.setValue(newID, forKey: "categoryID")
                }
                // Validate every dependent graph before the single commit.
                _ = try expenses(in: profile.id)
                _ = try budgets(in: profile.id)
                _ = try bills(in: profile.id)
                _ = try billOccurrences(in: profile.id)
            }
        }
    }

    /// User-initiated promotion keeps categories but removes only recorded sample entries.
    func startEmptyRealBook(_ profile: BookProfile) throws {
        guard profile.kind == .real else { throw BackupError.invalid }
        do {
            let book = try bookRow(for: BookProfile.sample.id)
            for expense in try objects("ExpenseRecord") {
                if (expense.value(forKey: "book") as? NSManagedObject) == book {
                    try detachBillOccurrences(linkedTo: expense)
                    context.delete(expense)
                }
            }
            book.setValue(profile.id, forKey: "id")
            book.setValue(profile.name, forKey: "name")
            book.setValue(profile.colorIndex, forKey: "colorIndex")
            writeModelBFields(of: profile, to: book)
            try commitIfNeeded()
        } catch { context.rollback(); throw error }
    }

    func renameRealBook(_ profile: BookProfile) throws {
        guard profile.kind == .real else { throw BackupError.invalid }
        do {
            let book = try bookRow(for: profile.id)
            book.setValue(profile.name, forKey: "name")
            try commitIfNeeded()
        } catch { context.rollback(); throw error }
    }

    /// Deletes all expenses and their allocations in the specified book, or across all books if nil.
    func clearExpenses(in bookID: UUID? = nil) throws {
        do {
            let targetBook: NSManagedObject? = try bookID.map { try bookRow(for: $0) }
            let allExpenses = try objects("ExpenseRecord")
            for expense in allExpenses {
                if let targetBook {
                    if (expense.value(forKey: "book") as? NSManagedObject) == targetBook {
                        for allocation in expense.value(forKey: "allocations") as? Set<NSManagedObject> ?? [] {
                            context.delete(allocation)
                        }
                        context.delete(expense)
                    }
                } else {
                    for allocation in expense.value(forKey: "allocations") as? Set<NSManagedObject> ?? [] {
                        context.delete(allocation)
                    }
                    context.delete(expense)
                }
            }
            let occurrences = try objects("BillOccurrenceRecord")
            for occ in occurrences {
                if let rule = occ.value(forKey: "rule") as? NSManagedObject,
                   let ruleBook = rule.value(forKey: "book") as? NSManagedObject {
                    if targetBook == nil || ruleBook == targetBook {
                        if occ.value(forKey: "expenseID") != nil {
                            occ.setValue(nil, forKey: "expenseID")
                            occ.setValue(BillOccurrenceStatus.skipped.rawValue, forKey: "status")
                            occ.setValue(Date.now, forKey: "updatedAt")
                        }
                    }
                }
            }
            try commitIfNeeded()
        } catch { context.rollback(); throw error }
    }

    /// Performs a complete factory wipe of Core Data entities and initializes a single fresh real book.
    func resetToFreshWorkspace(bookName: String, categories: [ExpenseCategory] = ExpenseCategory.defaults) throws -> (bookID: UUID, categories: [ExpenseCategory]) {
        do {
            for entity in ["BillOccurrenceRecord", "BillRuleRecord", "AllocationRecord", "ExpenseRecord", "BudgetCategoryRecord", "BudgetRecord", "CategoryRecord", "Book"] {
                for row in try objects(entity) { context.delete(row) }
            }
            let newBookID = UUID()
            let book = NSEntityDescription.insertNewObject(forEntityName: "Book", into: context)
            book.setValue(newBookID, forKey: "id")
            book.setValue(bookName, forKey: "name")
            var createdCategories: [ExpenseCategory] = []
            for category in categories {
                let row = NSEntityDescription.insertNewObject(forEntityName: "CategoryRecord", into: context)
                row.setValue(category.id, forKey: "id")
                row.setValue(category.name, forKey: "name")
                row.setValue(category.symbol, forKey: "symbol")
                row.setValue(book, forKey: "book")
                createdCategories.append(category)
            }
            let initialBudget = BudgetVersion.initial(overallLimit: 5_000_000 * 100, startDay: 1, date: .now, bookID: newBookID)
            let budgetRow = NSEntityDescription.insertNewObject(forEntityName: "BudgetRecord", into: context)
            budgetRow.setValue(initialBudget.id, forKey: "id")
            budgetRow.setValue(initialBudget.overallLimit, forKey: "overallLimit")
            budgetRow.setValue(initialBudget.startDay, forKey: "startDay")
            budgetRow.setValue(initialBudget.effectiveDay, forKey: "effectiveDay")
            budgetRow.setValue(initialBudget.transitionEndDay, forKey: "transitionEndDay")
            budgetRow.setValue(book, forKey: "book")
            try commitIfNeeded()
            return (newBookID, createdCategories)
        } catch {
            context.rollback()
            throw error
        }
    }

    /// Replace the complete workspace with a single Core Data transaction.
    func replace(with workspace: WorkspaceBackup, importArtworks: Bool = true) throws {
        try workspace.validate()
        do {
            for entity in ["BillOccurrenceRecord", "BillRuleRecord", "AllocationRecord", "ExpenseRecord", "BudgetCategoryRecord", "BudgetRecord", "CategoryRecord", "Book"] {
                for row in try objects(entity) { context.delete(row) }
            }
            for item in workspace.books {
                let book = NSEntityDescription.insertNewObject(forEntityName: "Book", into: context)
                book.setValue(item.book.id, forKey: "id")
                book.setValue(item.book.name, forKey: "name")
                book.setValue(item.book.colorIndex, forKey: "colorIndex")
                writeModelBFields(of: item.book, to: book)
                var categoryRows: [UUID: NSManagedObject] = [:]
                for category in item.categories {
                    let row = NSEntityDescription.insertNewObject(forEntityName: "CategoryRecord", into: context)
                    row.setValue(category.id, forKey: "id"); row.setValue(category.name, forKey: "name")
                    row.setValue(category.symbol, forKey: "symbol"); row.setValue(book, forKey: "book")
                    categoryRows[category.id] = row
                }
                for expense in item.expenses {
                    let row = NSEntityDescription.insertNewObject(forEntityName: "ExpenseRecord", into: context)
                    row.setValue(expense.id, forKey: "id"); row.setValue(expense.amount, forKey: "amount")
                    row.setValue(expense.day, forKey: "day"); row.setValue(expense.note, forKey: "note")
                    row.setValue(expense.source, forKey: "source"); row.setValue(expense.createdAt, forKey: "createdAt")
                    writeModelBFields(of: expense, to: row)
                    row.setValue(book, forKey: "book")
                    for value in expense.allocations {
                        let allocation = NSEntityDescription.insertNewObject(forEntityName: "AllocationRecord", into: context)
                        allocation.setValue(value.amount, forKey: "amount")
                        allocation.setValue(categoryRows[value.categoryID], forKey: "category")
                        allocation.setValue(row, forKey: "expense")
                    }
                }
                let budgets = item.budgets.isEmpty
                    ? [BudgetVersion.initial(overallLimit: workspace.settings.budget, startDay: workspace.settings.startDay, date: workspace.exportedAt, bookID: item.book.id)]
                    : item.budgets
                for budget in budgets {
                    try budget.validate(categories: item.categories)
                    let row = NSEntityDescription.insertNewObject(forEntityName: "BudgetRecord", into: context)
                    row.setValue(budget.id, forKey: "id")
                    row.setValue(budget.effectiveDay, forKey: "effectiveDay")
                    row.setValue(budget.overallLimit, forKey: "overallLimit")
                    row.setValue(budget.startDay, forKey: "startDay")
                    row.setValue(budget.transitionEndDay, forKey: "transitionEndDay")
                    row.setValue(budget.totalUntilDay, forKey: "totalUntilDay")
                    row.setValue(book, forKey: "book")
                    for categoryLimit in budget.categoryLimits {
                        let value = NSEntityDescription.insertNewObject(forEntityName: "BudgetCategoryRecord", into: context)
                        value.setValue(categoryLimit.categoryID, forKey: "categoryID")
                        value.setValue(categoryLimit.limit, forKey: "limit")
                        value.setValue(row, forKey: "budget")
                    }
                }
                var billRows: [UUID: NSManagedObject] = [:]
                if let bills = item.bills {
                    for bill in bills {
                        try bill.validate(categories: item.categories)
                        let row = NSEntityDescription.insertNewObject(forEntityName: "BillRuleRecord", into: context)
                        row.setValue(bill.id, forKey: "id")
                        row.setValue(bill.name, forKey: "name")
                        row.setValue(bill.amount, forKey: "amount")
                        row.setValue(bill.categoryID, forKey: "categoryID")
                        switch bill.recurrence {
                        case .monthly(let day):
                            row.setValue("monthly", forKey: "recurrenceType")
                            row.setValue(Int16(day), forKey: "recurrenceDay")
                            row.setValue(Int16(1), forKey: "recurrenceMonth")
                        case .weekly(let weekday):
                            row.setValue("weekly", forKey: "recurrenceType")
                            row.setValue(Int16(weekday), forKey: "recurrenceDay")
                            row.setValue(Int16(1), forKey: "recurrenceMonth")
                        case .yearly(let month, let day):
                            row.setValue("yearly", forKey: "recurrenceType")
                            row.setValue(Int16(day), forKey: "recurrenceDay")
                            row.setValue(Int16(month), forKey: "recurrenceMonth")
                        }
                        row.setValue(bill.recordingMode == .automatic, forKey: "isAutomatic")
                        row.setValue(bill.hasReminder, forKey: "hasReminder")
                        row.setValue(Int16(bill.reminderLeadDays), forKey: "reminderLeadDays")
                        row.setValue(bill.isActive, forKey: "isActive")
                        row.setValue(bill.createdAt, forKey: "createdAt")
                        row.setValue(bill.scheduleEffectiveDay, forKey: "scheduleEffectiveDay")
                        row.setValue(bill.scheduleRevision, forKey: "scheduleRevision")
                        row.setValue(book, forKey: "book")
                        billRows[bill.id] = row
                    }
                }
                if let occurrences = item.billOccurrences {
                    for occ in occurrences {
                        guard let ruleRow = billRows[occ.billRuleID] else { throw EntryError.corruptStore }
                        let row = NSEntityDescription.insertNewObject(forEntityName: "BillOccurrenceRecord", into: context)
                        row.setValue(occ.id, forKey: "id")
                        row.setValue(occ.dueDay, forKey: "dueDay")
                        row.setValue(occ.status.rawValue, forKey: "status")
                        row.setValue(occ.expenseID, forKey: "expenseID")
                        row.setValue(occ.createdAt, forKey: "createdAt")
                        row.setValue(occ.updatedAt, forKey: "updatedAt")
                        row.setValue(ruleRow, forKey: "rule")
                    }
                }
            }
            try commitIfNeeded()
            if importArtworks, let artworks = workspace.cardArtworks {
                for (filename, data) in artworks {
                    try CardArtworkStore.shared.importArtworkData(data, filename: filename)
                }
            }
        } catch { context.rollback(); throw error }
    }

    /// Replace single-book legacy backup by wrapping it into WorkspaceBackup
    func replace(with backup: BookBackup) throws {
        try replace(with: WorkspaceBackup(singleBook: backup))
    }

    func delete(_ id: UUID) throws {
        do {
            if let row = try find("ExpenseRecord", id: id) {
                try detachBillOccurrences(linkedTo: row)
                context.delete(row)
                try commitIfNeeded()
            }
        } catch { context.rollback(); throw error }
    }

    func delete(_ id: UUID, in bookID: UUID) throws { try delete(id, in: bookID, at: .now) }

    func delete(_ id: UUID, in bookID: UUID, at date: Date) throws {
        let book = try bookRow(for: bookID)
        guard let row = try findCategory("ExpenseRecord", id: id, in: book) else { throw EntryError.corruptStore }
        do {
            try detachBillOccurrences(linkedTo: row, at: date)
            context.delete(row)
            try commitIfNeeded()
        } catch { context.rollback(); throw error }
    }

    func bookRow(for id: UUID) throws -> NSManagedObject {
        if transactionDepth > 0, let cached = bookCache[id], !cached.isDeleted { return cached }
        guard let book = try find("Book", id: id) else { throw EntryError.corruptStore }
        if transactionDepth > 0 { bookCache[id] = book }
        return book
    }

    private func defaultBook() throws -> NSManagedObject {
        let books = try objects("Book")
        guard let first = books.first else { throw EntryError.corruptStore }
        return first
    }

    private func defaultBookID() throws -> UUID {
        guard let id = try defaultBook().value(forKey: "id") as? UUID else { throw EntryError.corruptStore }
        return id
    }

    private func detachBillOccurrences(linkedTo expense: NSManagedObject, at date: Date = .now) throws {
        guard let id = expense.value(forKey: "id") as? UUID,
              let book = expense.value(forKey: "book") as? NSManagedObject else { throw EntryError.corruptStore }
        let request = NSFetchRequest<NSManagedObject>(entityName: "BillOccurrenceRecord")
        request.predicate = NSPredicate(format: "expenseID == %@ AND rule.book == %@", id as NSUUID, book)
        for occurrence in try context.fetch(request) {
            occurrence.setValue(nil, forKey: "expenseID")
            occurrence.setValue(BillOccurrenceStatus.skipped.rawValue, forKey: "status")
            occurrence.setValue(date, forKey: "updatedAt")
        }
    }

    private func validateAggregate() throws {
        let amounts = try objects("ExpenseRecord").map { row -> Int64 in
            guard let amount = row.value(forKey: "amount") as? Int64 else { throw EntryError.corruptStore }
            return amount
        }
        _ = try Money.checkedSum(amounts)
    }

    private func objects(_ entity: String) throws -> [NSManagedObject] { try context.fetch(NSFetchRequest<NSManagedObject>(entityName: entity)) }

    private func find(_ entity: String, id: UUID) throws -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: entity)
        request.predicate = NSPredicate(format: "id == %@", id as NSUUID)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    private func findCategory(_ entity: String, id: UUID, in book: NSManagedObject) throws -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: entity)
        request.predicate = NSPredicate(format: "id == %@ AND book == %@", id as NSUUID, book)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    private func findBudget(_ entity: String, id: UUID, in book: NSManagedObject) throws -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: entity)
        request.predicate = NSPredicate(format: "id == %@ AND book == %@", id as NSUUID, book)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    private func findBillRule(_ entity: String, id: UUID, in book: NSManagedObject) throws -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: entity)
        request.predicate = NSPredicate(format: "id == %@ AND book == %@", id as NSUUID, book)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    private func findOccurrence(_ entity: String, id: UUID, in rule: NSManagedObject) throws -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: entity)
        request.predicate = NSPredicate(format: "id == %@ AND rule == %@", id as NSUUID, rule)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }
}
