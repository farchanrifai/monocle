#if DEBUG
import Foundation

/// Debug-only demo workspace: 5 cards in 3 stacks, about a year of varied spending, budgets and bills.
/// Launched with MONOCLE_DEMO=1 into its own folder (monocle-demo), so real data is never touched.
/// Deterministic: the same seed always produces the same ledger, relative to `now`.
enum DemoWorkspace {
    static func make(now: Date = .now) -> WorkspaceBackup {
        var random = Generator(seed: 42)
        let cal = Day.calendar
        let today = cal.startOfDay(for: now)
        func day(_ offset: Int) -> String { Day.string(cal.date(byAdding: .day, value: -offset, to: today)!) }

        let base = ExpenseCategory.defaults
        let food = base[0], transport = base[1], shopping = base[2], home = base[3], wellbeing = base[4], leisure = base[5]
        func category(_ n: Int, _ name: String, _ symbol: String) -> ExpenseCategory {
            ExpenseCategory(id: UUID(uuidString: String(format: "50000000-0000-0000-0000-%012d", n))!, name: name, symbol: symbol)
        }
        let utilities = category(1, "Utilities", "wifi"), kids = category(2, "Kids", "graduationcap")
        let office = category(3, "Office", "briefcase"), lodging = category(4, "Lodging", "house"), activities = category(5, "Activities", "sparkles")

        func card(_ n: Int, _ name: String, _ color: Int) -> Card {
            Card(id: UUID(uuidString: String(format: "60000000-0000-0000-0000-%012d", n))!, name: name, colorIndex: color)
        }
        let daily = card(1, "Daily", 0), household = card(2, "Household", 1), work = card(3, "Work", 2)
        let tokyo = card(4, "Tokyo Trip", 3), bali = card(5, "Bali Trip", 4)

        // (category, notes, min…max rupiah, chance per day)
        typealias Pattern = (ExpenseCategory, [String], ClosedRange<Int>, Double)
        let dailyPatterns: [Pattern] = [
            (food, ["Kopi Kenangan", "Janji Jiwa", "Starbucks"], 18_000...65_000, 0.7),
            (food, ["Lunch", "Nasi Padang", "Warteg", "Bakso", "Sate Ayam"], 25_000...85_000, 0.8),
            (food, ["Dinner", "GoFood", "GrabFood", "Ramen", "Pizza"], 45_000...260_000, 0.45),
            (transport, ["Gojek", "Grab", "KRL", "Parkir", "Tol"], 5_000...65_000, 0.75),
            (transport, ["Bensin"], 120_000...350_000, 0.09),
            (shopping, ["Tokopedia", "Shopee", "Uniqlo", "Zara", "IKEA"], 60_000...850_000, 0.12),
            (wellbeing, ["Apotek", "Gym day pass", "Haircut", "Dokter"], 35_000...450_000, 0.07),
            (leisure, ["Cinema", "Steam", "Karaoke", "Gramedia", "Concert"], 50_000...650_000, 0.1),
        ]
        let householdPatterns: [Pattern] = [
            (home, ["Alfamart", "Indomaret", "Superindo", "Laundry"], 30_000...420_000, 0.45),
            (kids, ["School supplies", "Toys", "Snacks", "Swimming class"], 25_000...350_000, 0.15),
            (shopping, ["Home decor", "Kitchenware"], 90_000...900_000, 0.05),
        ]
        let workPatterns: [Pattern] = [
            (food, ["Client lunch", "Team coffee", "Overtime dinner"], 60_000...750_000, 0.25),
            (transport, ["Grab to client", "Taxi", "Train to Bandung"], 25_000...420_000, 0.25),
            (office, ["Printer ink", "Co-working day", "Stationery", "Software license"], 40_000...1_200_000, 0.08),
        ]
        let tripPatterns: [Pattern] = [
            (food, ["Ramen", "Sushi", "Konbini", "Beach club", "Warung", "Cafe"], 40_000...650_000, 1.8),
            (transport, ["Train", "Taxi", "Scooter rental", "Airport transfer"], 20_000...550_000, 1.0),
            (activities, ["Museum", "Temple tour", "Surf lesson", "Theme park"], 90_000...1_400_000, 0.5),
            (shopping, ["Souvenirs", "Clothes", "Duty free"], 80_000...1_800_000, 0.4),
        ]

        var counter = 0
        func expenses(_ patterns: [Pattern], days: [Int], card: Card, scale: Double = 1) -> [Expense] {
            var result: [Expense] = []
            for offset in days {
                // Spending drifts up toward recent months and peaks in December, so trends and comparisons have shape.
                let date = cal.date(byAdding: .day, value: -offset, to: today)!
                let month = cal.component(.month, from: date)
                let drift = (1.25 - Double(offset) / 1460) * (month == 12 ? 1.35 : 1) * scale
                for (category, notes, range, chance) in patterns {
                    var times = Int(chance)
                    if random.unit() < chance - Double(times) { times += 1 }
                    for _ in 0..<times {
                        counter += 1
                        let rupiah = Int64((Double(random.int(in: range)) * drift / 1000).rounded()) * 1000
                        let minor = max(rupiah, 1000) * 100
                        let note = notes[random.int(in: 0...(notes.count - 1))]
                        let id = UUID(uuidString: String(format: "70000000-0000-0000-0000-%012d", counter))!
                        result.append(Expense(id: id, amount: minor, day: day(offset), note: note,
                                              allocations: [.init(categoryID: category.id, amount: minor)], source: "demo",
                                              createdAt: date.addingTimeInterval(Double(8 * 3600 + counter % 36_000)), cardID: card.id))
                    }
                }
            }
            return result
        }

        var dailyExpenses = expenses(dailyPatterns, days: Array(0..<365), card: daily)
        // A few split purchases (one receipt, two categories).
        for offset in stride(from: 3, to: 360, by: 17) {
            counter += 1
            let foodPart = Int64(random.int(in: 60...240)) * 1000_00, homePart = Int64(random.int(in: 40...180)) * 1000_00
            dailyExpenses.append(Expense(id: UUID(uuidString: String(format: "70000000-0000-0000-0000-%012d", counter))!,
                                         amount: foodPart + homePart, day: day(offset), note: "Pasar",
                                         allocations: [.init(categoryID: food.id, amount: foodPart), .init(categoryID: home.id, amount: homePart)],
                                         source: "demo", cardID: daily.id))
        }
        let householdExpenses = expenses(householdPatterns, days: Array(0..<365), card: household)
        let workdays = (0..<365).filter { !cal.isDateInWeekend(cal.date(byAdding: .day, value: -$0, to: today)!) }
        let workExpenses = expenses(workPatterns, days: workdays, card: work)
        // Tokyo about seven months ago, Bali in the last few weeks.
        let tokyoExpenses = expenses(tripPatterns, days: Array(205..<215), card: tokyo, scale: 1.4)
        let baliExpenses = expenses(tripPatterns, days: Array(12..<18), card: bali)

        func budget(_ card: Card, _ limit: Int64, _ limits: [(ExpenseCategory, Int64)]) -> [BudgetVersion] {
            var version = BudgetVersion.initial(overallLimit: limit * 100, startDay: 1, date: cal.date(byAdding: .year, value: -1, to: today)!, cardID: card.id)
            version.categoryLimits = limits.map { CategoryBudget(categoryID: $0.0.id, limit: $0.1 * 100) }
            return [version]
        }
        func bill(_ n: Int, _ card: Card, _ name: String, _ rupiah: Int64, _ category: ExpenseCategory, _ recurrence: BillRecurrence) -> BillRule {
            BillRule(id: UUID(uuidString: String(format: "80000000-0000-0000-0000-%012d", n))!, cardID: card.id, name: name,
                     amount: rupiah * 100, categoryID: category.id, recurrence: recurrence, recordingMode: .pending, hasReminder: true)
        }

        let cards = [
            CardBackupItem(card: daily, categories: base, expenses: dailyExpenses,
                           budgets: budget(daily, 9_000_000, [(food, 3_500_000), (transport, 1_200_000), (leisure, 900_000), (shopping, 1_000_000)]),
                           bills: [bill(1, daily, "Netflix", 186_000, leisure, .monthly(day: 5)),
                                   bill(2, daily, "Spotify", 55_000, leisure, .monthly(day: 12)),
                                   bill(3, daily, "Gym membership", 450_000, wellbeing, .monthly(day: 1))]),
            CardBackupItem(card: household, categories: base + [utilities, kids], expenses: householdExpenses,
                           budgets: budget(household, 7_000_000, [(home, 4_000_000), (kids, 1_500_000)]),
                           bills: [bill(4, household, "Internet", 450_000, utilities, .monthly(day: 10)),
                                   bill(5, household, "Electricity", 900_000, utilities, .monthly(day: 20)),
                                   bill(6, household, "Car insurance", 4_800_000, utilities, .yearly(month: 3, day: 15))]),
            CardBackupItem(card: work, categories: [food, transport, office], expenses: workExpenses,
                           budgets: budget(work, 3_000_000, [(office, 1_000_000)])),
            CardBackupItem(card: tokyo, categories: [food, transport, shopping, lodging, activities], expenses: tokyoExpenses,
                           budgets: budget(tokyo, 25_000_000, [])),
            CardBackupItem(card: bali, categories: [food, transport, shopping, lodging, activities], expenses: baliExpenses,
                           budgets: budget(bali, 15_000_000, [])),
        ]

        var preferences = WorkspacePreferences()
        let everyday = CardStack(id: UUID(uuidString: "90000000-0000-0000-0000-000000000001")!, name: "Everyday", icon: "house", cardIDs: [daily.id, household.id])
        preferences.stacks = [everyday,
                              CardStack(id: UUID(uuidString: "90000000-0000-0000-0000-000000000002")!, name: "Travel", icon: "airplane", cardIDs: [tokyo.id, bali.id]),
                              CardStack(id: UUID(uuidString: "90000000-0000-0000-0000-000000000003")!, name: "Work", icon: "briefcase", cardIDs: [work.id])]
        preferences.activeStackID = everyday.id
        preferences.cardOrder = cards.map(\.card.id)
        var settings = PrototypeSettings()
        settings.card = daily
        settings.budget = 9_000_000_00
        return WorkspaceBackup(cards: cards, preferences: preferences, settings: settings)
    }

    /// SplitMix64: small, seedable, and the same on every run.
    struct Generator {
        var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
        mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }
        mutating func int(in range: ClosedRange<Int>) -> Int { range.lowerBound + Int(next() % UInt64(range.count)) }
    }
}
#endif
