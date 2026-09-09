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

    func categories() throws -> [ExpenseCategory] {
        try objects("CategoryRecord").map { row in
            guard let id = row.value(forKey: "id") as? UUID, let name = row.value(forKey: "name") as? String,
                  let symbol = row.value(forKey: "symbol") as? String else { throw EntryError.corruptStore }
            return ExpenseCategory(id: id, name: name, symbol: symbol)
        }.sorted { $0.id.uuidString < $1.id.uuidString }
    }

    func expenses() throws -> [Expense] {
        let categories = try categories()
        return try objects("ExpenseRecord").map { row in
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
            let expense = Expense(id: id, amount: amount, day: day, note: row.value(forKey: "note") as? String ?? "", allocations: values, source: row.value(forKey: "source") as? String ?? "manual", createdAt: createdAt)
            try expense.validate(categories: categories)
            return expense
        }.sorted { $0.day == $1.day ? $0.createdAt > $1.createdAt : $0.day > $1.day }
    }

    func budgets() throws -> [BudgetVersion] {
        let categories = try categories()
        let values = try objects("BudgetRecord").map { row -> BudgetVersion in
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
                                       transitionEndDay: row.value(forKey: "transitionEndDay") as? String)
            try budget.validate(categories: categories)
            return budget
        }.sorted { $0.effectiveDay < $1.effectiveDay }
        guard Set(values.map(\.effectiveDay)).count == values.count else { throw EntryError.corruptStore }
        return values
    }

    func prepareInitialBudget(settings: PrototypeSettings) throws {
        guard try budgets().isEmpty else { return }
        try save(BudgetVersion.initial(overallLimit: settings.budget, startDay: settings.startDay))
    }

    func save(_ expense: Expense) throws {
        try expense.validate(categories: categories())
        do {
            let existing = try find("ExpenseRecord", id: expense.id)
            let row = existing ?? NSEntityDescription.insertNewObject(forEntityName: "ExpenseRecord", into: context)
            let book = try currentBook()
            row.setValue(expense.id, forKey: "id"); row.setValue(expense.amount, forKey: "amount")
            row.setValue(expense.day, forKey: "day"); row.setValue(expense.note, forKey: "note")
            row.setValue(expense.source, forKey: "source"); row.setValue(expense.createdAt, forKey: "createdAt")
            row.setValue(book, forKey: "book")
            for allocation in row.value(forKey: "allocations") as? Set<NSManagedObject> ?? [] { context.delete(allocation) }
            for value in expense.allocations {
                guard let category = try find("CategoryRecord", id: value.categoryID) else { throw EntryError.missingCategory }
                let allocation = NSEntityDescription.insertNewObject(forEntityName: "AllocationRecord", into: context)
                allocation.setValue(value.amount, forKey: "amount"); allocation.setValue(category, forKey: "category")
                allocation.setValue(row, forKey: "expense")
            }
            try context.save()
        } catch { context.rollback(); throw error }
    }

    func save(_ budget: BudgetVersion) throws {
        try budget.validate(categories: categories())
        do {
            for row in try objects("BudgetRecord") where
                row.value(forKey: "effectiveDay") as? String == budget.effectiveDay &&
                row.value(forKey: "id") as? UUID != budget.id {
                context.delete(row)
            }
            let row = try find("BudgetRecord", id: budget.id) ?? NSEntityDescription.insertNewObject(forEntityName: "BudgetRecord", into: context)
            let book = try currentBook()
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

    func saveCategory(_ category: ExpenseCategory) throws {
        let category = try category.validated(against: categories())
        do {
            let book = try currentBook()
            let row = try find("CategoryRecord", id: category.id) ?? NSEntityDescription.insertNewObject(forEntityName: "CategoryRecord", into: context)
            row.setValue(category.id, forKey: "id")
            row.setValue(category.name, forKey: "name")
            row.setValue(category.symbol, forKey: "symbol")
            row.setValue(book, forKey: "book")
            try context.save()
        } catch { context.rollback(); throw error }
    }

    func deleteCategory(_ id: UUID) throws {
        guard try !expenses().contains(where: { $0.allocations.contains(where: { $0.categoryID == id }) }) else { throw CategoryError.inUse }
        do {
            if let row = try find("CategoryRecord", id: id) { context.delete(row); try context.save() }
        } catch { context.rollback(); throw error }
    }

    /// User-initiated promotion keeps categories but removes only recorded sample entries.
    func startEmptyRealBook(_ profile: BookProfile) throws {
        guard profile.kind == .real else { throw BackupError.invalid }
        do {
            let book = try currentBook()
            for expense in try objects("ExpenseRecord") { context.delete(expense) }
            book.setValue(profile.id, forKey: "id")
            book.setValue(profile.name, forKey: "name")
            try context.save()
        } catch { context.rollback(); throw error }
    }

    func renameRealBook(_ profile: BookProfile) throws {
        guard profile.kind == .real else { throw BackupError.invalid }
        do {
            let book = try currentBook()
            guard book.value(forKey: "id") as? UUID == profile.id else { throw EntryError.corruptStore }
            book.setValue(profile.name, forKey: "name")
            try context.save()
        } catch { context.rollback(); throw error }
    }

    /// Replace the complete graph with a single Core Data transaction.
    func replace(with backup: BookBackup) throws {
        try backup.validate()
        do {
            for entity in ["AllocationRecord", "ExpenseRecord", "BudgetCategoryRecord", "BudgetRecord", "CategoryRecord", "Book"] {
                for row in try objects(entity) { context.delete(row) }
            }
            let book = NSEntityDescription.insertNewObject(forEntityName: "Book", into: context)
            book.setValue(backup.bookID, forKey: "id")
            book.setValue(backup.bookName, forKey: "name")
            var categoryRows: [UUID: NSManagedObject] = [:]
            for category in backup.categories {
                let row = NSEntityDescription.insertNewObject(forEntityName: "CategoryRecord", into: context)
                row.setValue(category.id, forKey: "id"); row.setValue(category.name, forKey: "name")
                row.setValue(category.symbol, forKey: "symbol"); row.setValue(book, forKey: "book")
                categoryRows[category.id] = row
            }
            for expense in backup.expenses {
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
            let budgets = backup.budgets.isEmpty
                ? [BudgetVersion.initial(overallLimit: backup.settings.budget, startDay: backup.settings.startDay, date: backup.exportedAt)]
                : backup.budgets
            for budget in budgets {
                try budget.validate(categories: backup.categories)
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
            try context.save()
        } catch { context.rollback(); throw error }
    }

    func delete(_ id: UUID) throws {
        do {
            if let row = try find("ExpenseRecord", id: id) { context.delete(row); try context.save() }
        } catch { context.rollback(); throw error }
    }
    private func objects(_ entity: String) throws -> [NSManagedObject] { try context.fetch(NSFetchRequest<NSManagedObject>(entityName: entity)) }
    private func currentBook() throws -> NSManagedObject {
        let books = try objects("Book")
        guard books.count == 1 else { throw EntryError.corruptStore }
        return books[0]
    }
    private func find(_ entity: String, id: UUID) throws -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: entity)
        request.predicate = NSPredicate(format: "id == %@", id as NSUUID)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }
}
