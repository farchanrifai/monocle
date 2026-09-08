import Foundation

enum CategoryError: LocalizedError {
    case invalidName, duplicateName, invalidSymbol, inUse, invalidRule, duplicateRule
    var errorDescription: String? {
        switch self {
        case .invalidName: "Use a category name between 1 and 40 characters."
        case .duplicateName: "A category with this name already exists."
        case .invalidSymbol: "Choose an icon from the list."
        case .inUse: "This category is used by an expense, your draft, or an expense available to undo. You can rename it, but it cannot be deleted."
        case .invalidRule: "Use one keyword between 1 and 40 characters."
        case .duplicateRule: "That keyword already has a rule."
        }
    }
}

struct CategoryRule: Codable, Identifiable, Equatable {
    var id: UUID
    var keyword: String
    var categoryID: UUID

    func validated(against categories: [ExpenseCategory], archivedIDs: Set<UUID>) throws -> Self {
        var result = self
        result.keyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !result.keyword.isEmpty, result.keyword.count <= 40,
              !result.keyword.contains(where: { $0.isWhitespace }),
              result.keyword.rangeOfCharacter(from: .controlCharacters) == nil,
              categories.contains(where: { $0.id == result.categoryID && !archivedIDs.contains($0.id) }) else { throw CategoryError.invalidRule }
        return result
    }
}

extension ExpenseCategory {
    static let symbols = ["cup.and.saucer", "tram", "bag", "house", "heart", "sparkles", "airplane", "book", "gift", "pawprint", "car", "bicycle", "cart", "fork.knife", "gamecontroller", "leaf", "wifi", "briefcase", "graduationcap", "cross.case", "music.note", "tshirt", "dumbbell", "circle.grid.2x2"]
    func validated(against categories: [ExpenseCategory]) throws -> Self {
        var result = self
        result.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.name.isEmpty, result.name.count <= 40,
              result.name.rangeOfCharacter(from: .controlCharacters) == nil else { throw CategoryError.invalidName }
        func key(_ name: String) -> String { name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX")) }
        guard !categories.contains(where: { $0.id != id && key($0.name) == key(result.name) }) else { throw CategoryError.duplicateName }
        guard Self.symbols.contains(symbol) else { throw CategoryError.invalidSymbol }
        return result
    }
}
