import Foundation

enum BookKind: String, Codable, Equatable { case sample, real }

struct BookProfile: Codable, Equatable {
    var id: UUID
    var name: String
    var kind: BookKind

    static let sample = Self(id: UUID(uuidString: "20000000-0000-0000-0000-000000000001")!, name: "Sample book", kind: .sample)

    static func real(named name: String) throws -> Self {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 40 else { throw BackupError.invalid }
        return Self(id: UUID(), name: name, kind: .real)
    }
}

struct BookBackup: Codable {
    var formatVersion = 1
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

    var total: Int64 { expenses.reduce(0) { $0 + $1.amount } }
    func validate() throws {
        guard (formatVersion == 1 || formatVersion == 2), currency == "IDR", minorUnitScale == 2 else { throw BackupError.unsupported }
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
              settings.categoryRules.allSatisfy { rule in (try? rule.validated(against: categories, archivedIDs: settings.archivedCategoryIDs)) == rule },
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
