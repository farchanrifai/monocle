import Foundation

/// The demo workspace: four cards (USD, EUR, JPY), about three months of everyday spending, budgets and bills, in USD,
/// dated back from the day it is made. Settings ▸ Try the demo opens it in a throwaway copy (AppEnvironment.makeDemo).
/// Debug builds can also launch into it with `-DemoData YES`, or always in the Demo build (`ANKKA_DEMO_BUILD`).
/// Bill reminders never reach the system schedule, so the real workspace's reminders are left alone.
enum DemoData {
    #if DEBUG
    #if ANKKA_DEMO_BUILD
    static let isEnabled = true
    #else
    static var isEnabled: Bool { ProcessInfo.processInfo.arguments.contains("-DemoData") }
    #endif

    /// Never the Application Support folder the real workspace uses.
    static func directory() throws -> URL {
        #if ANKKA_DEMO_BUILD
        // Kept between launches, so what is added while shooting stays and dates stay anchored to the first launch.
        let url = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("ankka-demo-data", isDirectory: true)
        #else
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ankka-demo-data", isDirectory: true)
        try? FileManager.default.removeItem(at: url)
        #endif
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    #endif

    /// Rebuilding the reminder schedule would replace the real workspace's pending reminders on this device.
    @MainActor static let notifications = BillNotificationService(client: SilentNotifications())

    @MainActor private final class SilentNotifications: BillNotificationClient {
        func authorization() async -> BillReminderAuthorization { .authorized }
        func requestAuthorization() async throws -> Bool { true }
        func pendingIdentifiers() async -> [String] { [] }
        func add(_ reminder: BillReminder) async throws {}
        func remove(_ identifiers: [String]) {}
    }

    /// Deterministic for a given `now`. Budgets start mid-way so today lands in the middle of each cycle.
    static func make(now: Date = .now) -> WorkspaceBackup {
        var random = Generator(seed: 2026)
        let cal = Day.calendar
        let today = cal.startOfDay(for: now)
        func date(_ offset: Int) -> Date { cal.date(byAdding: .day, value: -offset, to: today)! }
        func dayOfMonth(_ offset: Int) -> Int { min(28, cal.component(.day, from: date(offset))) }
        var counter = 0
        func nextID(_ prefix: Int) -> UUID {
            counter += 1
            return UUID(uuidString: String(format: "%08d-0000-0000-0000-%012d", prefix, counter))!
        }

        let base = ExpenseCategory.defaults
        let food = base[0], transport = base[1], shopping = base[2], home = base[3], wellbeing = base[4], leisure = base[5]
        func category(_ n: Int, _ name: String, _ symbol: String) -> ExpenseCategory {
            ExpenseCategory(id: UUID(uuidString: String(format: "51000000-0000-0000-0000-%012d", n))!, name: name, symbol: symbol)
        }
        let utilities = category(1, "Utilities", "wifi"), lodging = category(2, "Lodging", "house"), activities = category(3, "Activities", "sparkles")

        func card(_ n: Int, _ name: String, _ color: Int, _ currency: String? = nil) -> Card {
            Card(id: UUID(uuidString: String(format: "61000000-0000-0000-0000-%012d", n))!, name: name, colorIndex: color, currency: currency)
        }
        let everyday = card(1, "Everyday", 0), homeCard = card(2, "Home", 9)
        let lisbon = card(3, "Travel — Lisbon", 1, "EUR"), tokyo = card(4, "Tokyo trip", 6, "JPY")

        /// A price in minor units: cafe-sized prices end in 5 cents, yen prices in 10 yen, and none end in .00.
        func price(_ range: ClosedRange<Double>, code: String = "USD") -> Int64 {
            let whole = Money.fractionDigits(code) == 0
            var cents = random.int(in: Int(range.lowerBound * 100)...Int(range.upperBound * 100))
            if whole { return Int64(cents / 1000 * 1000) }
            if range.upperBound < 15 { cents -= cents % 5 }
            if cents % 100 == 0 { cents += 45 }
            return Int64(cents)
        }
        func at(_ offset: Int, hour: Int) -> Date { date(offset).addingTimeInterval(Double(hour * 3600 + random.int(in: 0...3300))) }
        func expense(_ offset: Int, _ note: String, _ parts: [(ExpenseCategory, Int64)], card: Card, hour: Int,
                     rate: Decimal? = nil, source: String = "demo") -> Expense {
            let total = parts.reduce(0) { $0 + $1.1 }
            guard let code = card.currency, let rate else {
                return Expense(id: nextID(71_000_000), amount: total, day: Day.string(date(offset)), note: note,
                               splits: parts.map { .init(categoryID: $0.0.id, amount: $0.1) }, source: source,
                               createdAt: at(offset, hour: hour), cardID: card.id)
            }
            // Foreign cards: one category, paid in the card's currency, recorded in USD at the day's rate.
            let usd = try! Money.convert(total, rate: rate, to: "USD")
            return Expense(id: nextID(71_000_000), amount: usd, day: Day.string(date(offset)), note: note,
                           splits: [.init(categoryID: parts[0].0.id, amount: usd)], source: source, createdAt: at(offset, hour: hour),
                           cardID: card.id, originalAmount: total, originalCurrency: code, rate: "\(rate)", rateSource: .fetched)
        }

        typealias Pattern = (notes: [String], category: ExpenseCategory, price: ClosedRange<Double>, weekday: Double, weekend: Double, hour: ClosedRange<Int>)
        func spending(_ patterns: [Pattern], days: [Int], card: Card, rate: (Int) -> Decimal? = { _ in nil }) -> [Expense] {
            var result: [Expense] = []
            for offset in days {
                let weekend = cal.isDateInWeekend(date(offset))
                for pattern in patterns {
                    // Today holds only what happens before the screenshot's 9:41.
                    if offset == 0, pattern.hour.lowerBound > 9 { continue }
                    let chance = weekend ? pattern.weekend : pattern.weekday
                    var times = Int(chance)
                    if random.unit() < chance - Double(times) { times += 1 }
                    for _ in 0..<times {
                        let note = pattern.notes[random.int(in: 0...(pattern.notes.count - 1))]
                        result.append(expense(offset, note, [(pattern.category, price(pattern.price, code: card.currency ?? "USD"))],
                                              card: card, hour: random.int(in: pattern.hour), rate: rate(offset)))
                    }
                }
            }
            return result
        }

        let quarter = Array(0..<92)
        let cycleStart = 14 // Everyday's cycle began two weeks ago
        var everydayExpenses = spending([
            (["Oat latte"], food, 4.75...6.25, 0.16, 0.08, 7...8),
            (["Corner bakery"], food, 3.80...11.60, 0.06, 0.22, 8...10),
            (["Noodle bar lunch", "Deli sandwich", "Salad bowl", "Burrito lunch"], food, 10.90...17.80, 0.12, 0.02, 12...13),
            (["Grocery run", "Corner store"], food, 26.00...148.00, 0.07, 0.32, 17...19),
            (["Dinner with Sam", "Thai takeout", "Pizza night", "Neighborhood bistro"], food, 38.00...112.00, 0.05, 0.28, 19...21),
            (["Rideshare home"], transport, 11.20...26.90, 0.02, 0.07, 22...23),
            (["Bookshop", "Running socks", "Linen shirt", "Phone case", "Desk lamp"], shopping, 18.00...129.00, 0.035, 0.08, 13...17),
            (["Cinema tickets", "Museum day", "Board game café"], leisure, 18.00...64.00, 0.015, 0.1, 15...20),
            (["Pharmacy", "Haircut", "Yoga class"], wellbeing, 12.40...48.00, 0.03, 0.05, 10...18),
        ], days: quarter, card: everyday)
        // Split receipts: Saturday market runs and a couple of mixed bookshop visits.
        for offset in quarter.dropFirst() where cal.component(.weekday, from: date(offset)) == 7 && random.unit() < 0.55 {
            everydayExpenses.append(expense(offset, "Farmers market", [(food, price(16.0...38.0)), (home, price(6.0...22.0))], card: everyday, hour: 10))
        }
        for offset in [27, 61] {
            everydayExpenses.append(expense(offset, "Bookshop", [(leisure, price(14.0...32.0)), (shopping, price(8.0...19.0))], card: everyday, hour: 16))
        }
        for offset in stride(from: 2, to: 92, by: 9) {
            everydayExpenses.append(expense(offset, "Metro card top-up", [(transport, price(24.0...42.0))], card: everyday, hour: 8))
        }
        everydayExpenses.append(expense(6, "Running shoes", [(shopping, 11_845)], card: everyday, hour: 15))
        everydayExpenses.append(expense(0, "Corner bakery", [(food, 435)], card: everyday, hour: 8)) // today, before 9:41
        // Fixed nights out inside the current cycle, so one category is clearly over its limit.
        everydayExpenses.append(expense(3, "Concert tickets", [(leisure, 8_645)], card: everyday, hour: 20))
        everydayExpenses.append(expense(9, "Cinema tickets", [(leisure, 3_175)], card: everyday, hour: 19))

        var homeExpenses = spending([
            (["Hardware store", "Cleaning supplies", "Houseplant", "Laundry detergent", "Bath towels"], home, 8.90...74.50, 0.04, 0.12, 11...17),
        ], days: quarter, card: homeCard)

        // Lisbon: under way, started five days ago; prices in euros.
        func eurRate(_ offset: Int) -> Decimal { Decimal(string: "1.16\(41 + offset % 4 * 7)")! }
        var lisbonExpenses = spending([
            (["Pastéis de nata"], food, 2.40...7.80, 0.7, 0.7, 10...16),
            (["Bica and toast"], food, 3.10...6.90, 0.5, 0.5, 8...9),
            (["Seafood dinner in Alfama", "Tasca dinner", "Bifana and beer", "Petiscos with friends"], food, 14.50...68.00, 1, 1, 19...21),
            (["Tram ticket", "Metro day pass", "Ferry to Cacilhas", "Train to Sintra"], transport, 1.85...14.40, 0.8, 0.8, 9...15),
            (["Tile museum", "Castle entry", "Fado night", "Tile workshop"], activities, 8.00...42.00, 0.4, 0.4, 11...21),
            (["Ceramics shop", "Sardine tins for gifts", "Linen tote"], shopping, 9.50...46.00, 0.3, 0.3, 12...18),
        ], days: Array(0...5), card: lisbon, rate: eurRate)
        lisbonExpenses.append(expense(5, "Guesthouse in Alfama", [(lodging, 48_645)], card: lisbon, hour: 15, rate: eurRate(5)))
        lisbonExpenses.append(expense(5, "Airport taxi", [(transport, 1_865)], card: lisbon, hour: 14, rate: eurRate(5)))

        // Tokyo: eight days that ended twelve days ago; prices in yen.
        func jpyRate(_ offset: Int) -> Decimal { Decimal(string: "0.00668\(offset % 5)")! }
        var tokyoExpenses = spending([
            (["Ramen near Shibuya", "Ramen counter", "Tsukemen lunch"], food, 980...1_680, 0.6, 0.6, 12...14),
            (["Konbini snacks", "Vending machine coffee", "Onigiri and tea"], food, 140...860, 0.6, 0.6, 8...22),
            (["Izakaya with friends", "Sushi counter dinner", "Yakitori alley", "Okonomiyaki"], food, 2_400...9_800, 0.8, 0.8, 19...22),
            (["Transit card top-up"], transport, 1_500...3_000, 0.25, 0.25, 9...10),
            (["Temple entry", "Museum ticket", "Digital art museum", "Tea ceremony"], activities, 500...3_800, 0.4, 0.4, 10...17),
            (["Stationery shop", "Vintage jacket", "Ceramic bowls", "Bookshop"], shopping, 880...12_400, 0.3, 0.3, 13...19),
        ], days: Array(12...19), card: tokyo, rate: jpyRate)
        tokyoExpenses.append(expense(19, "Business hotel, 8 nights", [(lodging, 9_680_000)], card: tokyo, hour: 16, rate: jpyRate(19)))
        tokyoExpenses.append(expense(19, "Airport express", [(transport, 307_000)], card: tokyo, hour: 14, rate: jpyRate(19)))
        tokyoExpenses.append(expense(16, "Shinkansen to Kyoto", [(transport, 1_417_000)], card: tokyo, hour: 8, rate: jpyRate(16)))

        // Bills began with the quarter; every past due day is already recorded, so only upcoming ones are pending.
        var occurrences: [UUID: [BillOccurrence]] = [:]
        func bill(_ n: Int, _ card: Card, _ name: String, _ amount: Int64, _ category: ExpenseCategory, day: Int,
                  reminder: Bool, mode: BillRecordingMode = .pending, paid: (Int) -> Int64 = { _ in 0 }) -> Bill {
            let rule = Bill(id: UUID(uuidString: String(format: "81000000-0000-0000-0000-%012d", n))!, cardID: card.id, name: name,
                            amount: amount, categoryID: category.id, recurrence: .monthly(day: day), recordingMode: mode,
                            hasReminder: reminder, reminderLeadDays: reminder ? 2 : 0, createdAt: date(91))
            for (index, due) in BillReconciliationEngine.dueDays(for: rule, from: date(91), to: today).enumerated() {
                let offset = cal.dateComponents([.day], from: cal.startOfDay(for: Day.date(due)!), to: today).day!
                let value = paid(index) > 0 ? paid(index) : amount
                let record = expense(offset, name, [(category, value)], card: card, hour: 9, source: "bill-confirmed")
                homeExpenses.append(record)
                occurrences[card.id, default: []].append(BillOccurrence(billRuleID: rule.id, cardID: card.id, dueDay: due, status: .recorded,
                                                                        expenseID: record.id, createdAt: Day.date(due)!, updatedAt: Day.date(due)!))
            }
            return rule
        }
        let electricity: [Int64] = [9_155, 7_812, 8_437, 8_893]
        // All bills live on Home, the household card; Everyday's budget is day-to-day spending.
        let homeBills = [
            bill(1, homeCard, "Phone", 4_815, utilities, day: 18, reminder: true),
            bill(2, homeCard, "Streaming", 1_549, leisure, day: 9, reminder: false, mode: .automatic),
            bill(3, homeCard, "Gym membership", 5_499, wellbeing, day: 3, reminder: true),
            bill(4, homeCard, "Rent", 165_000, home, day: 1, reminder: true),
            // Due in three days: the one upcoming bill.
            bill(5, homeCard, "Electricity bill", 8_637, utilities, day: dayOfMonth(-3), reminder: true, paid: { electricity[$0 % 4] }),
        ]

        // Everyday limits read from the current cycle: Food & Drink close to its limit, Leisure over.
        let cycle = Cycle.month(containing: today)
        func spent(_ category: ExpenseCategory) -> Double {
            Double(everydayExpenses.filter { cycle.contains($0) }.flatMap(\.splits).filter { $0.categoryID == category.id }.reduce(0) { $0 + $1.amount }) / 100
        }
        func dollars(_ value: Double) -> Int64 { Int64(value) * 100 }
        let limits: [(ExpenseCategory, Int64)] = [
            (food, dollars(max(50, (spent(food) / 0.93 / 50).rounded(.up) * 50))),
            (leisure, dollars(max(25, (spent(leisure) / 1.15 / 25).rounded(.down) * 25))),
            (shopping, dollars(max(250, (spent(shopping) * 1.8 / 50).rounded(.up) * 50))),
            (transport, dollars(max(150, (spent(transport) * 1.8 / 10).rounded(.up) * 10))),
        ]
        func monthly(_ card: Card, _ limit: Int64, startDay: Int, _ categoryLimits: [(ExpenseCategory, Int64)] = []) -> [BudgetVersion] {
            var version = BudgetVersion.initial(overallLimit: limit, startDay: startDay, date: date(91), cardID: card.id)
            version.id = nextID(91_000_000)
            version.categoryLimits = categoryLimits.map { CategoryBudget(categoryID: $0.0.id, limit: $0.1) }
            return [version]
        }
        // Lisbon has a "Total until" budget for the whole trip, ending four days from now.
        let trip = BudgetVersion(id: nextID(91_000_000), effectiveDay: Day.string(date(5)), overallLimit: 160_000, startDay: 1,
                                 cardID: lisbon.id, totalUntilDay: Day.string(date(-4)))

        let tripCategories = [food, transport, shopping, lodging, activities]
        let cards = [
            CardBackupItem(card: everyday, categories: base, expenses: everydayExpenses,
                           budgets: monthly(everyday, 180_000, startDay: dayOfMonth(cycleStart), limits)),
            CardBackupItem(card: homeCard, categories: base + [utilities], expenses: homeExpenses,
                           budgets: monthly(homeCard, 240_000, startDay: 1), bills: homeBills,
                           billOccurrences: occurrences[homeCard.id]),
            CardBackupItem(card: lisbon, categories: tripCategories, expenses: lisbonExpenses, budgets: [trip]),
            // The trip falls inside the current cycle, so the card still shows what it cost.
            CardBackupItem(card: tokyo, categories: tripCategories, expenses: tokyoExpenses,
                           budgets: monthly(tokyo, 23_000_000, startDay: dayOfMonth(19))),
        ]

        var preferences = WorkspacePreferences(reportingCurrency: "USD")
        let trips = Stack(id: UUID(uuidString: "91000000-0000-0000-0000-000000000001")!, name: "Trips", icon: "airplane", cardIDs: [lisbon.id, tokyo.id])
        preferences.stacks = [trips]
        preferences.activeStackID = trips.id
        preferences.filterScope = .allCards // Home shows all four cards
        preferences.autoAppearance = true // follows the simulator's light/dark setting
        preferences.cardOrder = [tokyo.id, lisbon.id, homeCard.id, everyday.id] // the deck opens the last card
        preferences.cardCustomizations = Dictionary(uniqueKeysWithValues: [everyday, homeCard, lisbon, tokyo].map { ($0.id, CardCustomization.newCard(colorIndex: $0.colorIndex)) })
        var settings = PrototypeSettings()
        settings.card = everyday
        settings.budget = 180_000
        settings.startDay = dayOfMonth(cycleStart)
        return WorkspaceBackup(currency: "USD", cards: cards, preferences: preferences, settings: settings)
    }

    /// SplitMix64: the same seed always makes the same ledger.
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
