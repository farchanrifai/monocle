import Foundation

/// Daily reference rates: target units per one source unit, keyed by civil day ("yyyy-MM-dd").
protocol RateSource: Sendable {
    func rates(from: String, to: String, start: String, end: String) async throws -> [String: Decimal]
}

/// Frankfurter serves European Central Bank reference rates for working days. The only data request that is always
/// available (AI chat is opt-in): it sends two currency codes and dates, nothing about expenses. See docs/privacy.md.
struct FrankfurterRateSource: RateSource {
    var session: URLSession = .shared

    func rates(from: String, to: String, start: String, end: String) async throws -> [String: Decimal] {
        guard let url = URL(string: "https://api.frankfurter.dev/v1/\(start)..\(end)?base=\(from)&symbols=\(to)") else { throw RateError.unavailable }
        let (data, response) = try await session.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw RateError.unavailable }
        struct Body: Decodable { let rates: [String: [String: Decimal]] }
        return try JSONDecoder().decode(Body.self, from: data).rates.compactMapValues { $0[to] }
    }
}

enum RateError: LocalizedError {
    case unavailable
    var errorDescription: String? { "The exchange rate isn't available right now. Enter the rate yourself, or try again when you're online." }
}

/// Caches every fetched day on disk. A day without a published rate (weekend, holiday, today
/// before publication) uses the nearest earlier day, as the bank would.
@MainActor
final class ExchangeRates {
    static let shared = ExchangeRates()
    private let source: any RateSource
    private let fileURL: URL?
    private var cache: [String: [String: Decimal]] // "JPY>IDR" → day → rate

    init(source: any RateSource = FrankfurterRateSource(), fileURL: URL? = ExchangeRates.defaultURL) {
        self.source = source; self.fileURL = fileURL
        cache = fileURL.flatMap { try? Data(contentsOf: $0) }.flatMap { try? JSONDecoder().decode([String: [String: Decimal]].self, from: $0) } ?? [:]
    }

    nonisolated static var defaultURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("exchange-rates.json")
    }

    /// Cached rate for the day or the nearest earlier cached day within a week; nil means fetch.
    func cachedRate(from: String, to: String, on day: String) -> Decimal? {
        if from == to { return 1 }
        guard let days = cache["\(from)>\(to)"], let start = Self.shift(day, by: -7) else { return nil }
        return days.filter { $0.key <= day && $0.key >= start }.max { $0.key < $1.key }?.value
    }

    func rate(from: String, to: String, on day: String) async throws -> Decimal {
        if let cached = cachedRate(from: from, to: to, on: day) { return cached }
        try await prefetch(from: from, to: to, start: day, end: day)
        guard let rate = cachedRate(from: from, to: to, on: day) else { throw RateError.unavailable }
        return rate
    }

    /// One request covers a whole range of days; used when converting history.
    func prefetch(from: String, to: String, start: String, end: String) async throws {
        guard from != to, let padded = Self.shift(start, by: -7) else { return }
        let fetched = try await source.rates(from: from, to: to, start: padded, end: end)
        cache["\(from)>\(to)", default: [:]].merge(fetched) { _, new in new }
        if let fileURL, let data = try? JSONEncoder().encode(cache) {
            try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    private static func shift(_ day: String, by days: Int) -> String? {
        guard let date = Day.date(day), let moved = Day.calendar.date(byAdding: .day, value: days, to: date) else { return nil }
        return Day.string(moved)
    }
}
