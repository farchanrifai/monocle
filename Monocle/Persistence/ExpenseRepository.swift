import CoreData
import Foundation

@MainActor
final class ExpenseRepository: ExpenseStore {
    let container: NSPersistentContainer
    private var context: NSManagedObjectContext { container.viewContext }

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
            try context.save()
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
        let profile = try BookProfile.real(named: name)
        do {
            let book = NSEntityDescription.insertNewObject(forEntityName: "Book", into: context)
            book.setValue(profile.id, forKey: "id")
            book.setValue(profile.name, forKey: "name")
            for cat in ExpenseCategory.defaults {
                let row = NSEntityDescription.insertNewObject(forEntityName: "CategoryRecord", into: context)
                row.setValue(UUID(), forKey: "id")
                row.setValue(cat.name, forKey: "name")
                row.setValue(cat.symbol, forKey: "symbol")
                row.setValue(book, forKey: "book")
            }
            try context.save()
            return profile
        } catch { context.rollback(); throw error }
    }

    func renameBook(id: UUID, to name: String) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 40 else { throw BackupError.invalid }
        do {
            let book = try bookRow(for: id)
            book.setValue(trimmed, forKey: "name")
            try context.save()
        } catch { context.rollback(); throw error }
    }

    func deleteBook(id: UUID) throws {
        let allBooks = try self.books()
        guard allBooks.count > 1 else { throw BackupError.invalid }
        do {
            let book = try bookRow(for: id)
            context.delete(book)
            try context.save()
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
            try context.save()
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
            try context.save()
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
            try context.save()
        } catch { context.rollback(); throw error }
    }

    func saveCategory(_ category: ExpenseCategory) throws {
        try saveCategory(category, in: defaultBookID())
    }

    func deleteCategory(_ id: UUID, in bookID: UUID) throws {
        guard try !expenses(in: bookID).contains(where: { $0.allocations.contains(where: { $0.categoryID == id }) }) else { throw CategoryError.inUse }
        do {
            let book = try bookRow(for: bookID)
            if let row = try findCategory("CategoryRecord", id: id, in: book) {
                context.delete(row)
                try context.save()
            }
        } catch { context.rollback(); throw error }
    }

    func deleteCategory(_ id: UUID) throws {
        try deleteCategory(id, in: defaultBookID())
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
            try context.save()
        } catch { context.rollback(); throw error }
    }

    func renameRealBook(_ profile: BookProfile) throws {
        guard profile.kind == .real else { throw BackupError.invalid }
        do {
            let book = try bookRow(for: profile.id)
            book.setValue(profile.name, forKey: "name")
            try context.save()
        } catch { context.rollback(); throw error }
    }

    /// Replace the complete workspace with a single Core Data transaction.
    func replace(with workspace: WorkspaceBackup) throws {
        try workspace.validate()
        do {
            for entity in ["AllocationRecord", "ExpenseRecord", "BudgetCategoryRecord", "BudgetRecord", "CategoryRecord", "Book"] {
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
            }
            try context.save()
            if let artworks = workspace.cardArtworks {
                for (filename, data) in artworks {
                    try? CardArtworkStore.shared.importArtworkData(data, filename: filename)
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
            if let row = try find("ExpenseRecord", id: id) { context.delete(row); try context.save() }
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
}
