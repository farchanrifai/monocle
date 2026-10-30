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
            let repository = try ExpenseRepository(url: directory.appendingPathComponent("Ankka.sqlite"))
            try BackupService.recoverIfNeeded(directory: directory, repository: repository, state: state)
            let draft = try state.loadDraft()
            var settings = try state.loadSettings()
            let preferences = try state.loadWorkspacePreferences()
            let cards = try repository.cards()
            var categoriesByCard: [UUID: [ExpenseCategory]] = [:]
            for card in cards { categoriesByCard[card.id] = try repository.categories(in: card.id) }
            try preferences.validate(cards: cards, categoriesByCard: categoriesByCard)
            let settingsCards: [CardBackupItem] = cards.isEmpty
                ? [CardBackupItem(card: .demo, categories: Self.initialCategories(directory: directory), expenses: [], budgets: [])]
                : cards.map { CardBackupItem(card: $0, categories: categoriesByCard[$0.id] ?? [], expenses: [], budgets: []) }
            try settings.validate(cards: settingsCards, globalCategories: preferences.globalCategories, allowLegacySampleProfile: true)
            let originalSettings = settings
            if let stored = cards.first(where: { $0.id == settings.card.id }) { settings.card = stored }
            else if settings.card == .demo, let stored = cards.first { settings.card = stored }
            if settings != originalSettings { try state.saveSettings(settings) }
            try repository.prepareSampleCard(categories: Self.initialCategories(directory: directory))
            try repository.prepareInitialBudget(settings: settings)
            try SampleCardSeeder.seedIfNeeded(repository: repository, directory: directory)
            #if DEBUG
            if directory.lastPathComponent.hasPrefix("ankka-ui-test-"),
               ProcessInfo.processInfo.environment["ANKKA_TEST_THREE_CARDS"] == "1",
               try repository.cards().count == 1 {
                try repository.transaction {
                    _ = try repository.createCard(named: "UI card two")
                    _ = try repository.createCard(named: "UI card three")
                }
            }
            #endif
            let expenses = try ExpenseService(store: repository)
            expenses.configure(categoryRules: settings.categoryRules, archivedCategoryIDs: settings.archivedCategoryIDs)
            self.expenses = expenses
            let backups = BackupService(directory: directory, repository: repository, state: state, expenses: expenses)
            var appLock: AppLockController?
            #if DEBUG
            if directory.lastPathComponent.hasPrefix("ankka-ui-test-"), ProcessInfo.processInfo.environment["ANKKA_TEST_APP_LOCK"] == "1" {
                settings.appLockTimeout = .immediately // reload() re-applies the saved setting
                appLock = AppLockController(timeout: .immediately, authenticator: TestAuthenticator())
            }
            #endif
            model = AppModel(expenses: expenses, state: state, draft: draft, settings: settings, appLock: appLock, backups: backups)
            model.chat = ChatSession(fileURL: directory.appendingPathComponent("chat.json"))
            #if os(iOS)
            // ponytail: the Mac app stays unrestricted until it ships with universal purchase.
            var usesPlan = true
            #if DEBUG
            // UI runs see every feature unless they test the plan (ANKKA_TEST_PLAN=1, with -ankkaPro YES/NO).
            if directory.lastPathComponent.hasPrefix("ankka-ui-test-") { usesPlan = ProcessInfo.processInfo.environment["ANKKA_TEST_PLAN"] == "1" }
            #endif
            if usesPlan { model.pro = ProStore() }
            #endif
            var onboards = model.needsOnboarding
            #if DEBUG
            if directory.lastPathComponent.hasPrefix("ankka-ui-test-") { onboards = ProcessInfo.processInfo.environment["ANKKA_TEST_ONBOARDING"] == "1" }
            #endif
            model.showOnboarding = onboards
            #if DEBUG
            // Screenshot hooks: ANKKA_SHOW_PAYWALL=1 opens the paywall; ANKKA_ONBOARDING_STEP picks the step.
            if ProcessInfo.processInfo.environment["ANKKA_SHOW_PAYWALL"] != nil { model.paywall = PlanError.cardLimit.localizedDescription }
            if let step = ProcessInfo.processInfo.environment["ANKKA_ONBOARDING_STEP"] { model.showOnboarding = step != "none" }
            #endif
            #if DEBUG
            // ANKKA_DEMO=1: a separate ankka-demo folder, filled once with DemoWorkspace through the normal restore path.
            let demoMarker = directory.appendingPathComponent("demo-seeded")
            if directory.lastPathComponent == "ankka-demo", !FileManager.default.fileExists(atPath: demoMarker.path) {
                try model.restoreWorkspaceBackup(DemoWorkspace.make())
                try Data("1".utf8).write(to: demoMarker, options: .atomic)
            }
            #endif
        } catch {
            expenses = nil
            model = AppModel(startupFailure: error.localizedDescription)
        }
    }

    private static func storageDirectory() throws -> URL {
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        #if os(macOS)
        var folder = "ankka-mac"
        #else
        var folder = "ankka-prototype"
        #endif
        #if DEBUG
        if let run = ProcessInfo.processInfo.environment["ANKKA_TEST_RUN"], UUID(uuidString: run) != nil {
            folder = "ankka-ui-test-" + run
        }
        if ProcessInfo.processInfo.environment["ANKKA_DEMO"] == "1" { folder = "ankka-demo" }
        #endif
        let directory = support.appendingPathComponent(folder, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func initialCategories(directory: URL) -> [ExpenseCategory] {
        var categories = ExpenseCategory.defaults
        #if DEBUG
        if directory.lastPathComponent.hasPrefix("ankka-ui-test-"), ProcessInfo.processInfo.environment["ANKKA_MANY_CATEGORIES"] == "1" {
            categories += ["Travel", "Education", "Gifts", "Pets", "Insurance", "Family", "Subscriptions", "Charity", "Work", "Sport", "Garden", "Other"].enumerated().map { index, name in
                ExpenseCategory(id: UUID(uuidString: String(format: "10000000-0000-0000-0000-%012d", index + 7))!, name: name, symbol: "circle.grid.2x2")
            }
        }
        #endif
        return categories
    }
}

#if DEBUG
/// UI tests only: stands in for Face ID so lock behavior can be exercised on the simulator.
@MainActor
private final class TestAuthenticator: DeviceAuthenticating {
    func authenticate(reason: String) async -> Result<Void, AppLockError> { .success(()) }
}
#endif
