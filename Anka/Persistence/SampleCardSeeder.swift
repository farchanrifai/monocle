import Foundation

@MainActor
enum SampleCardSeeder {
    static func seedIfNeeded(repository: ExpenseRepository, directory: URL) throws {
        let marker = directory.appendingPathComponent("sample-seeded")
        guard !FileManager.default.fileExists(atPath: marker.path) else { return }
        guard try repository.cards().contains(where: { $0.id == Card.demo.id && $0.kind == .demo }) else {
            try Data("1".utf8).write(to: marker, options: .atomic)
            return
        }
        let existing = Set(try repository.expenses(in: Card.demo.id).map(\.id))
        let categories = ExpenseCategory.defaults
        let sample: [(Int, String, Int64, Int)] = [(0, "Morning coffee", 28_000, 0), (0, "Lunch at work", 45_000, 0), (0, "Ride home", 32_000, 1), (-1, "Weekly groceries", 185_000, 3), (-1, "Cinema night", 65_000, 5), (-2, "Coffee with friends", 56_000, 0)]
        try repository.transaction {
        for (index, value) in sample.enumerated() {
            let id = UUID(uuidString: String(format: "30000000-0000-0000-0000-%012d", index + 1))!
            guard !existing.contains(id) else { continue }
            let date = Calendar.current.date(byAdding: .day, value: value.0, to: .now) ?? .now
            let expense = Expense(id: id, amount: value.2 * 100, day: Day.string(date), note: value.1,
                                  splits: [.init(categoryID: categories[value.3].id, amount: value.2 * 100)],
                                  source: "sample", createdAt: date.addingTimeInterval(Double(-index) * 60))
            try repository.save(expense, in: Card.demo.id)
        }
        try Data("1".utf8).write(to: marker, options: .atomic)
        }
    }
}
