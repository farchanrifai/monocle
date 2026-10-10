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

    func validate() throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 40,
              name.rangeOfCharacter(from: .controlCharacters) == nil,
              (0..<CardPalette.standard.count).contains(colorIndex),
              (kind == .sample) == (id == BookProfile.sample.id) else { throw BackupError.invalid }
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

    /// Invalid in-memory candidates have no representable total; validation rejects them.
    var total: Int64? { try? Money.checkedSum(expenses.map(\.amount)) }
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
            guard expense.bookID == nil || expense.bookID == bookID,
                  expense.createdAt.timeIntervalSince1970.isFinite else { throw BackupError.invalid }
            let next = sum.addingReportingOverflow(expense.amount)
            guard !next.overflow else { throw BackupError.invalid }
            sum = next.partialValue
        }
        if formatVersion == 3 { guard !budgets.isEmpty else { throw BackupError.invalid } }
        if !budgets.isEmpty {
            guard Set(budgets.map(\.id)).count == budgets.count,
                  Set(budgets.map(\.effectiveDay)).count == budgets.count else { throw BackupError.invalid }
            for budget in budgets {
                guard budget.bookID == nil || budget.bookID == bookID else { throw BackupError.invalid }
                try budget.validate(categories: categories)
            }
        }
        if let id = draft.categoryID { guard categories.contains(where: { $0.id == id }) else { throw BackupError.invalid } }
        guard draft.bookID == nil || draft.bookID == bookID,
              draft.date.timeIntervalSince1970.isFinite, draft.createdAt.timeIntervalSince1970.isFinite,
              draft.splitAllocations.allSatisfy({ allocation in categories.contains(where: { $0.id == allocation.categoryID }) }),
              Set(draft.splitAllocations.map(\.id)).count == draft.splitAllocations.count,
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

enum ShortcutInputField: String, CaseIterable, Codable, Identifiable, Hashable, Sendable {
    case card
    case category
    case note
    case amount

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .card: return "Card / Account"
        case .category: return "Category"
        case .note: return "Short Note"
        case .amount: return "Amount (IDR)"
        }
    }

    var systemImage: String {
        switch self {
        case .card: return "creditcard.fill"
        case .category: return "tag.fill"
        case .note: return "pencil.line"
        case .amount: return "banknote.fill"
        }
    }
}

struct KeyModifiers: OptionSet, Codable, Hashable, Sendable {
    let rawValue: Int

    static let command = Self(rawValue: 1 << 0)
    static let option = Self(rawValue: 1 << 1)
    static let control = Self(rawValue: 1 << 2)
    static let shift = Self(rawValue: 1 << 3)
}

struct KeyChord: Codable, Equatable, Hashable, Sendable {
    var key: String
    var modifiers: KeyModifiers

    init(_ key: String, modifiers: KeyModifiers) {
        self.key = key.lowercased()
        self.modifiers = modifiers
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
    var shortcutInputOrder: [ShortcutInputField] = [.card, .category, .note, .amount]
    var macShortcutBindings: [String: KeyChord] = [:]

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
        case shortcutInputOrder, macShortcutBindings
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
        cardInactiveCategoryIDs: [UUID: [UUID]] = [:],
        shortcutInputOrder: [ShortcutInputField] = [.card, .category, .note, .amount],
        macShortcutBindings: [String: KeyChord] = [:]
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
        self.shortcutInputOrder = shortcutInputOrder
        self.macShortcutBindings = macShortcutBindings
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
        let decodedOrder = try container.decodeIfPresent([ShortcutInputField].self, forKey: .shortcutInputOrder) ?? [.card, .category, .note, .amount]
        self.shortcutInputOrder = decodedOrder
        macShortcutBindings = try container.decodeIfPresent([String: KeyChord].self, forKey: .macShortcutBindings) ?? [:]
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
        try container.encode(shortcutInputOrder, forKey: .shortcutInputOrder)
        try container.encode(macShortcutBindings, forKey: .macShortcutBindings)
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
    var formatVersion: Int = 7
    var exportedAt: Date = .now
    var currency: String = "IDR"
    var minorUnitScale: Int = 2
    var books: [BookBackupItem]
    var preferences: WorkspacePreferences
    var settings: PrototypeSettings
    var cardArtworks: [String: Data]? = nil

    init(formatVersion: Int = 7, exportedAt: Date = .now, currency: String = "IDR", minorUnitScale: Int = 2, books: [BookBackupItem], preferences: WorkspacePreferences = .init(), settings: PrototypeSettings = .init(), cardArtworks: [String: Data]? = nil) {
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

    /// Explicitly migrate older workspace metadata without silently repairing records.
    /// Formats 4–6 allowed sample settings beside real books and missing budget history.
    func normalized() throws -> Self {
        try validate()
        var result = self
        if formatVersion < 7, !books.contains(where: { $0.book == settings.book }) {
            result.settings.book = books.first(where: { $0.book.id == settings.book.id })?.book ?? books[0].book
        }
        result.books = books.map { item in
            var item = item
            item.expenses = item.expenses.map { var value = $0; value.bookID = item.book.id; return value }
            if item.budgets.isEmpty {
                var budget = BudgetVersion.initial(overallLimit: settings.budget, startDay: settings.startDay, date: exportedAt, bookID: item.book.id)
                budget.id = item.book.id // deterministic legacy materialization
                item.budgets = [budget]
            }
            item.budgets = item.budgets.map { var value = $0; value.bookID = item.book.id; return value }
            if item.draft == nil {
                var draft = ExpenseDraft()
                draft.id = item.book.id; draft.date = exportedAt; draft.createdAt = exportedAt
                item.draft = draft
            }
            item.draft?.bookID = item.book.id
            item.bills = item.bills ?? []
            item.billOccurrences = item.billOccurrences ?? []
            return item
        }
        return result
    }

    func validate() throws {
        guard (4...7).contains(formatVersion), currency == "IDR", minorUnitScale == 2 else { throw BackupError.unsupported }
        guard exportedAt.timeIntervalSince1970.isFinite, !books.isEmpty,
              Set(books.map(\.book.id)).count == books.count else { throw BackupError.invalid }
        // The old JSON envelopes retain their historical external-input ceilings.
        // Version 7 separates records and binary assets, so admitted live stores remain recoverable.
        if formatVersion < 7 {
            guard books.count <= 100 else { throw BackupError.tooLarge }
        }
        try preferences.validate(books: books.map(\.book), categoriesByBook: Dictionary(uniqueKeysWithValues: books.map { ($0.book.id, $0.categories) }))
        try settings.validate(books: books, globalCategories: preferences.globalCategories, allowLegacySampleProfile: formatVersion < 7)
        let expenseIDs = books.flatMap { $0.expenses.map(\.id) }
        let billIDs = books.flatMap { ($0.bills ?? []).map(\.id) }
        let occurrenceIDs = books.flatMap { ($0.billOccurrences ?? []).map(\.id) }
        guard Set(expenseIDs).count == expenseIDs.count,
              Set(billIDs).count == billIDs.count,
              Set(occurrenceIDs).count == occurrenceIDs.count else { throw BackupError.invalid }
        var total: Int64 = 0
        for item in books {
            try item.validate(legacyLimits: formatVersion < 7)
            for expense in item.expenses {
                let next = total.addingReportingOverflow(expense.amount)
                guard !next.overflow else { throw BackupError.invalid }
                total = next.partialValue
            }
        }
        let required = Set(preferences.cardCustomizations.values.compactMap { customization -> String? in
            if case .customPhoto(let filename) = customization.style { return filename }
            return nil
        })
        let artworks = cardArtworks ?? [:]
        guard required.isSubset(of: Set(artworks.keys)) else { throw BackupError.missingArtwork }
        for (filename, data) in artworks {
            guard CardArtworkStore.isValidFilename(filename) else { throw BackupError.invalid }
            try CardArtworkStore.validateArtworkData(data)
        }
    }

    /// A canonical graph for comparing a complete materialized preview.
    func canonical() throws -> Self {
        var result = try normalized()
        result.books = result.books.map { item in
            var item = item
            item.categories.sort { $0.id.uuidString < $1.id.uuidString }
            item.expenses = item.expenses.map { value in
                var value = value
                value.allocations.sort { $0.categoryID.uuidString < $1.categoryID.uuidString }
                return value
            }.sorted { $0.id.uuidString < $1.id.uuidString }
            item.budgets = item.budgets.map { value in
                var value = value
                value.categoryLimits.sort { $0.categoryID.uuidString < $1.categoryID.uuidString }
                return value
            }.sorted { $0.id.uuidString < $1.id.uuidString }
            item.bills?.sort { $0.id.uuidString < $1.id.uuidString }
            item.billOccurrences?.sort { $0.id.uuidString < $1.id.uuidString }
            return item
        }.sorted { $0.book.id.uuidString < $1.book.id.uuidString }
        result.cardArtworks = result.cardArtworks ?? [:]
        return result
    }

    func encoded() throws -> Data {
        try validate()
        if formatVersion == 7 { return try WorkspaceBackupStream.encode(self) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        guard data.count <= BookBackup.maximumBytes else { throw BackupError.tooLarge }
        return data
    }

    static func decode(_ data: Data) throws -> WorkspaceBackup {
        if data.starts(with: WorkspaceBackupStream.magic) {
            let workspace = try WorkspaceBackupStream.decode(data)
            try workspace.validate()
            return workspace
        }
        guard data.count <= BookBackup.maximumBytes else { throw BackupError.tooLarge }
        // Decode the envelope before selecting its validator; malformed workspace JSON
        // must not be misinterpreted as a single-book backup with default fields.
        struct Version: Decodable { var formatVersion: Int? }
        let version = try JSONDecoder().decode(Version.self, from: data).formatVersion ?? 1
        if version >= 4 {
            guard version <= 6 else { throw BackupError.unsupported }
            let workspace = try JSONDecoder().decode(Self.self, from: data)
            try workspace.validate()
            return workspace
        }
        let legacy = try BookBackup.decode(data)
        let workspace = WorkspaceBackup(singleBook: legacy)
        try workspace.validate()
        return workspace
    }
}

extension BookBackupItem {
    func validate(legacyLimits: Bool = false) throws {
        try book.validate()
        guard Set(categories.map(\.id)).count == categories.count,
              Set(expenses.map(\.id)).count == expenses.count,
              Set(budgets.map(\.id)).count == budgets.count,
              Set(budgets.map(\.effectiveDay)).count == budgets.count else { throw BackupError.invalid }
        if legacyLimits {
            guard expenses.count <= 10_000, categories.count <= 500,
                  (bills ?? []).count <= 1_000, (billOccurrences ?? []).count <= 10_000 else { throw BackupError.tooLarge }
        }
        for category in categories { guard try category.validated(against: categories) == category else { throw BackupError.invalid } }
        for expense in expenses {
            guard expense.bookID == nil || expense.bookID == book.id,
                  expense.createdAt.timeIntervalSince1970.isFinite else { throw BackupError.invalid }
            try expense.validate(categories: categories)
        }
        for budget in budgets {
            guard budget.bookID == nil || budget.bookID == book.id else { throw BackupError.invalid }
            try budget.validate(categories: categories)
        }
        if let draft {
            let categoryIDs = Set(categories.map(\.id))
            guard draft.bookID == nil || draft.bookID == book.id,
                  draft.date.timeIntervalSince1970.isFinite, draft.createdAt.timeIntervalSince1970.isFinite,
                  draft.categoryID.map(categoryIDs.contains) ?? true,
                  draft.splitAllocations.allSatisfy({ categoryIDs.contains($0.categoryID) }),
                  Set(draft.splitAllocations.map(\.id)).count == draft.splitAllocations.count,
                  !draft.editing || expenses.contains(where: { $0.id == draft.id }) else { throw BackupError.invalid }
        }
        let rules = bills ?? []
        guard Set(rules.map(\.id)).count == rules.count else { throw BackupError.invalid }
        for rule in rules {
            guard rule.bookID == book.id else { throw BackupError.invalid }
            try rule.validate(categories: categories)
        }
        try BillOccurrence.validate(billOccurrences ?? [], rules: rules, expenses: expenses, bookID: book.id)
    }
}

extension PrototypeSettings {
    func validate(books: [BookBackupItem], globalCategories: [GlobalCategory] = [], allowLegacySampleProfile: Bool = false) throws {
        try book.validate()
        let legacyProfile = allowLegacySampleProfile && (book == .sample || books.contains { $0.book.id == book.id && $0.book.kind == book.kind })
        guard budget > 0, budget <= Money.maximum, (1...31).contains(startDay),
              books.contains(where: { $0.book == book }) || legacyProfile,
              Set(categoryRules.map(\.id)).count == categoryRules.count,
              Set(categoryRules.map(\.keyword)).count == categoryRules.count else { throw BackupError.invalid }
        // The archive/rule catalog is workspace-wide; a category may be inactive on
        // the settings profile's card and retained for another card's history.
        let categories = books.flatMap(\.categories) + globalCategories.map { $0.toExpenseCategory() }
        guard archivedCategoryIDs.isSubset(of: Set(categories.map(\.id))) else { throw BackupError.invalid }
        for rule in categoryRules {
            guard try rule.validated(against: categories, archivedIDs: archivedCategoryIDs) == rule else { throw BackupError.invalid }
        }
    }
}

extension WorkspacePreferences {
    func validate(books: [BookProfile], categoriesByBook: [UUID: [ExpenseCategory]]) throws {
        for book in books { try book.validate() }
        let bookIDs = Set(books.map(\.id))
        func validBookList(_ ids: [UUID]) -> Bool { Set(ids).count == ids.count && Set(ids).isSubset(of: bookIDs) }
        guard validBookList(visibleBookIDs), validBookList(bookOrder), validBookList(alwaysHiddenBookIDs),
              BookVisualDirection(rawValue: visualDirection) != nil,
              StackFilterScope(rawValue: filterScopeRaw) != nil, EntryMode(rawValue: entryModeRaw) != nil,
              Set(shortcutInputOrder) == Set(ShortcutInputField.allCases), shortcutInputOrder.count == ShortcutInputField.allCases.count,
              Set(globalCategories.map(\.id)).count == globalCategories.count,
              Set(stacks.map(\.id)).count == stacks.count,
              activeStackID.map({ id in stacks.contains(where: { $0.id == id }) }) ?? true,
              Set(cardCustomizations.keys).isSubset(of: bookIDs),
              Set(cardInactiveCategoryIDs.keys).isSubset(of: bookIDs) else { throw BackupError.invalid }
        for category in globalCategories { guard try category.validated(against: globalCategories) == category else { throw BackupError.invalid } }
        let globalIDs = Set(globalCategories.map(\.id))
        for (bookID, ids) in cardInactiveCategoryIDs {
            let validIDs = globalIDs.union((categoriesByBook[bookID] ?? []).map(\.id))
            guard Set(ids).count == ids.count, Set(ids).isSubset(of: validIDs) else { throw BackupError.invalid }
        }
        for stack in stacks {
            guard validBookList(stack.cardIDs), !stack.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  stack.name.count <= 40, stack.name.rangeOfCharacter(from: .controlCharacters) == nil,
                  !stack.icon.isEmpty, stack.icon.count <= 100, stack.icon.rangeOfCharacter(from: .controlCharacters) == nil else { throw BackupError.invalid }
        }
        for customization in cardCustomizations.values {
            switch customization.style {
            case .palette(let index):
                guard (0..<CardPalette.standard.count).contains(index) else { throw BackupError.invalid }
            case .customColor(let hex):
                guard hex.range(of: "^#?[0-9A-Fa-f]{6}$", options: .regularExpression) != nil else { throw BackupError.invalid }
            case .customPhoto(let filename):
                guard CardArtworkStore.isValidFilename(filename) else { throw BackupError.invalid }
            case .stock: break
            }
        }
    }
}

/// Version 7 is a length-framed record stream, with raw binary asset frames.
/// Encoding a large ledger never creates a second base64-expanded asset graph;
/// each record/asset is decoded separately and all frame lengths are checked
/// against the remaining input before allocation. There is no overall live-data ceiling.
private enum WorkspaceBackupStream {
    static let magic = Data("MONOCLE-BACKUP-7\n".utf8)
    private struct Header: Codable {
        var exportedAt: Date
        var currency: String
        var minorUnitScale: Int
        var settings: PrototypeSettings
        var preferences: WorkspacePreferences
        var bookCount: Int
        var assetCount: Int
    }
    private struct BookHeader: Codable {
        var book: BookProfile
        var draft: ExpenseDraft?
        var categories: Int
        var expenses: Int
        var budgets: Int
        var bills: Int?
        var occurrences: Int?
    }
    static func encode(_ workspace: WorkspaceBackup) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var data = magic
        func append(_ frame: Data) {
            var length = UInt64(frame.count).bigEndian
            withUnsafeBytes(of: &length) { data.append(contentsOf: $0) }
            data.append(frame)
        }
        func appendJSON<T: Encodable>(_ value: T) throws { append(try encoder.encode(value)) }
        try appendJSON(Header(exportedAt: workspace.exportedAt, currency: workspace.currency, minorUnitScale: workspace.minorUnitScale,
                              settings: workspace.settings, preferences: workspace.preferences, bookCount: workspace.books.count,
                              assetCount: workspace.cardArtworks?.count ?? 0))
        for item in workspace.books {
            try appendJSON(BookHeader(book: item.book, draft: item.draft, categories: item.categories.count, expenses: item.expenses.count,
                                      budgets: item.budgets.count, bills: item.bills?.count, occurrences: item.billOccurrences?.count))
            for value in item.categories { try appendJSON(value) }
            for value in item.expenses { try appendJSON(value) }
            for value in item.budgets { try appendJSON(value) }
            for value in item.bills ?? [] { try appendJSON(value) }
            for value in item.billOccurrences ?? [] { try appendJSON(value) }
        }
        for filename in (workspace.cardArtworks ?? [:]).keys.sorted() {
            try appendJSON(filename)
            append(workspace.cardArtworks![filename]!)
        }
        return data
    }
    static func decode(_ data: Data) throws -> WorkspaceBackup {
        let decoder = JSONDecoder()
        var offset = magic.count
        func frame() throws -> Data {
            guard data.count - offset >= 8 else { throw BackupError.invalid }
            let length = data[offset..<(offset + 8)].reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
            offset += 8
            guard length <= UInt64(data.count - offset) else { throw BackupError.invalid }
            let end = offset + Int(length)
            defer { offset = end }
            return data.subdata(in: offset..<end)
        }
        func read<T: Decodable>(_ type: T.Type) throws -> T { try decoder.decode(type, from: frame()) }
        func records<T: Decodable>(_ count: Int, _ type: T.Type) throws -> [T] {
            guard count >= 0, count <= (data.count - offset) / 8 else { throw BackupError.invalid }
            var values: [T] = []
            for _ in 0..<count { values.append(try read(type)) }
            return values
        }
        let header = try read(Header.self)
        guard header.bookCount > 0, header.bookCount <= (data.count - offset) / 8,
              header.assetCount >= 0, header.assetCount <= (data.count - offset) / 16 else { throw BackupError.invalid }
        var books: [BookBackupItem] = []
        for _ in 0..<header.bookCount {
            let book = try read(BookHeader.self)
            let categories = try records(book.categories, ExpenseCategory.self)
            let expenses = try records(book.expenses, Expense.self)
            let budgets = try records(book.budgets, BudgetVersion.self)
            let bills = try book.bills.map { try records($0, BillRule.self) }
            let occurrences = try book.occurrences.map { try records($0, BillOccurrence.self) }
            books.append(BookBackupItem(book: book.book, categories: categories, expenses: expenses, budgets: budgets, draft: book.draft, bills: bills, billOccurrences: occurrences))
        }
        var assets: [String: Data] = [:]
        for _ in 0..<header.assetCount {
            let filename = try read(String.self)
            guard CardArtworkStore.isValidFilename(filename), assets[filename] == nil else { throw BackupError.invalid }
            let bytes = try frame()
            try CardArtworkStore.validateArtworkData(bytes)
            assets[filename] = bytes
        }
        guard offset == data.count else { throw BackupError.invalid }
        return WorkspaceBackup(formatVersion: 7, exportedAt: header.exportedAt, currency: header.currency, minorUnitScale: header.minorUnitScale,
                               books: books, preferences: header.preferences, settings: header.settings, cardArtworks: assets.isEmpty ? nil : assets)
    }
}

enum BackupError: LocalizedError {
    case unsupported, invalid, tooLarge, recoveryRequired, missingArtwork
    var errorDescription: String? {
        switch self {
        case .unsupported: "This backup version is not supported by this version of Monocle."
        case .invalid: "The backup contains invalid or inconsistent records. Your current workspace has not been replaced."
        case .tooLarge: "This legacy backup exceeds its supported size. Export a current workspace backup to preserve all records and artwork."
        case .recoveryRequired: "Restoration could not finish or roll back. Restart monocle to recover from the retained safety backup. Your original data has been kept."
        case .missingArtwork: "A card photo is missing or unreadable. Restore the photo before exporting or replacing this workspace."
        }
    }
}
