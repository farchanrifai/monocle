import Foundation

enum BookKind: String, Codable, Equatable { case sample, real }

struct BookProfile: Identifiable, Codable, Equatable, Hashable, Sendable {
    var id: UUID
    var name: String
    var kind: BookKind
    var colorIndex: Int

    static let sample = Self(id: UUID(uuidString: "20000000-0000-0000-0000-000000000001")!, name: "Sample book", kind: .sample, colorIndex: 0)

    init(id: UUID = UUID(), name: String, kind: BookKind = .real, colorIndex: Int = 0) {
        self.id = id
        self.name = name
        self.kind = kind
        self.colorIndex = colorIndex
    }

    static func real(named name: String, colorIndex: Int = 0) throws -> Self {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 40 else { throw BackupError.invalid }
        return Self(id: UUID(), name: name, kind: .real, colorIndex: colorIndex)
    }

    func renamed(to name: String) throws -> Self {
        guard kind == .real else { throw BackupError.invalid }
        var value = try Self.real(named: name, colorIndex: colorIndex)
        value.id = id
        return value
    }

    private enum CodingKeys: String, CodingKey { case id, name, kind, colorIndex }
    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        kind = try values.decode(BookKind.self, forKey: .kind)
        colorIndex = try values.decodeIfPresent(Int.self, forKey: .colorIndex) ?? 0
    }
    func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(name, forKey: .name)
        try values.encode(kind, forKey: .kind)
        try values.encode(colorIndex, forKey: .colorIndex)
    }
}

typealias Book = BookProfile

struct BookBackup: Codable {
    var formatVersion = 3
    var exportedAt = Date.now
    var bookID = BookProfile.sample.id
    var bookName = BookProfile.sample.name
    var bookKind = BookKind.sample.rawValue
    var currency = "IDR"
    var minorUnitScale = 2
    var sampleSeeded = true
    var categories: [ExpenseCategory]
    var expenses: [Expense]
    var draft: ExpenseDraft
    var settings: PrototypeSettings
    var budgets: [BudgetVersion]

    init(formatVersion: Int = 3, exportedAt: Date = .now, bookID: UUID = BookProfile.sample.id,
         bookName: String = BookProfile.sample.name, bookKind: String = BookKind.sample.rawValue,
         currency: String = "IDR", minorUnitScale: Int = 2, sampleSeeded: Bool = true,
         categories: [ExpenseCategory], expenses: [Expense], draft: ExpenseDraft,
         settings: PrototypeSettings, budgets: [BudgetVersion]? = nil) {
        self.formatVersion = formatVersion; self.exportedAt = exportedAt; self.bookID = bookID
        self.bookName = bookName; self.bookKind = bookKind; self.currency = currency
        self.minorUnitScale = minorUnitScale; self.sampleSeeded = sampleSeeded
        self.categories = categories; self.expenses = expenses; self.draft = draft; self.settings = settings
        self.budgets = budgets ?? [BudgetVersion.initial(overallLimit: settings.budget, startDay: settings.startDay, date: exportedAt)]
    }

    private enum CodingKeys: String, CodingKey {
        case formatVersion, exportedAt, bookID, bookName, bookKind, currency, minorUnitScale, sampleSeeded
        case categories, expenses, draft, settings, budgets
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = try values.decodeIfPresent(Int.self, forKey: .formatVersion) ?? 1
        exportedAt = try values.decodeIfPresent(Date.self, forKey: .exportedAt) ?? .now
        bookID = try values.decodeIfPresent(UUID.self, forKey: .bookID) ?? BookProfile.sample.id
        bookName = try values.decodeIfPresent(String.self, forKey: .bookName) ?? BookProfile.sample.name
        bookKind = try values.decodeIfPresent(String.self, forKey: .bookKind) ?? BookKind.sample.rawValue
        currency = try values.decodeIfPresent(String.self, forKey: .currency) ?? "IDR"
        minorUnitScale = try values.decodeIfPresent(Int.self, forKey: .minorUnitScale) ?? 2
        sampleSeeded = try values.decodeIfPresent(Bool.self, forKey: .sampleSeeded) ?? true
        categories = try values.decode([ExpenseCategory].self, forKey: .categories)
        expenses = try values.decode([Expense].self, forKey: .expenses)
        draft = try values.decode(ExpenseDraft.self, forKey: .draft)
        settings = try values.decode(PrototypeSettings.self, forKey: .settings)
        budgets = try values.decodeIfPresent([BudgetVersion].self, forKey: .budgets) ?? []
    }

    func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(formatVersion, forKey: .formatVersion); try values.encode(exportedAt, forKey: .exportedAt)
        try values.encode(bookID, forKey: .bookID); try values.encode(bookName, forKey: .bookName)
        try values.encode(bookKind, forKey: .bookKind); try values.encode(currency, forKey: .currency)
        try values.encode(minorUnitScale, forKey: .minorUnitScale); try values.encode(sampleSeeded, forKey: .sampleSeeded)
        try values.encode(categories, forKey: .categories); try values.encode(expenses, forKey: .expenses)
        try values.encode(draft, forKey: .draft); try values.encode(settings, forKey: .settings)
        try values.encode(budgets, forKey: .budgets)
    }

    var total: Int64 { expenses.reduce(0) { $0 + $1.amount } }
    func validate() throws {
        guard (1...3).contains(formatVersion), currency == "IDR", minorUnitScale == 2 else { throw BackupError.unsupported }
        if formatVersion == 1 {
            guard bookKind == BookKind.sample.rawValue, bookID == BookProfile.sample.id,
                  bookName == BookProfile.sample.name, sampleSeeded else { throw BackupError.unsupported }
        } else {
            guard let kind = BookKind(rawValue: bookKind), !bookName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  bookName.count <= 40, settings.book == .init(id: bookID, name: bookName, kind: kind),
                  (kind == .sample) == sampleSeeded else { throw BackupError.invalid }
        }
        guard expenses.count <= 10_000, categories.count <= 500,
              Set(expenses.map(\.id)).count == expenses.count,
              Set(categories.map(\.id)).count == categories.count,
              settings.archivedCategoryIDs.isSubset(of: Set(categories.map(\.id))),
              settings.categoryRules.allSatisfy({ rule in (try? rule.validated(against: categories, archivedIDs: settings.archivedCategoryIDs)) == rule }),
              Set(settings.categoryRules.map(\.keyword)).count == settings.categoryRules.count,
              exportedAt.timeIntervalSince1970.isFinite,
              settings.budget > 0, settings.budget <= Money.maximum, (1...31).contains(settings.startDay) else { throw BackupError.invalid }
        for category in categories {
            guard try category.validated(against: categories) == category else { throw BackupError.invalid }
        }
        var sum: Int64 = 0
        for expense in expenses {
            try expense.validate(categories: categories)
            guard expense.createdAt.timeIntervalSince1970.isFinite else { throw BackupError.invalid }
            let next = sum.addingReportingOverflow(expense.amount)
            guard !next.overflow else { throw BackupError.invalid }
            sum = next.partialValue
        }
        if formatVersion == 3 { guard !budgets.isEmpty else { throw BackupError.invalid } }
        if !budgets.isEmpty {
            guard Set(budgets.map(\.id)).count == budgets.count,
                  Set(budgets.map(\.effectiveDay)).count == budgets.count else { throw BackupError.invalid }
            for budget in budgets { try budget.validate(categories: categories) }
        }
        if let id = draft.categoryID { guard categories.contains(where: { $0.id == id }) else { throw BackupError.invalid } }
        guard draft.date.timeIntervalSince1970.isFinite, draft.createdAt.timeIntervalSince1970.isFinite,
              !draft.editing || expenses.contains(where: { $0.id == draft.id }) else { throw BackupError.invalid }
        // Drafts are intentionally allowed to be incomplete or contain invalid input.
    }
    func encoded() throws -> Data {
        try validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        guard data.count <= Self.maximumBytes else { throw BackupError.tooLarge }
        return data
    }
    static let maximumBytes = 10 * 1024 * 1024
    static func decode(_ data: Data) throws -> Self {
        guard data.count <= maximumBytes else { throw BackupError.tooLarge }
        let value = try JSONDecoder().decode(Self.self, from: data)
        try value.validate()
        return value
    }
}

enum BookVisualDirection: String, CaseIterable, Identifiable, Codable, Sendable {
    case light = "Light"
    case instrument = "Instrument"
    case ledger = "Ledger"
    case signal = "Signal"
    var id: Self { self }
}

enum StackFilterScope: String, Codable, Equatable, Sendable {
    case activeStack
    case allCards
}

struct CardStack: Identifiable, Codable, Equatable, Hashable, Sendable {
    var id: UUID = UUID()
    var name: String
    var icon: String = "rectangle.stack"
    var cardIDs: [UUID] = []

    init(id: UUID = UUID(), name: String, icon: String = "rectangle.stack", cardIDs: [UUID] = []) {
        self.id = id
        self.name = name
        self.icon = icon
        self.cardIDs = cardIDs
    }
}

struct WorkspacePreferences: Codable, Equatable, Sendable {
    var visibleBookIDs: [UUID] = []
    var bookOrder: [UUID] = []
    var allActivitiesScope: Bool = false
    var visualDirection: String = "Light"
    var autoAppearance: Bool = false
    var cardCustomizations: [UUID: BookCardCustomization] = [:]
    var alwaysHiddenBookIDs: [UUID] = []
    var stacks: [CardStack] = []
    var activeStackID: UUID? = nil
    var filterScopeRaw: String = "activeStack"
    var entryModeRaw: String = "Keypad"
    var globalCategories: [GlobalCategory] = []
    var cardInactiveCategoryIDs: [UUID: [UUID]] = [:]

    var direction: BookVisualDirection {
        get { BookVisualDirection(rawValue: visualDirection) ?? .light }
        set { visualDirection = newValue.rawValue }
    }

    var filterScope: StackFilterScope {
        get { StackFilterScope(rawValue: filterScopeRaw) ?? .activeStack }
        set { filterScopeRaw = newValue.rawValue }
    }

    var entryMode: EntryMode {
        get { EntryMode(rawValue: entryModeRaw) ?? .keypad }
        set { entryModeRaw = newValue.rawValue }
    }

    private enum CodingKeys: String, CodingKey {
        case visibleBookIDs, bookOrder, allActivitiesScope, visualDirection, autoAppearance, cardCustomizations
        case alwaysHiddenBookIDs, stacks, activeStackID, filterScopeRaw, entryModeRaw, globalCategories, cardInactiveCategoryIDs
    }

    init(
        visibleBookIDs: [UUID] = [],
        bookOrder: [UUID] = [],
        allActivitiesScope: Bool = false,
        visualDirection: String = "Light",
        autoAppearance: Bool = false,
        cardCustomizations: [UUID: BookCardCustomization] = [:],
        alwaysHiddenBookIDs: [UUID] = [],
        stacks: [CardStack] = [],
        activeStackID: UUID? = nil,
        filterScope: StackFilterScope = .activeStack,
        entryMode: EntryMode = .keypad,
        globalCategories: [GlobalCategory] = [],
        cardInactiveCategoryIDs: [UUID: [UUID]] = [:]
    ) {
        self.visibleBookIDs = visibleBookIDs
        self.bookOrder = bookOrder
        self.allActivitiesScope = allActivitiesScope
        self.visualDirection = visualDirection
        self.autoAppearance = autoAppearance
        self.cardCustomizations = cardCustomizations
        self.alwaysHiddenBookIDs = alwaysHiddenBookIDs
        self.stacks = stacks
        self.activeStackID = activeStackID
        self.filterScopeRaw = filterScope.rawValue
        self.entryModeRaw = entryMode.rawValue
        self.globalCategories = globalCategories
        self.cardInactiveCategoryIDs = cardInactiveCategoryIDs
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        visibleBookIDs = try container.decodeIfPresent([UUID].self, forKey: .visibleBookIDs) ?? []
        bookOrder = try container.decodeIfPresent([UUID].self, forKey: .bookOrder) ?? []
        allActivitiesScope = try container.decodeIfPresent(Bool.self, forKey: .allActivitiesScope) ?? false
        visualDirection = try container.decodeIfPresent(String.self, forKey: .visualDirection) ?? "Light"
        autoAppearance = try container.decodeIfPresent(Bool.self, forKey: .autoAppearance) ?? false
        cardCustomizations = try container.decodeIfPresent([UUID: BookCardCustomization].self, forKey: .cardCustomizations) ?? [:]
        alwaysHiddenBookIDs = try container.decodeIfPresent([UUID].self, forKey: .alwaysHiddenBookIDs) ?? []
        stacks = try container.decodeIfPresent([CardStack].self, forKey: .stacks) ?? []
        activeStackID = try container.decodeIfPresent(UUID.self, forKey: .activeStackID)
        filterScopeRaw = try container.decodeIfPresent(String.self, forKey: .filterScopeRaw) ?? "activeStack"
        entryModeRaw = try container.decodeIfPresent(String.self, forKey: .entryModeRaw) ?? "Keypad"
        globalCategories = try container.decodeIfPresent([GlobalCategory].self, forKey: .globalCategories) ?? []
        cardInactiveCategoryIDs = try container.decodeIfPresent([UUID: [UUID]].self, forKey: .cardInactiveCategoryIDs) ?? [:]
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(visibleBookIDs, forKey: .visibleBookIDs)
        try container.encode(bookOrder, forKey: .bookOrder)
        try container.encode(allActivitiesScope, forKey: .allActivitiesScope)
        try container.encode(visualDirection, forKey: .visualDirection)
        try container.encode(autoAppearance, forKey: .autoAppearance)
        try container.encode(cardCustomizations, forKey: .cardCustomizations)
        try container.encode(alwaysHiddenBookIDs, forKey: .alwaysHiddenBookIDs)
        try container.encode(stacks, forKey: .stacks)
        try container.encodeIfPresent(activeStackID, forKey: .activeStackID)
        try container.encode(filterScopeRaw, forKey: .filterScopeRaw)
        try container.encode(entryModeRaw, forKey: .entryModeRaw)
        try container.encode(globalCategories, forKey: .globalCategories)
        try container.encode(cardInactiveCategoryIDs, forKey: .cardInactiveCategoryIDs)
    }
}

struct BookBackupItem: Codable, Equatable, Sendable {
    var book: BookProfile
    var categories: [ExpenseCategory]
    var expenses: [Expense]
    var budgets: [BudgetVersion]
    var draft: ExpenseDraft?
    var bills: [BillRule]?
    var billOccurrences: [BillOccurrence]?
}

struct WorkspaceBackup: Codable, Equatable, Sendable {
    var formatVersion: Int = 6
    var exportedAt: Date = .now
    var currency: String = "IDR"
    var minorUnitScale: Int = 2
    var books: [BookBackupItem]
    var preferences: WorkspacePreferences
    var settings: PrototypeSettings
    var cardArtworks: [String: Data]? = nil

    init(formatVersion: Int = 6, exportedAt: Date = .now, currency: String = "IDR", minorUnitScale: Int = 2, books: [BookBackupItem], preferences: WorkspacePreferences = .init(), settings: PrototypeSettings = .init(), cardArtworks: [String: Data]? = nil) {
        self.formatVersion = formatVersion
        self.exportedAt = exportedAt
        self.currency = currency
        self.minorUnitScale = minorUnitScale
        self.books = books
        self.preferences = preferences
        self.settings = settings
        self.cardArtworks = cardArtworks
    }

    /// Convert a single-book BookBackup (formats 1–3) into a WorkspaceBackup
    init(singleBook backup: BookBackup) {
        let kind = BookKind(rawValue: backup.bookKind) ?? (backup.bookID == BookProfile.sample.id ? .sample : .real)
        let profile = BookProfile(id: backup.bookID, name: backup.bookName, kind: kind)
        let item = BookBackupItem(book: profile, categories: backup.categories, expenses: backup.expenses, budgets: backup.budgets, draft: backup.draft, bills: nil, billOccurrences: nil)
        self.init(
            formatVersion: 6,
            exportedAt: backup.exportedAt,
            currency: backup.currency,
            minorUnitScale: backup.minorUnitScale,
            books: [item],
            preferences: WorkspacePreferences(visibleBookIDs: [profile.id], bookOrder: [profile.id]),
            settings: backup.settings
        )
    }

    func validate() throws {
        guard formatVersion >= 4 && formatVersion <= 6, currency == "IDR", minorUnitScale == 2 else { throw BackupError.unsupported }
        guard !books.isEmpty, books.count <= 100 else { throw BackupError.invalid }
        let bookIDs = Set(books.map(\.book.id))
        guard bookIDs.count == books.count else { throw BackupError.invalid }
        if let cardArtworks {
            guard cardArtworks.keys.allSatisfy(CardArtworkStore.isValidFilename) else { throw BackupError.invalid }
        }
        let expenseIDs = books.flatMap { $0.expenses.map(\.id) }
        guard Set(expenseIDs).count == expenseIDs.count else { throw BackupError.invalid }
        for item in books {
            guard !item.book.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, item.book.name.count <= 40 else { throw BackupError.invalid }
            guard item.expenses.count <= 10_000, item.categories.count <= 500 else { throw BackupError.tooLarge }
            guard Set(item.expenses.map(\.id)).count == item.expenses.count,
                  Set(item.categories.map(\.id)).count == item.categories.count else { throw BackupError.invalid }
            for cat in item.categories {
                guard try cat.validated(against: item.categories) == cat else { throw BackupError.invalid }
            }
            for exp in item.expenses {
                try exp.validate(categories: item.categories)
            }
            for budget in item.budgets {
                try budget.validate(categories: item.categories)
            }
            if let bills = item.bills {
                guard bills.count <= 1_000, Set(bills.map(\.id)).count == bills.count else { throw BackupError.invalid }
                for bill in bills {
                    guard bill.bookID == item.book.id else { throw BackupError.invalid }
                    try bill.validate(categories: item.categories)
                }
            }
            if let occurrences = item.billOccurrences {
                guard occurrences.count <= 10_000, Set(occurrences.map(\.id)).count == occurrences.count else { throw BackupError.invalid }
                let ruleIDs = Set((item.bills ?? []).map(\.id))
                for occurrence in occurrences {
                    guard occurrence.bookID == item.book.id, ruleIDs.contains(occurrence.billRuleID),
                          Day.date(occurrence.dueDay) != nil else { throw BackupError.invalid }
                }
            }
        }
    }

    func encoded() throws -> Data {
        try validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        guard data.count <= BookBackup.maximumBytes else { throw BackupError.tooLarge }
        return data
    }

    static func decode(_ data: Data) throws -> WorkspaceBackup {
        guard data.count <= BookBackup.maximumBytes else { throw BackupError.tooLarge }
        if let workspace = try? JSONDecoder().decode(WorkspaceBackup.self, from: data) {
            try workspace.validate()
            return workspace
        }
        // Fall back to decoding as legacy BookBackup (formats 1–3)
        let legacy = try BookBackup.decode(data)
        let workspace = WorkspaceBackup(singleBook: legacy)
        try workspace.validate()
        return workspace
    }
}

enum BackupError: LocalizedError {
    case unsupported, invalid, tooLarge, recoveryRequired
    var errorDescription: String? {
        switch self {
        case .unsupported: "This backup version or book type is not supported by this version of monocle."
        case .invalid: "The backup contains invalid or inconsistent records. Your current book has not been replaced."
        case .tooLarge: "This version supports backups up to 10 MB, 10,000 expenses and 500 categories."
        case .recoveryRequired: "Restoration could not finish or roll back. Restart monocle to recover from the retained safety backup. Your original data has been kept."
        }
    }
}
