import CoreData
import Foundation

@MainActor
final class ExpenseRepository: ExpenseStore {
    let container: NSPersistentContainer
    private var context: NSManagedObjectContext { container.viewContext }

    private var transactionDepth = 0

    func transaction(_ operation: () throws -> Void) throws {
        transactionDepth += 1
        defer { transactionDepth -= 1 }
        do {
            try operation()
            if transactionDepth == 1 { try context.save() }
        } catch {
            context.rollback()
            throw error
        }
    }

    private func commitIfNeeded() throws {
        if transactionDepth == 0 && context.hasChanges { try context.save() }
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
            return BookProfile(id: id, name: name, kind: kind)
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
        let book = try bookRow(for: bookID)
        let cats = try categories(in: bookID)
        let set = (book.value(forKey: "expenses") as? Set<NSManagedObject>) ?? []
        return try set.map { row in
            guard let id = row.value(forKey: "id") as? UUID, let day = row.value(forKey: "day") as? String,
                  let createdAt = row.value(forKey: "createdAt") as? Date,
                  let amount = row.value(forKey: "amount") as? Int64,
                  let allocations = row.value(forKey: "allocations") as? Set<NSManagedObject> else { throw EntryError.corruptStore }
            let values = try allocations.map { allocation -> Allocation in
                guard let category = allocation.value(forKey: "category") as? NSManagedObject,
                      let categoryID = category.value(forKey: "id") as? UUID,
                      let value = allocation.value(forKey: "amount") as? Int64 else { throw EntryError.corruptStore }
                return Allocation(categoryID: categoryID, amount: value)
            }.sorted { $0.categoryID.uuidString < $1.categoryID.uuidString }
            let expense = Expense(id: id, amount: amount, day: day, note: row.value(forKey: "note") as? String ?? "", allocations: values, source: row.value(forKey: "source") as? String ?? "manual", createdAt: createdAt, bookID: bookID)
            try expense.validate(categories: cats)
            return expense
        }.sorted { $0.day == $1.day ? $0.createdAt > $1.createdAt : $0.day > $1.day }
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
                                       bookID: bookID)
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
        let set = (book.value(forKey: "bills") as? Set<NSManagedObject>) ?? []
        return try set.map { row in
            guard let id = row.value(forKey: "id") as? UUID,
                  let name = row.value(forKey: "name") as? String,
                  let amount = row.value(forKey: "amount") as? Int64,
                  let categoryID = row.value(forKey: "categoryID") as? UUID,
                  let createdAt = row.value(forKey: "createdAt") as? Date else { throw EntryError.corruptStore }
            let recurrenceType = row.value(forKey: "recurrenceType") as? String ?? "monthly"
            let recurrenceDay = (row.value(forKey: "recurrenceDay") as? NSNumber)?.intValue ?? 1
            let recurrenceMonth = (row.value(forKey: "recurrenceMonth") as? NSNumber)?.intValue ?? 1
            let recurrence: BillRecurrence
            switch recurrenceType {
            case "weekly": recurrence = .weekly(weekday: recurrenceDay)
            case "yearly": recurrence = .yearly(month: recurrenceMonth, day: recurrenceDay)
            default: recurrence = .monthly(day: recurrenceDay)
            }
            let isAutomatic = (row.value(forKey: "isAutomatic") as? NSNumber)?.boolValue ?? false
            let hasReminder = (row.value(forKey: "hasReminder") as? NSNumber)?.boolValue ?? true
            let reminderLeadDays = (row.value(forKey: "reminderLeadDays") as? NSNumber)?.intValue ?? 0
            let isActive = (row.value(forKey: "isActive") as? NSNumber)?.boolValue ?? true
            return BillRule(
                id: id,
                bookID: bookID,
                name: name,
                amount: amount,
                categoryID: categoryID,
                recurrence: recurrence,
                recordingMode: isAutomatic ? .automatic : .pending,
                hasReminder: hasReminder,
                reminderLeadDays: reminderLeadDays,
                createdAt: createdAt,
                isActive: isActive
            )
        }.sorted { $0.createdAt < $1.createdAt }
    }

    func bills() throws -> [BillRule] {
        try bills(in: defaultBookID())
    }

    func billOccurrences(in bookID: UUID) throws -> [BillOccurrence] {
        let book = try bookRow(for: bookID)
        let billRules = (book.value(forKey: "bills") as? Set<NSManagedObject>) ?? []
        var occurrences: [BillOccurrence] = []
        for rule in billRules {
            guard let ruleID = rule.value(forKey: "id") as? UUID else { continue }
            let occSet = (rule.value(forKey: "occurrences") as? Set<NSManagedObject>) ?? []
            for row in occSet {
                guard let id = row.value(forKey: "id") as? UUID,
                      let dueDay = row.value(forKey: "dueDay") as? String,
                      let statusStr = row.value(forKey: "status") as? String,
                      let status = BillOccurrenceStatus(rawValue: statusStr),
                      let createdAt = row.value(forKey: "createdAt") as? Date,
                      let updatedAt = row.value(forKey: "updatedAt") as? Date else { continue }
                let expenseID = row.value(forKey: "expenseID") as? UUID
                occurrences.append(BillOccurrence(
                    id: id,
                    billRuleID: ruleID,
                    bookID: bookID,
                    dueDay: dueDay,
                    status: status,
                    expenseID: expenseID,
                    createdAt: createdAt,
                    updatedAt: updatedAt
                ))
            }
        }
        return occurrences.sorted { $0.dueDay < $1.dueDay }
    }

    func billOccurrences() throws -> [BillOccurrence] {
        try billOccurrences(in: defaultBookID())
    }

    func saveBill(_ bill: BillRule, in bookID: UUID) throws {
        let book = try bookRow(for: bookID)
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
            row.setValue(book, forKey: "book")
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

    func save(_ expense: Expense, in bookID: UUID) throws {
        let book = try bookRow(for: bookID)
        try expense.validate(categories: categories(in: bookID))
        do {
            let existing = try find("ExpenseRecord", id: expense.id)
            if let existing, let existingBook = existing.value(forKey: "book") as? NSManagedObject,
               let existingID = existingBook.value(forKey: "id") as? UUID, existingID != bookID {
                throw EntryError.corruptStore // Reject cross-book reparenting
            }
            let row = existing ?? NSEntityDescription.insertNewObject(forEntityName: "ExpenseRecord", into: context)
            row.setValue(expense.id, forKey: "id"); row.setValue(expense.amount, forKey: "amount")
            row.setValue(expense.day, forKey: "day"); row.setValue(expense.note, forKey: "note")
            row.setValue(expense.source, forKey: "source"); row.setValue(expense.createdAt, forKey: "createdAt")
            row.setValue(book, forKey: "book")
            for allocation in row.value(forKey: "allocations") as? Set<NSManagedObject> ?? [] { context.delete(allocation) }
            for value in expense.allocations {
                guard let category = try findCategory("CategoryRecord", id: value.categoryID, in: book) else { throw EntryError.missingCategory }
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
        guard try !bills(in: bookID).contains(where: { $0.categoryID == id }) else { throw CategoryError.inUse }
        guard try !expenses(in: bookID).contains(where: { $0.allocations.contains(where: { $0.categoryID == id }) }) else { throw CategoryError.inUse }
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
        let book = try bookRow(for: bookID)
        let hasAllocations = try expenses(in: bookID).contains(where: { $0.allocations.contains(where: { $0.categoryID == categoryID }) })
        let hasBills = try bills(in: bookID).contains(where: { $0.categoryID == categoryID })
        do {
            if !hasAllocations && !hasBills {
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

    func unifyCategoriesToGlobalCatalog(_ catalog: [GlobalCategory]) throws {
        func norm(_ name: String) -> String {
            name.trimmingCharacters(in: .whitespacesAndNewlines).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        }
        let catalogByName = Dictionary(catalog.map { (norm($0.name), $0) }, uniquingKeysWith: { first, _ in first })
        do {
            let catRows = try objects("CategoryRecord")
            let budgetCatRows = try objects("BudgetCategoryRecord")
            let billRows = try objects("BillRuleRecord")

            var idMapping: [UUID: UUID] = [:]

            for row in catRows {
                guard let name = row.value(forKey: "name") as? String,
                      let currentID = row.value(forKey: "id") as? UUID,
                      let global = catalogByName[norm(name)] else { continue }
                if currentID != global.id {
                    row.setValue(global.id, forKey: "id")
                    idMapping[currentID] = global.id
                }
            }

            if !idMapping.isEmpty {
                for bRow in budgetCatRows {
                    if let oldID = bRow.value(forKey: "categoryID") as? UUID, let newID = idMapping[oldID] {
                        bRow.setValue(newID, forKey: "categoryID")
                    }
                }
                for billRow in billRows {
                    if let oldID = billRow.value(forKey: "categoryID") as? UUID, let newID = idMapping[oldID] {
                        billRow.setValue(newID, forKey: "categoryID")
                    }
                }
            }
            try commitIfNeeded()
        } catch {
            context.rollback()
            throw error
        }
    }

    /// User-initiated promotion keeps categories but removes only recorded sample entries.
    func startEmptyRealBook(_ profile: BookProfile) throws {
        guard profile.kind == .real else { throw BackupError.invalid }
        do {
            let book = try defaultBook()
            for expense in try objects("ExpenseRecord") {
                if (expense.value(forKey: "book") as? NSManagedObject) == book {
                    context.delete(expense)
                }
            }
            book.setValue(profile.id, forKey: "id")
            book.setValue(profile.name, forKey: "name")
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
                            occ.setValue(BillOccurrenceStatus.pending.rawValue, forKey: "status")
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
                        row.setValue(book, forKey: "book")
                        billRows[bill.id] = row
                    }
                }
                if let occurrences = item.billOccurrences {
                    for occ in occurrences {
                        guard let ruleRow = billRows[occ.billRuleID] else { continue }
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
            if let row = try find("ExpenseRecord", id: id) { context.delete(row); try commitIfNeeded() }
        } catch { context.rollback(); throw error }
    }

    func bookRow(for id: UUID) throws -> NSManagedObject {
        guard let book = try find("Book", id: id) else { throw EntryError.corruptStore }
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
