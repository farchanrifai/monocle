import CoreData
import Foundation

@MainActor
final class ExpenseRepository: ExpenseStore {
    static let bookID = UUID(uuidString: "20000000-0000-0000-0000-000000000001")!
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
            book.setValue(Self.bookID, forKey: "id")
            book.setValue("Sample book", forKey: "name")
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

    func save(_ expense: Expense) throws {
        try expense.validate(categories: categories())
        do {
            let existing = try find("ExpenseRecord", id: expense.id)
            let row = existing ?? NSEntityDescription.insertNewObject(forEntityName: "ExpenseRecord", into: context)
            guard let book = try find("Book", id: Self.bookID) else { throw EntryError.corruptStore }
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

    func saveCategory(_ category: ExpenseCategory) throws {
        let category = try category.validated(against: categories())
        do {
            guard let book = try find("Book", id: Self.bookID) else { throw EntryError.corruptStore }
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

    func delete(_ id: UUID) throws {
        do {
            if let row = try find("ExpenseRecord", id: id) { context.delete(row); try context.save() }
        } catch { context.rollback(); throw error }
    }
    private func objects(_ entity: String) throws -> [NSManagedObject] { try context.fetch(NSFetchRequest<NSManagedObject>(entityName: entity)) }
    private func find(_ entity: String, id: UUID) throws -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: entity)
        request.predicate = NSPredicate(format: "id == %@", id as NSUUID)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }
}
