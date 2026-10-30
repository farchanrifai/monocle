import Foundation

enum AppLockTimeout: String, Codable, CaseIterable, Identifiable {
    case immediately
    case oneMinute
    case fiveMinutes

    var id: String { rawValue }
    var title: String {
        switch self {
        case .immediately: "Immediately"
        case .oneMinute: "After 1 minute"
        case .fiveMinutes: "After 5 minutes"
        }
    }
    var interval: TimeInterval {
        switch self {
        case .immediately: 0
        case .oneMinute: 60
        case .fiveMinutes: 5 * 60
        }
    }
}

struct PrototypeSettings: Codable, Equatable {
    /// The profile binds this otherwise single-card state file to the Core Data card and backup contract.
    var card = Card.demo
    var budget: Int64 = 450_000_000
    var startDay = 1
    var billAutomatic = false
    var billReminder = true
    /// Nil means the app never presents its own lock. System Shortcut authentication is separate.
    var appLockTimeout: AppLockTimeout?
    /// Archived categories remain attached to historical expenses but are hidden from new capture.
    var archivedCategoryIDs: Set<UUID> = []
    var categoryRules: [CategoryRule] = []

    private enum CodingKeys: String, CodingKey { case card = "book", budget, startDay, billAutomatic, billReminder, appLockTimeout, archivedCategoryIDs, categoryRules }
    init() {}
    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        card = try values.decodeIfPresent(Card.self, forKey: .card) ?? .demo
        budget = try values.decodeIfPresent(Int64.self, forKey: .budget) ?? 450_000_000
        startDay = try values.decodeIfPresent(Int.self, forKey: .startDay) ?? 1
        billAutomatic = try values.decodeIfPresent(Bool.self, forKey: .billAutomatic) ?? false
        billReminder = try values.decodeIfPresent(Bool.self, forKey: .billReminder) ?? true
        appLockTimeout = try values.decodeIfPresent(AppLockTimeout.self, forKey: .appLockTimeout)
        archivedCategoryIDs = try values.decodeIfPresent(Set<UUID>.self, forKey: .archivedCategoryIDs) ?? []
        categoryRules = try values.decodeIfPresent([CategoryRule].self, forKey: .categoryRules) ?? []
    }
    func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(card, forKey: .card)
        try values.encode(budget, forKey: .budget); try values.encode(startDay, forKey: .startDay)
        try values.encode(billAutomatic, forKey: .billAutomatic); try values.encode(billReminder, forKey: .billReminder)
        try values.encodeIfPresent(appLockTimeout, forKey: .appLockTimeout); try values.encode(archivedCategoryIDs, forKey: .archivedCategoryIDs)
        try values.encode(categoryRules, forKey: .categoryRules)
    }
}

@MainActor
protocol LocalStateStore {
    func loadDraft() throws -> ExpenseDraft
    func saveDraft(_ draft: ExpenseDraft) throws
    func loadDraft(for cardID: UUID) throws -> ExpenseDraft
    func saveDraft(_ draft: ExpenseDraft, for cardID: UUID) throws
    func loadSettings() throws -> PrototypeSettings
    func saveSettings(_ settings: PrototypeSettings) throws
    func loadWorkspacePreferences() throws -> WorkspacePreferences
    func saveWorkspacePreferences(_ preferences: WorkspacePreferences) throws
}

/// Retains the original filenames and encoding so existing installations reopen unchanged.
@MainActor
final class FileLocalStateStore: LocalStateStore {
    private let directory: URL
    init(directory: URL) { self.directory = directory }
    func loadDraft() throws -> ExpenseDraft { try loadDraft(for: Card.demo.id) }
    func saveDraft(_ draft: ExpenseDraft) throws { try saveDraft(draft, for: draft.cardID ?? Card.demo.id) }

    func loadDraft(for cardID: UUID) throws -> ExpenseDraft {
        if let draft: ExpenseDraft = try read("draft-\(cardID.uuidString).json") {
            return draft
        }
        if cardID == Card.demo.id, let legacy: ExpenseDraft = try read("draft.json") {
            return legacy
        }
        return ExpenseDraft()
    }

    func saveDraft(_ draft: ExpenseDraft, for cardID: UUID) throws {
        var draft = draft
        draft.cardID = cardID
        try write(draft, name: "draft-\(cardID.uuidString).json")
        if cardID == Card.demo.id {
            var legacy = draft
            legacy.cardID = nil
            try write(legacy, name: "draft.json")
        }
    }

    func loadSettings() throws -> PrototypeSettings { try read("settings.json") ?? PrototypeSettings() }
    func saveSettings(_ settings: PrototypeSettings) throws { try write(settings, name: "settings.json") }

    func loadWorkspacePreferences() throws -> WorkspacePreferences { try read("workspace.json") ?? WorkspacePreferences() }
    func saveWorkspacePreferences(_ preferences: WorkspacePreferences) throws { try write(preferences, name: "workspace.json") }

    private func read<T: Decodable>(_ name: String) throws -> T? {
        let url = directory.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
    }
    private func write<T: Encodable>(_ value: T, name: String) throws {
        try JSONEncoder().encode(value).write(to: directory.appendingPathComponent(name), options: .atomic)
    }
}
