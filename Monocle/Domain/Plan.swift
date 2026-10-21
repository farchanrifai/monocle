import Foundation

/// Free and Pro (docs/planning/app-store-release.md). Pure rules; ExpenseService enforces them on every write.
struct Plan: Equatable, Sendable {
    var isPro: Bool
    /// The one real card a Free workspace keeps writing to. Chosen once, stored outside backups.
    var keptCardID: UUID? = nil

    static let freeCards = 1
    static let freeBills = 3
    /// Entries the user may add to the Sample card, on Free and Pro alike (seeded entries don't count).
    static let sampleEntries = 10
    static let freeQuestionsPerDay = 5

    /// The writable real card on Free: the chosen one, else the first real card.
    func keptCard(in cards: [Card]) -> UUID? {
        let real = cards.filter { $0.kind == .real }
        return real.first { $0.id == keptCardID }?.id ?? real.first?.id
    }

    /// Real cards beyond the kept one are read-only on Free. The Sample card is never locked.
    func isLocked(_ cardID: UUID, in cards: [Card]) -> Bool {
        guard !isPro, let card = cards.first(where: { $0.id == cardID }), card.kind == .real else { return false }
        return card.id != keptCard(in: cards)
    }

    /// Active bills that don't run on Free: those on locked cards, then all but the three oldest.
    func frozenBills(_ bills: [Bill], cards: [Card]) -> Set<UUID> {
        guard !isPro else { return [] }
        let active = bills.filter(\.isActive)
        let locked = active.filter { isLocked($0.cardID, in: cards) }
        let open = active.filter { !isLocked($0.cardID, in: cards) }.sorted { $0.createdAt < $1.createdAt }
        return Set(locked.map(\.id) + open.dropFirst(Self.freeBills).map(\.id))
    }
}

enum PlanError: LocalizedError, Equatable {
    case cardLimit, lockedCard, billLimit, sampleLimit, foreignCurrency

    var errorDescription: String? {
        switch self {
        case .cardLimit: "Free includes one card. Upgrade to Pro for more cards and stacks."
        case .lockedCard: "This card is read-only on Free. Upgrade to Pro to change it."
        case .billLimit: "Free includes \(Plan.freeBills) active bills. Upgrade to Pro for more, or pause one first."
        case .sampleLimit: "The Sample card is for trying things out. Add this to your card."
        case .foreignCurrency: "Spending in another currency is part of Pro."
        }
    }

    /// Pro unlocks it, so the app offers the paywall rather than only an alert.
    var opensPaywall: Bool { self != .sampleLimit }
}
