import Foundation

/// The only production composition root. Tests provide their own stores and models.
@MainActor
final class AppEnvironment {
    static var shared = AppEnvironment()
    var model: AppModel
    var expenses: ExpenseService?

    private init() {
        do {
            let directory = try Self.storageDirectory()
            let state = FileLocalStateStore(directory: directory)
            // Fail without replacing malformed user files or seeding over existing data.
            let repository = try ExpenseRepository(url: directory.appendingPathComponent("Monocle.sqlite"))
            try BackupService.recoverIfNeeded(directory: directory, repository: repository, state: state)
            let draft = try state.loadDraft()
            var settings = try state.loadSettings()
            let preferences = try state.loadWorkspacePreferences()
            let books = try repository.books()
            var categoriesByBook: [UUID: [ExpenseCategory]] = [:]
            for book in books { categoriesByBook[book.id] = try repository.categories(in: book.id) }
            try preferences.validate(books: books, categoriesByBook: categoriesByBook)
            let settingsBooks: [BookBackupItem] = books.isEmpty
                ? [BookBackupItem(book: .sample, categories: Self.initialCategories(directory: directory), expenses: [], budgets: [])]
                : books.map { BookBackupItem(book: $0, categories: categoriesByBook[$0.id] ?? [], expenses: [], budgets: []) }
            try settings.validate(books: settingsBooks, globalCategories: preferences.globalCategories, allowLegacySampleProfile: true)
            let originalSettings = settings
            if let stored = books.first(where: { $0.id == settings.book.id }) { settings.book = stored }
            else if settings.book == .sample, let stored = books.first { settings.book = stored }
            if settings != originalSettings { try state.saveSettings(settings) }
            try repository.prepareSampleBook(categories: Self.initialCategories(directory: directory))
            try repository.prepareInitialBudget(settings: settings)
            try SampleBookSeeder.seedIfNeeded(repository: repository, directory: directory)
            #if DEBUG
            // UI runs get isolated stores; reset chat opt-in too, since Keychain and defaults outlive a run.
            if directory.lastPathComponent.hasPrefix("monocle-ui-test-") {
                APIKeyStore.delete()
                UserDefaults.standard.removeObject(forKey: "chatEnabled")
            }
            if directory.lastPathComponent.hasPrefix("monocle-ui-test-"),
               ProcessInfo.processInfo.environment["MONOCLE_TEST_THREE_CARDS"] == "1",
               try repository.books().count == 1 {
                try repository.transaction {
                    _ = try repository.createBook(named: "UI card two")
                    _ = try repository.createBook(named: "UI card three")
                }
            }
            #endif
            let expenses = try ExpenseService(store: repository)
            expenses.configure(categoryRules: settings.categoryRules, archivedCategoryIDs: settings.archivedCategoryIDs)
            self.expenses = expenses
            let backups = BackupService(directory: directory, repository: repository, state: state, expenses: expenses)
            model = AppModel(expenses: expenses, state: state, draft: draft, settings: settings, backups: backups)
        } catch {
            expenses = nil
            model = AppModel(startupFailure: error.localizedDescription)
        }
    }

    private static func storageDirectory() throws -> URL {
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        var folder = "monocle-prototype"
        #if DEBUG
        if let run = ProcessInfo.processInfo.environment["MONOCLE_TEST_RUN"], UUID(uuidString: run) != nil {
            folder = "monocle-ui-test-" + run
        }
        #endif
        let directory = support.appendingPathComponent(folder, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func initialCategories(directory: URL) -> [ExpenseCategory] {
        var categories = ExpenseCategory.defaults
        #if DEBUG
        if directory.lastPathComponent.hasPrefix("monocle-ui-test-"), ProcessInfo.processInfo.environment["MONOCLE_MANY_CATEGORIES"] == "1" {
            categories += ["Travel", "Education", "Gifts", "Pets", "Insurance", "Family", "Subscriptions", "Charity", "Work", "Sport", "Garden", "Other"].enumerated().map { index, name in
                ExpenseCategory(id: UUID(uuidString: String(format: "10000000-0000-0000-0000-%012d", index + 7))!, name: name, symbol: "circle.grid.2x2")
            }
        }
        #endif
        return categories
    }
}
