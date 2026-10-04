import Foundation

@MainActor
enum SampleBookSeeder {
    static func seedIfNeeded(repository: ExpenseRepository, directory: URL) throws {
        let marker = directory.appendingPathComponent("sample-seeded")
        guard !FileManager.default.fileExists(atPath: marker.path) else { return }
        guard try repository.books().contains(where: { $0.id == BookProfile.sample.id && $0.kind == .sample }) else {
            try Data("1".utf8).write(to: marker, options: .atomic)
            return
        }
        let existing = Set(try repository.expenses(in: BookProfile.sample.id).map(\.id))
        let categories = ExpenseCategory.defaults
        let sample: [(Int, String, Int64, Int)] = [(0, "Morning coffee", 28_000, 0), (0, "Lunch at work", 45_000, 0), (0, "Ride home", 32_000, 1), (-1, "Weekly groceries", 185_000, 3), (-1, "Cinema night", 65_000, 5), (-2, "Coffee with friends", 56_000, 0)]
        try repository.transaction {
        for (index, value) in sample.enumerated() {
            let id = UUID(uuidString: String(format: "30000000-0000-0000-0000-%012d", index + 1))!
            guard !existing.contains(id) else { continue }
            let date = Calendar.current.date(byAdding: .day, value: value.0, to: .now) ?? .now
            let expense = Expense(id: id, amount: value.2 * 100, day: Day.string(date), note: value.1,
                                  allocations: [.init(categoryID: categories[value.3].id, amount: value.2 * 100)],
                                  source: "sample", createdAt: date.addingTimeInterval(Double(-index) * 60))
            try repository.save(expense, in: BookProfile.sample.id)
        }
        try Data("1".utf8).write(to: marker, options: .atomic)
        }
    }
}
