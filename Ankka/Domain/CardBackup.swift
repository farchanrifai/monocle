import Foundation

enum CardKind: String, Codable, Equatable { case demo = "sample", real }

struct Card: Identifiable, Codable, Equatable, Hashable, Sendable {
    var id: UUID
    var name: String
    var kind: CardKind
    var colorIndex: Int
    /// Budget and totals currency; nil means the workspace reporting currency.
    var currency: String? = nil
    /// Pre-filled on new expenses and shown as the secondary amount.
    var spendingCurrency: String? = nil
    var defaultPaidWithID: UUID? = nil

    static let demo = Self(id: UUID(uuidString: "20000000-0000-0000-0000-000000000001")!, name: "Sample card", kind: .demo, colorIndex: 0)

    init(id: UUID = UUID(), name: String, kind: CardKind = .real, colorIndex: Int = 0,
         currency: String? = nil, spendingCurrency: String? = nil, defaultPaidWithID: UUID? = nil) {
        self.id = id
        self.name = name
        self.kind = kind
        self.colorIndex = colorIndex
        self.currency = currency
        self.spendingCurrency = spendingCurrency
        self.defaultPaidWithID = defaultPaidWithID
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
              (kind == .demo) == (id == Card.demo.id),
              currency.map(Money.isCurrencyCode) ?? true,
              spendingCurrency.map(Money.isCurrencyCode) ?? true else { throw BackupError.invalid }
    }

    func renamed(to name: String) throws -> Self {
        guard kind == .real else { throw BackupError.invalid }
        var value = self
        value.name = try Self.real(named: name, colorIndex: colorIndex).name
        return value
    }

    private enum CodingKeys: String, CodingKey { case id, name, kind, colorIndex, currency, spendingCurrency, defaultPaidWithID }
    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        kind = try values.decode(CardKind.self, forKey: .kind)
        colorIndex = try values.decodeIfPresent(Int.self, forKey: .colorIndex) ?? 0
        currency = try values.decodeIfPresent(String.self, forKey: .currency)
        spendingCurrency = try values.decodeIfPresent(String.self, forKey: .spendingCurrency)
        defaultPaidWithID = try values.decodeIfPresent(UUID.self, forKey: .defaultPaidWithID)
    }
    func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(name, forKey: .name)
        try values.encode(kind, forKey: .kind)
        try values.encode(colorIndex, forKey: .colorIndex)
        try values.encodeIfPresent(currency, forKey: .currency)
        try values.encodeIfPresent(spendingCurrency, forKey: .spendingCurrency)
        try values.encodeIfPresent(defaultPaidWithID, forKey: .defaultPaidWithID)
    }
}


struct CardBackup: Codable {
    var formatVersion = 3
    var exportedAt = Date.now
    var cardID = Card.demo.id
    var cardName = Card.demo.name
    var cardKind = CardKind.demo.rawValue
    var currency = "IDR"
    var minorUnitScale = 2
    var sampleSeeded = true
    var categories: [ExpenseCategory]
    var expenses: [Expense]
    var draft: ExpenseDraft
    var settings: PrototypeSettings
    var budgets: [BudgetVersion]

    init(formatVersion: Int = 3, exportedAt: Date = .now, cardID: UUID = Card.demo.id,
         cardName: String = Card.demo.name, cardKind: String = CardKind.demo.rawValue,
         currency: String = "IDR", minorUnitScale: Int = 2, sampleSeeded: Bool = true,
         categories: [ExpenseCategory], expenses: [Expense], draft: ExpenseDraft,
         settings: PrototypeSettings, budgets: [BudgetVersion]? = nil) {
        self.formatVersion = formatVersion; self.exportedAt = exportedAt; self.cardID = cardID
        self.cardName = cardName; self.cardKind = cardKind; self.currency = currency
        self.minorUnitScale = minorUnitScale; self.sampleSeeded = sampleSeeded
        self.categories = categories; self.expenses = expenses; self.draft = draft; self.settings = settings
        self.budgets = budgets ?? [BudgetVersion.initial(overallLimit: settings.budget, startDay: settings.startDay, date: exportedAt)]
    }

    private enum CodingKeys: String, CodingKey {
        case formatVersion, exportedAt, cardID = "bookID", cardName = "bookName", cardKind = "bookKind", currency, minorUnitScale, sampleSeeded
        case categories, expenses, draft, settings, budgets
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = try values.decodeIfPresent(Int.self, forKey: .formatVersion) ?? 1
        exportedAt = try values.decodeIfPresent(Date.self, forKey: .exportedAt) ?? .now
        cardID = try values.decodeIfPresent(UUID.self, forKey: .cardID) ?? Card.demo.id
        cardName = try values.decodeIfPresent(String.self, forKey: .cardName) ?? Card.demo.name
        cardKind = try values.decodeIfPresent(String.self, forKey: .cardKind) ?? CardKind.demo.rawValue
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
        try values.encode(cardID, forKey: .cardID); try values.encode(cardName, forKey: .cardName)
        try values.encode(cardKind, forKey: .cardKind); try values.encode(currency, forKey: .currency)
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
            guard cardKind == CardKind.demo.rawValue, cardID == Card.demo.id,
                  cardName == Card.demo.name, sampleSeeded else { throw BackupError.unsupported }
        } else {
            guard let kind = CardKind(rawValue: cardKind), !cardName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  cardName.count <= 40, settings.card == .init(id: cardID, name: cardName, kind: kind),
                  (kind == .demo) == sampleSeeded else { throw BackupError.invalid }
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
            guard expense.cardID == nil || expense.cardID == cardID,
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
                guard budget.cardID == nil || budget.cardID == cardID else { throw BackupError.invalid }
                try budget.validate(categories: categories)
            }
        }
        if let id = draft.categoryID { guard categories.contains(where: { $0.id == id }) else { throw BackupError.invalid } }
        guard draft.cardID == nil || draft.cardID == cardID,
              draft.date.timeIntervalSince1970.isFinite, draft.createdAt.timeIntervalSince1970.isFinite,
              draft.splitParts.allSatisfy({ split in categories.contains(where: { $0.id == split.categoryID }) }),
              Set(draft.splitParts.map(\.id)).count == draft.splitParts.count,
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

enum CardVisualDirection: String, CaseIterable, Identifiable, Codable, Sendable {
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

struct Stack: Identifiable, Codable, Equatable, Hashable, Sendable {
    var id: UUID = UUID()
    var name: String
    var icon: String = "rectangle.stack"
    var cardIDs: [UUID] = []
    /// Optional overall cap in reporting-currency minor units; without it the stack budget is the sum of its cards.
    var capLimit: Int64? = nil
    var capStartDay: Int? = nil

    init(id: UUID = UUID(), name: String, icon: String = "rectangle.stack", cardIDs: [UUID] = [], capLimit: Int64? = nil, capStartDay: Int? = nil) {
        self.id = id
        self.name = name
        self.icon = icon
        self.cardIDs = cardIDs
        self.capLimit = capLimit
        self.capStartDay = capStartDay
    }
}

extension Stack {
    /// The stack budget for a calendar-month cycle: its cap when set, otherwise the sum of its cards' monthly budgets.
    func budgetLimit(cardLimits: [Int64]) -> Int64? {
        if let capLimit { return capLimit }
        guard let sum = try? Money.checkedSum(cardLimits), sum > 0 else { return nil }
        return min(sum, Money.maximum)
    }
}

extension WorkspacePreferences {
    /// A card belongs to at most one stack. Keeps it in `preferred` when that stack holds it, otherwise in the
    /// first stack (in stack order) that does; returns how many duplicate placements were removed.
    @discardableResult
    mutating func keepEachCardInOneStack(preferring preferred: UUID? = nil) -> Int {
        var owner: [UUID: UUID] = [:]
        if let preferred, let stack = stacks.first(where: { $0.id == preferred }) {
            for id in stack.cardIDs { owner[id] = preferred }
        }
        for stack in stacks { for id in stack.cardIDs where owner[id] == nil { owner[id] = stack.id } }
        var removed = 0
        for index in stacks.indices {
            var seen = Set<UUID>()
            let kept = stacks[index].cardIDs.filter { owner[$0] == stacks[index].id && seen.insert($0).inserted }
            removed += stacks[index].cardIDs.count - kept.count
            stacks[index].cardIDs = kept
        }
        return removed
    }

    func stack(containing cardID: UUID) -> Stack? { stacks.first { $0.cardIDs.contains(cardID) } }
}

/// "Paid with": an optional label such as BCA debit or Cash. Never a balance.
struct PaymentMethod: Identifiable, Codable, Equatable, Hashable, Sendable {
    enum Kind: String, Codable, CaseIterable, Sendable { case bank, card, cash, eWallet }
    var id: UUID = UUID()
    var name: String
    var kind: Kind = .bank
}

extension PaymentMethod.Kind {
    var title: String {
        switch self {
        case .bank: "Bank account"
        case .card: "Card"
        case .cash: "Cash"
        case .eWallet: "E-wallet"
        }
    }
    var symbol: String {
        switch self {
        case .bank: "building.columns"
        case .card: "creditcard"
        case .cash: "banknote"
        case .eWallet: "iphone"
        }
    }
}

extension EntryFormField {
    var title: String {
        switch self {
        case .date: "Date"
        case .note: "Note"
        case .split: "Split across categories"
        case .paidWith: "Paid with"
        case .currency: "Currency"
        }
    }
}

enum PaymentMethodError: LocalizedError, Equatable {
    case invalidName, duplicateName, inUse(Int)
    var errorDescription: String? {
        switch self {
        case .invalidName: "Enter a name of up to 40 characters."
        case .duplicateName: "A Paid with label with this name already exists."
        case .inUse(let count): "\(count) \(count == 1 ? "expense uses" : "expenses use") this label, so it can't be deleted. Rename it instead."
        }
    }
}

/// Add Expense fields the user can hide. Amount, Card and Category are always shown.
enum EntryFormField: String, Codable, CaseIterable, Hashable, Sendable {
    case date, note, split, paidWith, currency
    static let hiddenByDefault: [EntryFormField] = [.paidWith, .currency]
}

/// The lines of the Add Expense details group, in the order the user chose. Category and Card are always shown.
enum EntryFormRow: String, Codable, CaseIterable, Hashable, Sendable {
    case category, card, paidWith, note, date
    var title: String {
        switch self {
        case .category: "Category"
        case .card: "Card"
        case .paidWith: "Paid with"
        case .note: "Note"
        case .date: "Date"
        }
    }
    /// The hide/show switch for this line, nil when it is always shown.
    var field: EntryFormField? {
        switch self {
        case .paidWith: .paidWith
        case .note: .note
        case .date: .date
        case .category, .card: nil
        }
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
        case .amount: return "Amount"
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
    var visibleCardIDs: [UUID] = []
    var cardOrder: [UUID] = []
    var allActivitiesScope: Bool = false
    var visualDirection: String = "Light"
    var autoAppearance: Bool = false
    var cardCustomizations: [UUID: CardCustomization] = [:]
    var alwaysHiddenCardIDs: [UUID] = []
    var stacks: [Stack] = []
    var activeStackID: UUID? = nil
    var filterScopeRaw: String = "activeStack"
    var globalCategories: [GlobalCategory] = []
    var cardInactiveCategoryIDs: [UUID: [UUID]] = [:]
    var shortcutInputOrder: [ShortcutInputField] = [.card, .category, .note, .amount]
    var macShortcutBindings: [String: KeyChord] = [:]
    var paymentMethods: [PaymentMethod] = []
    var hiddenEntryFields: [EntryFormField] = EntryFormField.hiddenByDefault
    var reportingCurrency: String = "IDR"
    var entryRowOrder: [EntryFormRow] = [] // empty = the default order; only written once the user reorders

    var direction: CardVisualDirection {
        get { CardVisualDirection(rawValue: visualDirection) ?? .light }
        set { visualDirection = newValue.rawValue }
    }

    var filterScope: StackFilterScope {
        get { StackFilterScope(rawValue: filterScopeRaw) ?? .activeStack }
        set { filterScopeRaw = newValue.rawValue }
    }

    private enum CodingKeys: String, CodingKey {
        case visibleCardIDs = "visibleBookIDs", cardOrder = "bookOrder", allActivitiesScope, visualDirection, autoAppearance, cardCustomizations
        case alwaysHiddenCardIDs = "alwaysHiddenBookIDs", stacks, activeStackID, filterScopeRaw, globalCategories, cardInactiveCategoryIDs
        case shortcutInputOrder, macShortcutBindings, paymentMethods, hiddenEntryFields, reportingCurrency, entryRowOrder
    }

    init(
        visibleCardIDs: [UUID] = [],
        cardOrder: [UUID] = [],
        allActivitiesScope: Bool = false,
        visualDirection: String = "Light",
        autoAppearance: Bool = false,
        cardCustomizations: [UUID: CardCustomization] = [:],
        alwaysHiddenCardIDs: [UUID] = [],
        stacks: [Stack] = [],
        activeStackID: UUID? = nil,
        filterScope: StackFilterScope = .activeStack,
        globalCategories: [GlobalCategory] = [],
        cardInactiveCategoryIDs: [UUID: [UUID]] = [:],
        shortcutInputOrder: [ShortcutInputField] = [.card, .category, .note, .amount],
        macShortcutBindings: [String: KeyChord] = [:],
        paymentMethods: [PaymentMethod] = [],
        hiddenEntryFields: [EntryFormField] = EntryFormField.hiddenByDefault,
        reportingCurrency: String = "IDR",
        entryRowOrder: [EntryFormRow] = []
    ) {
        self.visibleCardIDs = visibleCardIDs
        self.cardOrder = cardOrder
        self.allActivitiesScope = allActivitiesScope
        self.visualDirection = visualDirection
        self.autoAppearance = autoAppearance
        self.cardCustomizations = cardCustomizations
        self.alwaysHiddenCardIDs = alwaysHiddenCardIDs
        self.stacks = stacks
        self.activeStackID = activeStackID
        self.filterScopeRaw = filterScope.rawValue
        self.globalCategories = globalCategories
        self.cardInactiveCategoryIDs = cardInactiveCategoryIDs
        self.shortcutInputOrder = shortcutInputOrder
        self.macShortcutBindings = macShortcutBindings
        self.paymentMethods = paymentMethods
        self.hiddenEntryFields = hiddenEntryFields
        self.reportingCurrency = reportingCurrency
        self.entryRowOrder = entryRowOrder
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        visibleCardIDs = try container.decodeIfPresent([UUID].self, forKey: .visibleCardIDs) ?? []
        cardOrder = try container.decodeIfPresent([UUID].self, forKey: .cardOrder) ?? []
        allActivitiesScope = try container.decodeIfPresent(Bool.self, forKey: .allActivitiesScope) ?? false
        visualDirection = try container.decodeIfPresent(String.self, forKey: .visualDirection) ?? "Light"
        autoAppearance = try container.decodeIfPresent(Bool.self, forKey: .autoAppearance) ?? false
        cardCustomizations = try container.decodeIfPresent([UUID: CardCustomization].self, forKey: .cardCustomizations) ?? [:]
        alwaysHiddenCardIDs = try container.decodeIfPresent([UUID].self, forKey: .alwaysHiddenCardIDs) ?? []
        stacks = try container.decodeIfPresent([Stack].self, forKey: .stacks) ?? []
        activeStackID = try container.decodeIfPresent(UUID.self, forKey: .activeStackID)
        filterScopeRaw = try container.decodeIfPresent(String.self, forKey: .filterScopeRaw) ?? "activeStack"
        globalCategories = try container.decodeIfPresent([GlobalCategory].self, forKey: .globalCategories) ?? []
        cardInactiveCategoryIDs = try container.decodeIfPresent([UUID: [UUID]].self, forKey: .cardInactiveCategoryIDs) ?? [:]
        let decodedOrder = try container.decodeIfPresent([ShortcutInputField].self, forKey: .shortcutInputOrder) ?? [.card, .category, .note, .amount]
        self.shortcutInputOrder = decodedOrder
        macShortcutBindings = try container.decodeIfPresent([String: KeyChord].self, forKey: .macShortcutBindings) ?? [:]
        paymentMethods = try container.decodeIfPresent([PaymentMethod].self, forKey: .paymentMethods) ?? []
        // Decoded as strings so a stored "quick" (the removed text field) is skipped instead of failing the decode.
        hiddenEntryFields = try container.decodeIfPresent([String].self, forKey: .hiddenEntryFields)?.compactMap(EntryFormField.init(rawValue:)) ?? EntryFormField.hiddenByDefault
        reportingCurrency = try container.decodeIfPresent(String.self, forKey: .reportingCurrency) ?? "IDR"
        entryRowOrder = try container.decodeIfPresent([EntryFormRow].self, forKey: .entryRowOrder) ?? []
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(visibleCardIDs, forKey: .visibleCardIDs)
        try container.encode(cardOrder, forKey: .cardOrder)
        try container.encode(allActivitiesScope, forKey: .allActivitiesScope)
        try container.encode(visualDirection, forKey: .visualDirection)
        try container.encode(autoAppearance, forKey: .autoAppearance)
        try container.encode(cardCustomizations, forKey: .cardCustomizations)
        try container.encode(alwaysHiddenCardIDs, forKey: .alwaysHiddenCardIDs)
        try container.encode(stacks, forKey: .stacks)
        try container.encodeIfPresent(activeStackID, forKey: .activeStackID)
        try container.encode(filterScopeRaw, forKey: .filterScopeRaw)
        try container.encode(globalCategories, forKey: .globalCategories)
        try container.encode(cardInactiveCategoryIDs, forKey: .cardInactiveCategoryIDs)
        try container.encode(shortcutInputOrder, forKey: .shortcutInputOrder)
        try container.encode(macShortcutBindings, forKey: .macShortcutBindings)
        try container.encode(paymentMethods, forKey: .paymentMethods)
        try container.encode(hiddenEntryFields, forKey: .hiddenEntryFields)
        try container.encode(reportingCurrency, forKey: .reportingCurrency)
        if !entryRowOrder.isEmpty { try container.encode(entryRowOrder, forKey: .entryRowOrder) }
    }
}

struct CardBackupItem: Codable, Equatable, Sendable {
    var card: Card
    var categories: [ExpenseCategory]
    var expenses: [Expense]
    var budgets: [BudgetVersion]
    var draft: ExpenseDraft?
    var bills: [Bill]?
    var billOccurrences: [BillOccurrence]?
    // Stored keys keep their pre-rename names so existing backups, drafts and settings still load.
    private enum CodingKeys: String, CodingKey { case card = "book", categories, expenses, budgets, draft, bills, billOccurrences }
}

struct WorkspaceBackup: Codable, Equatable, Sendable {
    static let currentFormat = 8
    var formatVersion: Int = currentFormat
    var exportedAt: Date = .now
    var currency: String = "IDR"
    var minorUnitScale: Int = 2
    var cards: [CardBackupItem]
    var preferences: WorkspacePreferences
    var settings: PrototypeSettings
    var cardArtworks: [String: Data]? = nil
    // Stored keys keep their pre-rename names so existing backups, drafts and settings still load.
    private enum CodingKeys: String, CodingKey {
        case formatVersion, exportedAt, currency, minorUnitScale, cards = "books", preferences, settings, cardArtworks
    }

    init(formatVersion: Int = currentFormat, exportedAt: Date = .now, currency: String = "IDR", minorUnitScale: Int = 2, cards: [CardBackupItem], preferences: WorkspacePreferences = .init(), settings: PrototypeSettings = .init(), cardArtworks: [String: Data]? = nil) {
        self.formatVersion = formatVersion
        self.exportedAt = exportedAt
        self.currency = currency
        self.minorUnitScale = minorUnitScale
        self.cards = cards
        self.preferences = preferences
        self.settings = settings
        self.cardArtworks = cardArtworks
    }

    /// Convert a single-card CardBackup (formats 1–3) into a WorkspaceBackup
    init(singleCard backup: CardBackup) {
        let kind = CardKind(rawValue: backup.cardKind) ?? (backup.cardID == Card.demo.id ? .demo : .real)
        let profile = Card(id: backup.cardID, name: backup.cardName, kind: kind)
        let item = CardBackupItem(card: profile, categories: backup.categories, expenses: backup.expenses, budgets: backup.budgets, draft: backup.draft, bills: nil, billOccurrences: nil)
        self.init(
            formatVersion: 6,
            exportedAt: backup.exportedAt,
            currency: backup.currency,
            minorUnitScale: backup.minorUnitScale,
            cards: [item],
            preferences: WorkspacePreferences(visibleCardIDs: [profile.id], cardOrder: [profile.id]),
            settings: backup.settings
        )
    }

    /// Explicitly migrate older workspace metadata without silently repairing records.
    /// Formats 4–6 allowed sample settings beside real cards and missing budget history.
    func normalized() throws -> Self {
        try validate()
        var result = self
        if formatVersion < 7, !cards.contains(where: { $0.card == settings.card }) {
            result.settings.card = cards.first(where: { $0.card.id == settings.card.id })?.card ?? cards[0].card
        }
        result.cards = cards.map { item in
            var item = item
            item.expenses = item.expenses.map { var value = $0; value.cardID = item.card.id; return value }
            if item.budgets.isEmpty {
                var budget = BudgetVersion.initial(overallLimit: settings.budget, startDay: settings.startDay, date: exportedAt, cardID: item.card.id)
                budget.id = item.card.id // deterministic legacy materialization
                item.budgets = [budget]
            }
            item.budgets = item.budgets.map { var value = $0; value.cardID = item.card.id; return value }
            if item.draft == nil {
                var draft = ExpenseDraft()
                draft.id = item.card.id; draft.date = exportedAt; draft.createdAt = exportedAt
                item.draft = draft
            }
            item.draft?.cardID = item.card.id
            item.bills = item.bills ?? []
            item.billOccurrences = item.billOccurrences ?? []
            return item
        }
        return result
    }

    func validate() throws {
        // Format 8 names the workspace reporting currency; older formats are rupiah only.
        let expectedCurrency = formatVersion >= 8 ? preferences.reportingCurrency : "IDR"
        guard (4...Self.currentFormat).contains(formatVersion), currency == expectedCurrency, minorUnitScale == 2 else { throw BackupError.unsupported }
        guard exportedAt.timeIntervalSince1970.isFinite, !cards.isEmpty,
              Set(cards.map(\.card.id)).count == cards.count else { throw BackupError.invalid }
        // The old JSON envelopes retain their historical external-input ceilings.
        // Version 7 separates records and binary assets, so admitted live stores remain recoverable.
        if formatVersion < 7 {
            guard cards.count <= 100 else { throw BackupError.tooLarge }
        }
        try preferences.validate(cards: cards.map(\.card), categoriesByCard: Dictionary(uniqueKeysWithValues: cards.map { ($0.card.id, $0.categories) }))
        try settings.validate(cards: cards, globalCategories: preferences.globalCategories, allowLegacySampleProfile: formatVersion < 7)
        let expenseIDs = cards.flatMap { $0.expenses.map(\.id) }
        let billIDs = cards.flatMap { ($0.bills ?? []).map(\.id) }
        let occurrenceIDs = cards.flatMap { ($0.billOccurrences ?? []).map(\.id) }
        guard Set(expenseIDs).count == expenseIDs.count,
              Set(billIDs).count == billIDs.count,
              Set(occurrenceIDs).count == occurrenceIDs.count else { throw BackupError.invalid }
        var total: Int64 = 0
        let paymentMethodIDs = Set(preferences.paymentMethods.map(\.id))
        for item in cards {
            try item.validate(legacyLimits: formatVersion < 7)
            for expense in item.expenses {
                guard expense.paidWithID.map(paymentMethodIDs.contains) ?? true else { throw BackupError.invalid }
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
        result.cards = result.cards.map { item in
            var item = item
            item.categories.sort { $0.id.uuidString < $1.id.uuidString }
            item.expenses = item.expenses.map { value in
                var value = value
                value.splits.sort { $0.categoryID.uuidString < $1.categoryID.uuidString }
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
        }.sorted { $0.card.id.uuidString < $1.card.id.uuidString }
        result.cardArtworks = result.cardArtworks ?? [:]
        return result
    }

    func encoded() throws -> Data {
        try validate()
        if formatVersion >= 7 { return try WorkspaceBackupStream.encode(self) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        guard data.count <= CardBackup.maximumBytes else { throw BackupError.tooLarge }
        return data
    }

    static func decode(_ data: Data) throws -> WorkspaceBackup {
        if WorkspaceBackupStream.version(of: data) != nil {
            let workspace = try WorkspaceBackupStream.decode(data)
            try workspace.validate()
            return workspace
        }
        guard data.count <= CardBackup.maximumBytes else { throw BackupError.tooLarge }
        // Decode the envelope before selecting its validator; malformed workspace JSON
        // must not be misinterpreted as a single-card backup with default fields.
        struct Version: Decodable { var formatVersion: Int? }
        let version = try JSONDecoder().decode(Version.self, from: data).formatVersion ?? 1
        if version >= 4 {
            guard version <= 6 else { throw BackupError.unsupported }
            let workspace = try JSONDecoder().decode(Self.self, from: data)
            try workspace.validate()
            return workspace
        }
        let legacy = try CardBackup.decode(data)
        let workspace = WorkspaceBackup(singleCard: legacy)
        try workspace.validate()
        return workspace
    }
}

extension CardBackupItem {
    func validate(legacyLimits: Bool = false) throws {
        try card.validate()
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
            guard expense.cardID == nil || expense.cardID == card.id,
                  expense.createdAt.timeIntervalSince1970.isFinite else { throw BackupError.invalid }
            try expense.validate(categories: categories)
        }
        for budget in budgets {
            guard budget.cardID == nil || budget.cardID == card.id else { throw BackupError.invalid }
            try budget.validate(categories: categories)
        }
        if let draft {
            let categoryIDs = Set(categories.map(\.id))
            guard draft.cardID == nil || draft.cardID == card.id,
                  draft.date.timeIntervalSince1970.isFinite, draft.createdAt.timeIntervalSince1970.isFinite,
                  draft.categoryID.map(categoryIDs.contains) ?? true,
                  draft.splitParts.allSatisfy({ categoryIDs.contains($0.categoryID) }),
                  Set(draft.splitParts.map(\.id)).count == draft.splitParts.count,
                  !draft.editing || expenses.contains(where: { $0.id == draft.id }) else { throw BackupError.invalid }
        }
        let rules = bills ?? []
        guard Set(rules.map(\.id)).count == rules.count else { throw BackupError.invalid }
        for rule in rules {
            guard rule.cardID == card.id else { throw BackupError.invalid }
            try rule.validate(categories: categories)
        }
        try BillOccurrence.validate(billOccurrences ?? [], rules: rules, expenses: expenses, cardID: card.id)
    }
}

extension PrototypeSettings {
    func validate(cards: [CardBackupItem], globalCategories: [GlobalCategory] = [], allowLegacySampleProfile: Bool = false) throws {
        try card.validate()
        let legacyProfile = allowLegacySampleProfile && (card == .demo || cards.contains { $0.card.id == card.id && $0.card.kind == card.kind })
        guard budget > 0, budget <= Money.maximum, (1...31).contains(startDay),
              cards.contains(where: { $0.card == card }) || legacyProfile,
              Set(categoryRules.map(\.id)).count == categoryRules.count,
              Set(categoryRules.map(\.keyword)).count == categoryRules.count else { throw BackupError.invalid }
        // The archive/rule catalog is workspace-wide; a category may be inactive on
        // the settings profile's card and retained for another card's history.
        let categories = cards.flatMap(\.categories) + globalCategories.map { $0.toExpenseCategory() }
        guard archivedCategoryIDs.isSubset(of: Set(categories.map(\.id))) else { throw BackupError.invalid }
        for rule in categoryRules {
            guard try rule.validated(against: categories, archivedIDs: archivedCategoryIDs) == rule else { throw BackupError.invalid }
        }
    }
}

extension WorkspacePreferences {
    func validate(cards: [Card], categoriesByCard: [UUID: [ExpenseCategory]]) throws {
        for card in cards { try card.validate() }
        let cardIDs = Set(cards.map(\.id))
        func validCardList(_ ids: [UUID]) -> Bool { Set(ids).count == ids.count && Set(ids).isSubset(of: cardIDs) }
        guard validCardList(visibleCardIDs), validCardList(cardOrder), validCardList(alwaysHiddenCardIDs),
              CardVisualDirection(rawValue: visualDirection) != nil,
              StackFilterScope(rawValue: filterScopeRaw) != nil,
              Set(shortcutInputOrder) == Set(ShortcutInputField.allCases), shortcutInputOrder.count == ShortcutInputField.allCases.count,
              Set(globalCategories.map(\.id)).count == globalCategories.count,
              Set(stacks.map(\.id)).count == stacks.count,
              activeStackID.map({ id in stacks.contains(where: { $0.id == id }) }) ?? true,
              Set(cardCustomizations.keys).isSubset(of: cardIDs),
              Set(cardInactiveCategoryIDs.keys).isSubset(of: cardIDs),
              Money.isCurrencyCode(reportingCurrency),
              Set(hiddenEntryFields).count == hiddenEntryFields.count,
              Set(paymentMethods.map(\.id)).count == paymentMethods.count,
              cards.allSatisfy({ card in card.defaultPaidWithID.map { id in paymentMethods.contains { $0.id == id } } ?? true })
        else { throw BackupError.invalid }
        for method in paymentMethods {
            let name = method.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, method.name.count <= 40, method.name.rangeOfCharacter(from: .controlCharacters) == nil else { throw BackupError.invalid }
        }
        for category in globalCategories { guard try category.validated(against: globalCategories) == category else { throw BackupError.invalid } }
        let globalIDs = Set(globalCategories.map(\.id))
        for (cardID, ids) in cardInactiveCategoryIDs {
            let validIDs = globalIDs.union((categoriesByCard[cardID] ?? []).map(\.id))
            guard Set(ids).count == ids.count, Set(ids).isSubset(of: validIDs) else { throw BackupError.invalid }
        }
        for stack in stacks {
            guard validCardList(stack.cardIDs), !stack.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  stack.name.count <= 40, stack.name.rangeOfCharacter(from: .controlCharacters) == nil,
                  !stack.icon.isEmpty, stack.icon.count <= 100, stack.icon.rangeOfCharacter(from: .controlCharacters) == nil,
                  stack.capLimit.map({ (1...Money.maximum).contains($0) }) ?? true,
                  stack.capStartDay.map({ (1...31).contains($0) }) ?? true else { throw BackupError.invalid }
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

/// Versions 7 and 8 are a length-framed record stream, with raw binary asset frames.
/// Version 8 adds optional card, expense, budget and preference fields; an older app rejects it instead of dropping them.
/// Encoding a large ledger never creates a second base64-expanded asset graph;
/// each record/asset is decoded separately and all frame lengths are checked
/// against the remaining input before split. There is no overall live-data ceiling.
private enum WorkspaceBackupStream {
    static func magic(_ version: Int) -> Data { Data("MONOCLE-BACKUP-\(version)\n".utf8) }
    static func version(of data: Data) -> Int? { [8, 7].first { data.starts(with: magic($0)) } }
    private struct Header: Codable {
        var exportedAt: Date
        var currency: String
        var minorUnitScale: Int
        var settings: PrototypeSettings
        var preferences: WorkspacePreferences
        var cardCount: Int
        var assetCount: Int
        private enum CodingKeys: String, CodingKey { case exportedAt, currency, minorUnitScale, settings, preferences, cardCount = "bookCount", assetCount }
    }
    private struct CardHeader: Codable {
        var card: Card
        var draft: ExpenseDraft?
        var categories: Int
        var expenses: Int
        var budgets: Int
        var bills: Int?
        var occurrences: Int?
        private enum CodingKeys: String, CodingKey { case card = "book", draft, categories, expenses, budgets, bills, occurrences }
    }
    static func encode(_ workspace: WorkspaceBackup) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var data = magic(workspace.formatVersion)
        func append(_ frame: Data) {
            var length = UInt64(frame.count).bigEndian
            withUnsafeBytes(of: &length) { data.append(contentsOf: $0) }
            data.append(frame)
        }
        func appendJSON<T: Encodable>(_ value: T) throws { append(try encoder.encode(value)) }
        try appendJSON(Header(exportedAt: workspace.exportedAt, currency: workspace.currency, minorUnitScale: workspace.minorUnitScale,
                              settings: workspace.settings, preferences: workspace.preferences, cardCount: workspace.cards.count,
                              assetCount: workspace.cardArtworks?.count ?? 0))
        for item in workspace.cards {
            try appendJSON(CardHeader(card: item.card, draft: item.draft, categories: item.categories.count, expenses: item.expenses.count,
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
        guard let fileVersion = Self.version(of: data) else { throw BackupError.unsupported }
        var offset = magic(fileVersion).count
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
        guard header.cardCount > 0, header.cardCount <= (data.count - offset) / 8,
              header.assetCount >= 0, header.assetCount <= (data.count - offset) / 16 else { throw BackupError.invalid }
        var cards: [CardBackupItem] = []
        for _ in 0..<header.cardCount {
            let card = try read(CardHeader.self)
            let categories = try records(card.categories, ExpenseCategory.self)
            let expenses = try records(card.expenses, Expense.self)
            let budgets = try records(card.budgets, BudgetVersion.self)
            let bills = try card.bills.map { try records($0, Bill.self) }
            let occurrences = try card.occurrences.map { try records($0, BillOccurrence.self) }
            cards.append(CardBackupItem(card: card.card, categories: categories, expenses: expenses, budgets: budgets, draft: card.draft, bills: bills, billOccurrences: occurrences))
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
        return WorkspaceBackup(formatVersion: fileVersion, exportedAt: header.exportedAt, currency: header.currency, minorUnitScale: header.minorUnitScale,
                               cards: cards, preferences: header.preferences, settings: header.settings, cardArtworks: assets.isEmpty ? nil : assets)
    }
}

enum BackupError: LocalizedError {
    case unsupported, invalid, tooLarge, recoveryRequired, missingArtwork
    var errorDescription: String? {
        switch self {
        case .unsupported: "This backup version is not supported by this version of Ankka."
        case .invalid: "The backup contains invalid or inconsistent records. Your current workspace has not been replaced."
        case .tooLarge: "This legacy backup exceeds its supported size. Export a current workspace backup to preserve all records and artwork."
        case .recoveryRequired: "Restoration could not finish or roll back. Restart ankka to recover from the retained safety backup. Your original data has been kept."
        case .missingArtwork: "A card photo is missing or unreadable. Restore the photo before exporting or replacing this workspace."
        }
    }
}
