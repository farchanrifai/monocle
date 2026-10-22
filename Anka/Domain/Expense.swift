import Foundation

struct ExpenseCategory: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var name: String
    var symbol: String

    static let defaults: [Self] = [
        .init(id: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!, name: "Food & Drink", symbol: "cup.and.saucer"),
        .init(id: UUID(uuidString: "10000000-0000-0000-0000-000000000002")!, name: "Transport", symbol: "tram"),
        .init(id: UUID(uuidString: "10000000-0000-0000-0000-000000000003")!, name: "Shopping", symbol: "bag"),
        .init(id: UUID(uuidString: "10000000-0000-0000-0000-000000000004")!, name: "Home", symbol: "house"),
        .init(id: UUID(uuidString: "10000000-0000-0000-0000-000000000005")!, name: "Wellbeing", symbol: "heart"),
        .init(id: UUID(uuidString: "10000000-0000-0000-0000-000000000006")!, name: "Leisure", symbol: "sparkles")
    ]
}

struct GlobalCategory: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var name: String
    var symbol: String
    var defaultActiveForNewCards: Bool = true

    init(id: UUID = UUID(), name: String, symbol: String, defaultActiveForNewCards: Bool = true) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.defaultActiveForNewCards = defaultActiveForNewCards
    }

    init(category: ExpenseCategory, defaultActiveForNewCards: Bool = true) {
        self.id = category.id
        self.name = category.name
        self.symbol = category.symbol
        self.defaultActiveForNewCards = defaultActiveForNewCards
    }

    func toExpenseCategory() -> ExpenseCategory {
        ExpenseCategory(id: id, name: name, symbol: symbol)
    }

    static let defaults: [GlobalCategory] = ExpenseCategory.defaults.map {
        GlobalCategory(category: $0, defaultActiveForNewCards: true)
    }
}

struct Split: Codable, Hashable, Sendable {
    var categoryID: UUID
    var amount: Int64
}

struct Expense: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var amount: Int64 // IDR minor units: Rp1 = 100 units.
    var day: String
    var note: String
    var splits: [Split]
    var source: String = "manual"
    var createdAt: Date = .now
    var cardID: UUID? = nil
    var paidWithID: UUID? = nil
    /// Set only when paid in another currency than the reporting one; `amount` is the converted value.
    var originalAmount: Int64? = nil
    var originalCurrency: String? = nil
    /// Reporting-currency units per one original unit, as a decimal string.
    var rate: String? = nil
    var rateSource: RateSource? = nil

    enum RateSource: String, Codable, Sendable { case fetched, manual }
    // Stored keys keep their pre-rename names so existing backups, drafts and settings still load.
    private enum CodingKeys: String, CodingKey {
        case id, amount, day, note, splits = "allocations", source, createdAt, cardID = "bookID"
        case paidWithID, originalAmount, originalCurrency, rate, rateSource
    }

    init(id: UUID = UUID(), amount: Int64, day: String, note: String, splits: [Split], source: String = "manual", createdAt: Date = .now, cardID: UUID? = nil,
         paidWithID: UUID? = nil, originalAmount: Int64? = nil, originalCurrency: String? = nil, rate: String? = nil, rateSource: RateSource? = nil) {
        self.id = id
        self.amount = amount
        self.day = day
        self.note = note
        self.splits = splits
        self.source = source
        self.createdAt = createdAt
        self.cardID = cardID
        self.paidWithID = paidWithID
        self.originalAmount = originalAmount
        self.originalCurrency = originalCurrency
        self.rate = rate
        self.rateSource = rateSource
    }

    /// Equal expenses share an id, so hashing the id keeps `==` and the hash consistent.
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    static func == (lhs: Expense, rhs: Expense) -> Bool {
        lhs.id == rhs.id &&
        lhs.amount == rhs.amount &&
        lhs.day == rhs.day &&
        lhs.note == rhs.note &&
        lhs.splits == rhs.splits &&
        lhs.source == rhs.source &&
        lhs.createdAt == rhs.createdAt &&
        lhs.paidWithID == rhs.paidWithID &&
        lhs.originalAmount == rhs.originalAmount &&
        lhs.originalCurrency == rhs.originalCurrency &&
        lhs.rate == rhs.rate &&
        lhs.rateSource == rhs.rateSource &&
        (lhs.cardID == nil || rhs.cardID == nil || lhs.cardID == rhs.cardID)
    }

    func validate(categories: [ExpenseCategory]) throws {
        guard amount > 0, amount <= Money.maximum else { throw EntryError.invalidAmount }
        // The foreign-currency fields travel together or not at all.
        if originalCurrency != nil || originalAmount != nil || rate != nil || rateSource != nil {
            guard let originalCurrency, Money.isCurrencyCode(originalCurrency),
                  let originalAmount, originalAmount > 0, originalAmount <= Money.maximum,
                  let rate, let value = Decimal(string: rate, locale: Locale(identifier: "en_US_POSIX")), value > 0,
                  rateSource != nil else { throw EntryError.invalidAmount }
        }
        guard Day.date(day) != nil else { throw EntryError.invalidDate }
        guard !splits.isEmpty else { throw EntryError.missingCategory }
        var sum: Int64 = 0
        var categoryIDs = Set<UUID>()
        for split in splits {
            guard categories.contains(where: { $0.id == split.categoryID }), split.amount > 0 else {
                throw EntryError.missingCategory
            }
            guard categoryIDs.insert(split.categoryID).inserted else { throw EntryError.duplicateSplitCategory }
            let addition = sum.addingReportingOverflow(split.amount)
            guard !addition.overflow else { throw EntryError.invalidAmount }
            sum = addition.partialValue
        }
        guard sum == amount else { throw EntryError.splitMismatch }
    }
}

extension Expense {
    /// What was paid, e.g. "¥12,000"; the reporting amount when paid in the reporting currency.
    var paidText: String {
        if let originalAmount, let originalCurrency { return Money.format(originalAmount, code: originalCurrency) }
        return Money.format(amount)
    }
    /// "≈ Rp1,284,000" under a foreign amount; nil otherwise.
    var reportingNote: String? { originalCurrency == nil ? nil : "≈ " + Money.format(amount) }
}

enum EntryError: LocalizedError {
    case invalidAmount, missingCategory, invalidDate, splitMismatch, duplicateSplitCategory, ambiguousAmount, corruptStore, aggregateOverflow
    var errorDescription: String? {
        switch self {
        case .invalidAmount: "Enter an amount greater than zero."
        case .missingCategory: "Choose a category before adding."
        case .invalidDate: "Choose a valid expense date."
        case .splitMismatch: "Your category splits must equal the total."
        case .duplicateSplitCategory: "Choose each split category only once."
        case .ambiguousAmount: "Use one amount, for example Coffee 28k."
        case .corruptStore: "Some stored records could not be read. Your data has been kept intact."
        case .aggregateOverflow: "The combined spending exceeds the supported exact total. No records were changed."
        }
    }
}

enum Money {
    static let maximum: Int64 = 9_000_000_000_000_000
    /// The workspace reporting currency, kept in sync by AppModel.
    /// ponytail: one global default for ~95 format/parse call sites; pass `code:` where a card or expense currency applies.
    nonisolated(unsafe) static var reportingCurrency = "IDR"

    /// Common choices first in pickers; any ISO code the rate source knows also works.
    static let commonCurrencies = ["IDR", "USD", "SGD", "JPY", "EUR", "MYR", "THB", "AUD", "GBP", "KRW", "CNY", "HKD"]

    /// Digits after the decimal point people type for this currency. Rupiah, yen and won are whole.
    static func fractionDigits(_ code: String) -> Int {
        if ["IDR", "JPY", "KRW", "VND", "CLP", "ISK", "HUF", "TWD"].contains(code) { return 0 }
        let formatter = NumberFormatter(); formatter.numberStyle = .currency; formatter.currencyCode = code
        return min(2, formatter.maximumFractionDigits)
    }

    static func symbol(_ code: String) -> String {
        if code == "IDR" { return "Rp" }
        let formatter = NumberFormatter(); formatter.numberStyle = .currency; formatter.currencyCode = code
        formatter.locale = Locale(identifier: "en_US")
        return formatter.currencySymbol ?? code
    }

    /// Converts minor units at `rate` (target units per one source unit), rounded to what the target currency shows.
    static func convert(_ amount: Int64, rate: Decimal, to code: String) throws -> Int64 {
        guard rate > 0 else { throw EntryError.invalidAmount }
        var major = Decimal(amount) / 100 * rate
        var rounded = Decimal()
        NSDecimalRound(&rounded, &major, fractionDigits(code), .plain)
        let minor = rounded * 100
        guard minor > 0, minor <= Decimal(maximum) else { throw EntryError.invalidAmount }
        return NSDecimalNumber(decimal: minor).int64Value
    }

    /// Rough units per US dollar, only to scale the Sample card's made-up amounts into a new workspace's currency.
    static let roughPerUSD: [String: Decimal] = [
        "IDR": 16_000, "JPY": 150, "KRW": 1_400, "VND": 25_000, "INR": 85, "THB": 35, "PHP": 57, "MYR": 4.5, "CNY": 7.2,
        "HKD": 7.8, "TWD": 32, "SGD": 1.35, "AUD": 1.5, "NZD": 1.7, "CAD": 1.4, "GBP": 0.8, "EUR": 0.92, "CHF": 0.88,
        "SEK": 10.5, "NOK": 10.7, "DKK": 6.9, "PLN": 4, "CZK": 23, "HUF": 360, "TRY": 34, "ILS": 3.7, "AED": 3.67,
        "SAR": 3.75, "MXN": 18, "BRL": 5.5, "CLP": 950, "COP": 4_100, "ARS": 950, "ZAR": 18, "EGP": 48, "NGN": 1_500,
        "PKR": 280, "BDT": 120, "LKR": 300,
    ]
    /// ponytail: unknown currencies count as dollar-sized; good enough for sample data, never for real money.
    static func roughRate(from: String, to: String) -> Decimal { (roughPerUSD[to] ?? 1) / (roughPerUSD[from] ?? 1) }

    /// A major-unit amount from Shortcuts or chat (28000, 4.5) in minor units, rounded to the currency's decimals.
    static func minor(fromMajor major: Decimal, code: String? = nil) throws -> Int64 {
        var value = major, rounded = Decimal()
        NSDecimalRound(&rounded, &value, fractionDigits(code ?? reportingCurrency), .plain)
        guard rounded > 0, rounded * 100 <= Decimal(maximum) else { throw EntryError.invalidAmount }
        return NSDecimalNumber(decimal: rounded * 100).int64Value
    }

    /// ISO 4217 shape: three uppercase ASCII letters.
    static func isCurrencyCode(_ code: String) -> Bool {
        code.count == 3 && code.unicodeScalars.allSatisfy { ("A"..."Z").contains($0) }
    }
    static func parse(_ input: String, locale: Locale = .autoupdatingCurrent, code: String? = nil) throws -> Int64 {
        let code = code ?? reportingCurrency
        let cents = fractionDigits(code) > 0
        var value = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for prefix in ["rp", code.lowercased(), symbol(code).lowercased()] where !prefix.isEmpty && value.hasPrefix(prefix) {
            value = String(value.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces); break
        }
        let thousands = value.hasSuffix("k")
        if thousands { value.removeLast() }
        let decimalSeparator = locale.decimalSeparator ?? "."
        let groupingSeparator = locale.groupingSeparator ?? ","
        let decimalPattern = NSRegularExpression.escapedPattern(for: decimalSeparator)
        let groupingPattern = NSRegularExpression.escapedPattern(for: groupingSeparator)
        // Validate strictly before normalization; NumberFormatter alone accepts malformed grouping.
        let pattern = thousands ? "^[0-9]+(?:" + decimalPattern + "[0-9]{1,3})?$"
            : "^(?:[0-9]+|[0-9]{1,3}(?:" + groupingPattern + "[0-9]{3})+)(?:" + decimalPattern + (cents ? "[0-9]{1,2}" : "0{1,2}") + ")?$"
        guard value.range(of: pattern, options: .regularExpression) != nil else { throw EntryError.invalidAmount }
        if !thousands { value = value.replacingOccurrences(of: groupingSeparator, with: "") }
        value = value.replacingOccurrences(of: decimalSeparator, with: ".")
        guard var decimal = Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")) else { throw EntryError.invalidAmount }
        if thousands { decimal *= 1000 }
        var rounded = Decimal()
        NSDecimalRound(&rounded, &decimal, cents ? 2 : 0, .plain)
        guard rounded == decimal, decimal > 0, decimal <= Decimal(maximum / 100) else { throw EntryError.invalidAmount }
        return NSDecimalNumber(decimal: decimal * 100).int64Value
    }

    /// Every admitted workspace must have a representable exact total, including all cards.
    static func checkedSum<S: Sequence>(_ amounts: S) throws -> Int64 where S.Element == Int64 {
        var total: Int64 = 0
        for amount in amounts {
            let next = total.addingReportingOverflow(amount)
            guard !next.overflow else { throw EntryError.aggregateOverflow }
            total = next.partialValue
        }
        return total
    }

    /// For subsets of the validated/admitted workspace only. Broken invariants must never
    /// produce a plausible rounded or clipped financial total.
    static func sum<S: Sequence>(_ amounts: S) -> Int64 where S.Element == Int64 {
        do { return try checkedSum(amounts) }
        catch { preconditionFailure("Financial aggregate admission invariant violated") }
    }

    /// Decimal avoids intermediate multiplication overflow; forecasts truncate to minor units.
    static func checkedScale(_ amount: Int64, numerator: Int, denominator: Int = 1) throws -> Int64 {
        guard denominator > 0, numerator >= 0 else { throw EntryError.aggregateOverflow }
        var value = Decimal(amount) * Decimal(numerator) / Decimal(denominator)
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, 0, .down)
        guard rounded >= Decimal(Int64.min), rounded <= Decimal(Int64.max) else { throw EntryError.aggregateOverflow }
        return NSDecimalNumber(decimal: rounded).int64Value
    }

    /// Locale-independent reversible CSV/historical-edit representation, in major units.
    static func exactDigits(_ amount: Int64) -> String {
        let whole = amount / 100
        let fraction = abs(amount % 100)
        let prefix = amount < 0 && whole == 0 ? "-0" : String(whole)
        return fraction == 0 ? String(whole) : "\(prefix).\(String(format: "%02d", fraction))"
    }

    /// CSV accepts exact cents; manual capture goes through `parse`, at the currency's decimals.
    static func parseExact(_ input: String) throws -> Int64 {
        guard input.range(of: "^[0-9]+(?:\\.[0-9]{1,2})?$", options: .regularExpression) != nil,
              let amount = Decimal(string: input, locale: Locale(identifier: "en_US_POSIX")),
              amount > 0, amount * 100 <= Decimal(maximum) else { throw EntryError.invalidAmount }
        return NSDecimalNumber(decimal: amount * 100).int64Value
    }

    static func digits(_ amount: Int64) -> String { String(amount / 100) }

    /// Amount text as people type it: thousands grouped, decimals only once typed (and only where the currency has them).
    /// Anything else, like `28k` or `Rp28.000`, is left as typed for `parse`.
    static func groupedInput(_ text: String, locale: Locale = .autoupdatingCurrent, code: String? = nil) -> String {
        let decimal = locale.decimalSeparator ?? ".", group = locale.groupingSeparator ?? ","
        let parts = text.replacingOccurrences(of: group, with: "").replacingOccurrences(of: " ", with: "").components(separatedBy: decimal)
        guard parts.count <= 2, parts.allSatisfy({ $0.allSatisfy { $0.isASCII && $0.isNumber } }) else { return text }
        var whole = ""
        for (offset, digit) in parts[0].reversed().enumerated() {
            if offset > 0, offset % 3 == 0 { whole = group + whole }
            whole = String(digit) + whole
        }
        let places = fractionDigits(code ?? reportingCurrency)
        guard parts.count == 2, places > 0 else { return whole }
        return whole + decimal + parts[1].prefix(places)
    }
    static func format(_ amount: Int64, currency: Bool = true, locale: Locale = .autoupdatingCurrent, code: String? = nil) -> String {
        let value = Decimal(amount) / 100
        let number = value.formatted(.number.locale(locale).precision(.fractionLength(0...(amount % 100 == 0 ? 0 : 2))))
        return (currency ? symbol(code ?? reportingCurrency) : "") + number
    }
}

enum Day {
    /// Stored days always use Gregorian civil dates; reporting follows the local time zone.
    static var calendar: Calendar { reportingCalendar(.current) }
    static func reportingCalendar(_ input: Calendar) -> Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = input.timeZone
        result.locale = input.locale
        result.firstWeekday = input.firstWeekday
        return result
    }
    static func string(_ date: Date, calendar: Calendar = Day.calendar) -> String {
        let calendar = reportingCalendar(calendar)
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 2000, parts.month ?? 1, parts.day ?? 1)
    }
    static func date(_ value: String, calendar: Calendar = Day.calendar) -> Date? {
        let calendar = reportingCalendar(calendar)
        let parts = value.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, value.count == 10,
              let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12)),
              string(date, calendar: calendar) == value else { return nil }
        return date
    }
    static func title(_ value: String) -> String {
        guard let date = date(value) else { return value }
        if Calendar.current.isDateInToday(date) { return "Today" }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.day().month(.wide))
    }
}

struct DraftSplit: Identifiable, Codable, Equatable {
    var id = UUID()
    var categoryID: UUID
    var amount: String
    /// Only unchanged accepted historical input may retain fractional minor units.
    var preservedAmount: Int64? = nil
    func resolvedAmount(code: String? = nil) throws -> Int64 {
        if let preservedAmount, preservedAmount > 0, preservedAmount <= Money.maximum,
           amount == Money.exactDigits(preservedAmount) { return preservedAmount }
        return try Money.parse(amount, code: code)
    }
}

struct ExpenseDraft: Codable, Equatable {
    var id = UUID()
    var cardID: UUID?
    var amount = ""
    var categoryID: UUID?
    var note = ""
    var date = Date.now {
        didSet { civilDay = Day.string(date) }
    }
    var civilDay = Day.string(.now)
    var preservedAmount: Int64? = nil
    var editing = false
    var createdAt = Date.now
    var source = "manual"
    /// Empty keeps the original one-category path; nonempty is the advanced split editor.
    var splitParts: [DraftSplit] = []
    var paidWithID: UUID? = nil
    /// The currency typed amounts are in; nil means the reporting currency.
    var currency: String? = nil
    /// Reporting units per one `currency` unit, as typed or fetched; needed when `currency` is foreign.
    var rate = ""
    var rateSource: Expense.RateSource? = nil
    var isSplit: Bool { !splitParts.isEmpty }
    func isForeign(reporting: String = Money.reportingCurrency) -> Bool { currency.map { $0 != reporting } ?? false }
    var hasContent: Bool { !amount.isEmpty || !note.isEmpty || categoryID != nil || !splitParts.isEmpty }
    func resolvedAmount() throws -> Int64 {
        if let preservedAmount, preservedAmount > 0, preservedAmount <= Money.maximum,
           amount == Money.exactDigits(preservedAmount) { return preservedAmount }
        return try Money.parse(amount, code: currency)
    }
    func resolvedAllocatedAmount() throws -> Int64 {
        try Money.checkedSum(splitParts.map { $0.amount.isEmpty ? 0 : try $0.resolvedAmount(code: currency) })
    }
    /// The typed amount in the reporting currency. Needs only an amount and a rate, so it can show before a category is chosen.
    func reportingEquivalent(reporting: String = Money.reportingCurrency) -> Int64? {
        guard isForeign(reporting: reporting), let rate = resolvedRate(), let value = try? resolvedAmount() else { return nil }
        return try? Money.convert(value, rate: rate, to: reporting)
    }
    func resolvedRate() -> Decimal? {
        Decimal(string: rate.replacingOccurrences(of: ",", with: "."), locale: Locale(identifier: "en_US_POSIX")).flatMap { $0 > 0 ? $0 : nil }
    }
    /// Amounts are typed in `currency`; a foreign expense is converted to the reporting currency and keeps its original amount.
    func expense(reporting: String = Money.reportingCurrency) throws -> Expense {
        let value = try resolvedAmount()
        var splits: [Split]
        if splitParts.isEmpty {
            guard let categoryID else { throw EntryError.missingCategory }
            splits = [.init(categoryID: categoryID, amount: value)]
        } else {
            guard splitParts.count > 1 else { throw EntryError.splitMismatch }
            splits = try splitParts.map { split in
                let value = try split.resolvedAmount(code: currency)
                return .init(categoryID: split.categoryID, amount: value)
            }
        }
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isForeign(reporting: reporting), let currency else {
            return Expense(id: id, amount: value, day: civilDay, note: trimmedNote, splits: splits, source: source, createdAt: createdAt, cardID: cardID,
                           paidWithID: paidWithID)
        }
        guard let rateValue = resolvedRate() else { throw RateError.unavailable }
        guard try Money.checkedSum(splits.map(\.amount)) == value else { throw EntryError.splitMismatch }
        let converted = try Money.convert(value, rate: rateValue, to: reporting)
        splits = try Self.convert(splits, rate: rateValue, total: converted, to: reporting)
        return Expense(id: id, amount: converted, day: civilDay, note: trimmedNote, splits: splits, source: source, createdAt: createdAt, cardID: cardID,
                       paidWithID: paidWithID, originalAmount: value, originalCurrency: currency, rate: "\(rateValue)", rateSource: rateSource ?? .manual)
    }

    /// Converts each split part and gives any rounding difference to the largest part, so parts still add up exactly.
    static func convert(_ splits: [Split], rate: Decimal, total: Int64, to code: String) throws -> [Split] {
        guard splits.count > 1 else { return splits.map { .init(categoryID: $0.categoryID, amount: total) } }
        var parts = try splits.map { Split(categoryID: $0.categoryID, amount: try Money.convert($0.amount, rate: rate, to: code)) }
        let difference = total - Money.sum(parts.map(\.amount))
        if let largest = parts.indices.max(by: { parts[$0].amount < parts[$1].amount }) { parts[largest].amount += difference }
        guard parts.allSatisfy({ $0.amount > 0 }) else { throw EntryError.splitMismatch }
        return parts
    }
    init() {}
    init(expense: Expense) {
        id = expense.id; cardID = expense.cardID; amount = Money.exactDigits(expense.amount); preservedAmount = expense.amount; categoryID = expense.splits.first?.categoryID
        note = expense.note; date = Day.date(expense.day) ?? .now; civilDay = expense.day; editing = true; createdAt = expense.createdAt; source = expense.source
        paidWithID = expense.paidWithID
        if let original = expense.originalAmount, let currency = expense.originalCurrency, let rate = expense.rate {
            // Edit in the currency it was paid in; split parts go back by their share of the total.
            self.currency = currency; self.rate = rate; rateSource = expense.rateSource
            amount = Money.exactDigits(original); preservedAmount = original
            if expense.splits.count > 1 {
                let unit: Int64 = Money.fractionDigits(currency) == 0 ? 100 : 1 // whole yen, cents for dollars
                var parts = expense.splits.map { part in
                    let scaled = (try? Money.checkedScale(original, numerator: Int(truncatingIfNeeded: part.amount), denominator: Int(truncatingIfNeeded: expense.amount))) ?? 0
                    return Split(categoryID: part.categoryID, amount: (scaled + unit / 2) / unit * unit)
                }
                let difference = original - Money.sum(parts.map(\.amount))
                if let largest = parts.indices.max(by: { parts[$0].amount < parts[$1].amount }) { parts[largest].amount += difference }
                splitParts = parts.map { .init(categoryID: $0.categoryID, amount: Money.exactDigits($0.amount), preservedAmount: $0.amount) }
            }
        } else if expense.splits.count > 1 {
            splitParts = expense.splits.map { .init(categoryID: $0.categoryID, amount: Money.exactDigits($0.amount), preservedAmount: $0.amount) }
        }
    }

    private enum CodingKeys: String, CodingKey { case id, cardID = "bookID", amount, categoryID, note, date, editing, createdAt, source, splitParts = "splitAllocations", civilDay, preservedAmount, paidWithID, currency, rate, rateSource }
    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        cardID = try values.decodeIfPresent(UUID.self, forKey: .cardID)
        amount = try values.decodeIfPresent(String.self, forKey: .amount) ?? ""
        categoryID = try values.decodeIfPresent(UUID.self, forKey: .categoryID)
        note = try values.decodeIfPresent(String.self, forKey: .note) ?? ""
        let legacyDate = try values.decodeIfPresent(Date.self, forKey: .date) ?? .now
        civilDay = try values.decodeIfPresent(String.self, forKey: .civilDay) ?? Day.string(legacyDate)
        guard let restoredDate = Day.date(civilDay) else { throw EntryError.invalidDate }
        date = restoredDate
        preservedAmount = try values.decodeIfPresent(Int64.self, forKey: .preservedAmount)
        editing = try values.decodeIfPresent(Bool.self, forKey: .editing) ?? false
        createdAt = try values.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
        source = try values.decodeIfPresent(String.self, forKey: .source) ?? "manual"
        splitParts = try values.decodeIfPresent([DraftSplit].self, forKey: .splitParts) ?? []
        paidWithID = try values.decodeIfPresent(UUID.self, forKey: .paidWithID)
        currency = try values.decodeIfPresent(String.self, forKey: .currency)
        rate = try values.decodeIfPresent(String.self, forKey: .rate) ?? ""
        rateSource = try values.decodeIfPresent(Expense.RateSource.self, forKey: .rateSource)
    }
    func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id); try values.encodeIfPresent(cardID, forKey: .cardID); try values.encode(amount, forKey: .amount)
        try values.encodeIfPresent(categoryID, forKey: .categoryID); try values.encode(note, forKey: .note)
        try values.encode(date, forKey: .date)
        try values.encode(editing, forKey: .editing); try values.encode(createdAt, forKey: .createdAt); try values.encode(source, forKey: .source)
        try values.encode(splitParts, forKey: .splitParts)
        try values.encodeIfPresent(paidWithID, forKey: .paidWithID); try values.encodeIfPresent(currency, forKey: .currency)
        try values.encode(rate, forKey: .rate); try values.encodeIfPresent(rateSource, forKey: .rateSource)
        try values.encode(civilDay, forKey: .civilDay); try values.encodeIfPresent(preservedAmount, forKey: .preservedAmount)
    }

    static func == (lhs: ExpenseDraft, rhs: ExpenseDraft) -> Bool {
        lhs.id == rhs.id &&
        lhs.amount == rhs.amount &&
        lhs.categoryID == rhs.categoryID &&
        lhs.note == rhs.note &&
        lhs.civilDay == rhs.civilDay &&
        lhs.preservedAmount == rhs.preservedAmount &&
        lhs.editing == rhs.editing &&
        lhs.createdAt == rhs.createdAt &&
        lhs.source == rhs.source &&
        lhs.splitParts == rhs.splitParts &&
        lhs.paidWithID == rhs.paidWithID &&
        lhs.currency == rhs.currency && lhs.rate == rhs.rate && lhs.rateSource == rhs.rateSource &&
        (lhs.cardID == nil || rhs.cardID == nil || lhs.cardID == rhs.cardID)
    }
}

struct ParsedExpense {
    var amount: Int64
    var note: String
    var categoryID: UUID?
}

enum ExpenseParser {
    static let keywords = [
        0: ["coffee", "kopi", "lunch", "dinner", "breakfast", "food", "makan"],
        1: ["grab", "gojek", "taxi", "parking", "petrol"],
        2: ["shopping", "shirt", "shoes"],
        3: ["rent", "internet", "electricity", "groceries"],
        4: ["gym", "doctor", "medicine"],
        5: ["cinema", "movie", "netflix"]
    ]
    static func parse(_ text: String, categories: [ExpenseCategory], rules: [CategoryRule] = []) throws -> ParsedExpense {
        let tokens = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        let numberTokens = tokens.enumerated().filter { $0.element.contains(where: { $0.isNumber }) }
        guard numberTokens.count == 1, let token = numberTokens.first else { throw EntryError.ambiguousAmount }
        let amount = try Money.parse(token.element)
        let words = tokens.enumerated().filter { $0.offset != token.offset }.map(\.element)
        let customMatches = Set(rules.filter { rule in words.contains { $0.lowercased() == rule.keyword } }.map(\.categoryID))
        let matches = keywords.filter { _, keys in words.contains { keys.contains($0.lowercased()) } }.keys
        let categoryID: UUID? = customMatches.count == 1 ? customMatches.first : (customMatches.isEmpty && matches.count == 1 ? ExpenseCategory.defaults[matches.first!].id : nil)
        return ParsedExpense(amount: amount, note: words.joined(separator: " "), categoryID: categories.first(where: { $0.id == categoryID })?.id)
    }
}

struct Cycle: Equatable, Sendable {
    let start: Date
    let end: Date
    let calendar: Calendar
    init(start: Date, end: Date, calendar: Calendar = Day.calendar) {
        self.calendar = Day.reportingCalendar(calendar)
        self.start = self.calendar.startOfDay(for: start)
        self.end = self.calendar.startOfDay(for: end)
    }
    static func containing(_ date: Date, startDay: Int, calendar: Calendar = Day.calendar) -> Self {
        let calendar = Day.reportingCalendar(calendar)
        let date = calendar.startOfDay(for: date)
        let day = min(31, max(1, startDay))
        let month = calendar.dateInterval(of: .month, for: date)!.start
        func boundary(_ month: Date) -> Date {
            let days = calendar.range(of: .day, in: .month, for: month)!.count
            return calendar.date(byAdding: .day, value: min(day, days) - 1, to: month)!
        }
        let current = boundary(month)
        if date >= current {
            return .init(start: current, end: boundary(calendar.date(byAdding: .month, value: 1, to: month)!), calendar: calendar)
        }
        return .init(start: boundary(calendar.date(byAdding: .month, value: -1, to: month)!), end: current, calendar: calendar)
    }
    func contains(_ expense: Expense) -> Bool {
        guard Day.date(expense.day, calendar: calendar) != nil else { return false }
        return expense.day >= Day.string(start, calendar: calendar) && expense.day < Day.string(end, calendar: calendar)
    }
    var label: String {
        let last = calendar.date(byAdding: .day, value: -1, to: end) ?? end
        return start.formatted(.dateTime.day().month(.abbreviated)) + " – " + last.formatted(.dateTime.day().month(.abbreviated))
    }
}

struct CategoryBudget: Codable, Equatable, Sendable {
    var categoryID: UUID
    var limit: Int64
}

struct BudgetVersion: Identifiable, Codable, Equatable, Sendable {
    static let legacyID = UUID(uuidString: "40000000-0000-0000-0000-000000000001")!

    var id = UUID()
    var effectiveDay: String
    var overallLimit: Int64
    var startDay: Int
    var categoryLimits: [CategoryBudget] = []
    /// Set only for the first period after a start-day change.
    var transitionEndDay: String?
    var cardID: UUID? = nil
    /// Set for a "Total until" budget (a goal): one period from effectiveDay up to and including this day.
    var totalUntilDay: String? = nil
    // Stored keys keep their pre-rename names so existing backups, drafts and settings still load.
    private enum CodingKeys: String, CodingKey {
        case id, effectiveDay, overallLimit, startDay, categoryLimits, transitionEndDay, cardID = "bookID", totalUntilDay
    }

    static func initial(overallLimit: Int64, startDay: Int, date: Date = .now, calendar: Calendar = Day.calendar, cardID: UUID? = nil) -> Self {
        let validStartDay = min(31, max(1, startDay))
        let cycle = Cycle.containing(date, startDay: validStartDay, calendar: calendar)
        let id = (cardID == nil || cardID == Card.demo.id) ? legacyID : UUID()
        return .init(id: id, effectiveDay: Day.string(cycle.start, calendar: calendar),
                     overallLimit: max(1, min(Money.maximum, overallLimit)), startDay: validStartDay,
                     categoryLimits: [], transitionEndDay: nil, cardID: cardID)
    }

    func validate(categories: [ExpenseCategory]) throws {
        guard overallLimit > 0, overallLimit <= Money.maximum else { throw BudgetError.invalidLimit }
        guard (1...31).contains(startDay), Day.date(effectiveDay) != nil else { throw BudgetError.invalidEffectiveDate }
        if let transitionEndDay {
            guard let start = Day.date(effectiveDay), let end = Day.date(transitionEndDay), end > start else {
                throw BudgetError.invalidTransition
            }
        }
        if let totalUntilDay {
            guard Day.date(totalUntilDay) != nil, totalUntilDay >= effectiveDay else { throw BudgetError.invalidEffectiveDate }
        }
        var categoryIDs = Set<UUID>()
        for categoryLimit in categoryLimits {
            guard categories.contains(where: { $0.id == categoryLimit.categoryID }) else { throw BudgetError.missingCategory }
            guard categoryLimit.limit > 0, categoryLimit.limit <= Money.maximum else { throw BudgetError.invalidLimit }
            guard categoryIDs.insert(categoryLimit.categoryID).inserted else { throw BudgetError.duplicateCategory }
        }
    }

    func limit(for categoryID: UUID) -> Int64? {
        categoryLimits.first { $0.categoryID == categoryID }?.limit
    }

    static func == (lhs: BudgetVersion, rhs: BudgetVersion) -> Bool {
        lhs.id == rhs.id &&
        lhs.effectiveDay == rhs.effectiveDay &&
        lhs.overallLimit == rhs.overallLimit &&
        lhs.startDay == rhs.startDay &&
        lhs.categoryLimits == rhs.categoryLimits &&
        lhs.transitionEndDay == rhs.transitionEndDay &&
        lhs.totalUntilDay == rhs.totalUntilDay &&
        (lhs.cardID == nil || rhs.cardID == nil || lhs.cardID == rhs.cardID)
    }
}

struct BudgetPeriod: Equatable, Sendable {
    let budget: BudgetVersion
    let cycle: Cycle
    var isTransition: Bool { budget.transitionEndDay == Day.string(cycle.end, calendar: cycle.calendar) }
}

enum BudgetHistory {
    static func active(on date: Date, budgets: [BudgetVersion], calendar: Calendar = Day.calendar) -> BudgetVersion? {
        let day = Day.string(date, calendar: calendar)
        // A "Total until" budget ends after its last day; the cycle budget before it (if any) applies again.
        return budgets.filter { $0.effectiveDay <= day && ($0.totalUntilDay.map { $0 >= day } ?? true) }.max { $0.effectiveDay < $1.effectiveDay }
    }

    static func period(containing date: Date, budgets: [BudgetVersion], calendar: Calendar = Day.calendar) -> BudgetPeriod? {
        guard let budget = active(on: date, budgets: budgets, calendar: calendar) else { return nil }
        let day = Day.string(date, calendar: calendar)
        // A "Total until" budget is one period from its start through its last day.
        if let lastDay = budget.totalUntilDay, let start = Day.date(budget.effectiveDay, calendar: calendar),
           let last = Day.date(lastDay, calendar: calendar) {
            let reporting = Day.reportingCalendar(calendar)
            let end = reporting.date(byAdding: .day, value: 1, to: reporting.startOfDay(for: last)) ?? last
            return BudgetPeriod(budget: budget, cycle: Cycle(start: reporting.startOfDay(for: start), end: end, calendar: calendar))
        }
        if let start = Day.date(budget.effectiveDay, calendar: calendar),
           let endDay = budget.transitionEndDay, let end = Day.date(endDay, calendar: calendar),
           day >= budget.effectiveDay, day < endDay {
            return BudgetPeriod(budget: budget, cycle: Cycle(start: Day.reportingCalendar(calendar).startOfDay(for: start), end: Day.reportingCalendar(calendar).startOfDay(for: end), calendar: calendar))
        }
        return BudgetPeriod(budget: budget, cycle: Cycle.containing(date, startDay: budget.startDay, calendar: calendar))
    }

    static func transitionEnd(after date: Date, startDay: Int, calendar: Calendar = Day.calendar) -> Date {
        Cycle.containing(date, startDay: startDay, calendar: calendar).end
    }
}

enum BudgetError: LocalizedError {
    case invalidLimit, invalidEffectiveDate, invalidTransition, missingCategory, duplicateCategory

    var errorDescription: String? {
        switch self {
        case .invalidLimit: "Enter a valid budget greater than zero."
        case .invalidEffectiveDate: "The budget cycle date is invalid."
        case .invalidTransition: "The budget transition period is invalid."
        case .missingCategory: "A category budget refers to a missing category."
        case .duplicateCategory: "A category can have only one budget limit."
        }
    }
}
