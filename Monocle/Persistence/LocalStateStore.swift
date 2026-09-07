import Foundation

struct PrototypeSettings: Codable, Equatable {
    var budget: Int64 = 450_000_000
    var startDay = 1
    var billAutomatic = false
    var billReminder = true
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
