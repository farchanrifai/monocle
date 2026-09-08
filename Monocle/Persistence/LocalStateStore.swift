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
    /// The profile binds this otherwise single-book state file to the Core Data book and backup contract.
    var book = BookProfile.sample
    var budget: Int64 = 450_000_000
    var startDay = 1
    var billAutomatic = false
    var billReminder = true
    /// Nil means the app never presents its own lock. System Shortcut authentication is separate.
    var appLockTimeout: AppLockTimeout?
    /// Archived categories remain attached to historical expenses but are hidden from new capture.
    var archivedCategoryIDs: Set<UUID> = []
    var categoryRules: [CategoryRule] = []

    private enum CodingKeys: String, CodingKey { case book, budget, startDay, billAutomatic, billReminder, appLockTimeout, archivedCategoryIDs, categoryRules }
    init() {}
    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        book = try values.decodeIfPresent(BookProfile.self, forKey: .book) ?? .sample
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
        try values.encode(book, forKey: .book)
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
    func loadSettings() throws -> PrototypeSettings
    func saveSettings(_ settings: PrototypeSettings) throws
}

/// Retains the original filenames and encoding so existing installations reopen unchanged.
@MainActor
final class FileLocalStateStore: LocalStateStore {
    private let directory: URL
    init(directory: URL) { self.directory = directory }
    func loadDraft() throws -> ExpenseDraft { try read("draft.json") ?? ExpenseDraft() }
    func saveDraft(_ draft: ExpenseDraft) throws { try write(draft, name: "draft.json") }
    func loadSettings() throws -> PrototypeSettings { try read("settings.json") ?? PrototypeSettings() }
    func saveSettings(_ settings: PrototypeSettings) throws { try write(settings, name: "settings.json") }

    private func read<T: Decodable>(_ name: String) throws -> T? {
        let url = directory.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder().decode(T.self, from: Data(contentsOf: url))
    }
    private func write<T: Encodable>(_ value: T, name: String) throws {
        try JSONEncoder().encode(value).write(to: directory.appendingPathComponent(name), options: .atomic)
    }
}
