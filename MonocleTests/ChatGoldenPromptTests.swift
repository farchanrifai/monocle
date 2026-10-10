import XCTest
@testable import Monocle

/// CHAT_SPEC §10 golden prompts against the real API. Manual, not per commit: skipped unless a key is set.
///   TEST_RUNNER_ANTHROPIC_API_KEY=sk-ant-... xcodebuild test ... -only-testing:MonocleTests/ChatGoldenPromptTests
/// Prints every reply plus token usage, so cache reads can be checked by eye.
@MainActor
final class ChatGoldenPromptTests: XCTestCase {
    private var model: AppModel!
    private var repo: ExpenseRepository!
    private var tempDir: URL!
    private var client: ClaudeClient!
    private var usage: [(input: Int, write: Int, read: Int)] = []
    private let now = Date.now

    override func setUp() async throws {
        repo = try ExpenseRepository(inMemory: true)
        let daily = try repo.createBook(named: "Daily")
        let categories = try repo.categories(in: daily.id)
        let food = try XCTUnwrap(categories.first { $0.name == "Food & Drink" })
        let transport = try XCTUnwrap(categories.first { $0.name == "Transport" })
        for (rupiah, daysAgo, note, category) in [(45_000, 0, "Lunch", food), (28_000, 1, "Kopi", food), (100_000, 3, "Bensin", transport),
                                                  (60_000, 35, "Makan malam", food), (50_000, 40, "Parkir", transport)] {
            let minor = Int64(rupiah) * 100
            let day = Day.string(Day.calendar.date(byAdding: .day, value: -daysAgo, to: now)!)
            try repo.save(Expense(amount: minor, day: day, note: note, allocations: [.init(categoryID: category.id, amount: minor)],
                                  bookID: daily.id), in: daily.id)
        }
        var budget = BudgetVersion.initial(overallLimit: 3_000_000_00, startDay: 1, date: now, bookID: daily.id)
        budget.categoryLimits = [CategoryBudget(categoryID: food.id, limit: 50_000_00)]
        try repo.save(budget, in: daily.id)

        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        model = AppModel(expenses: try ExpenseService(store: repo), state: FileLocalStateStore(directory: tempDir))
        try model.reload()

        // Skip after seeding so the fixture is still exercised on keyless runs.
        let key = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] ?? ""
        try XCTSkipIf(key.isEmpty, "Set TEST_RUNNER_ANTHROPIC_API_KEY to run golden prompts against the real API.")
        client = ClaudeClient(apiKey: key)
    }

    override func tearDown() async throws {
        if !usage.isEmpty {
            print("GOLDEN usage per request (input / cache write / cache read):")
            usage.forEach { print("  \($0.input) / \($0.write) / \($0.read)") }
        }
        if let tempDir { try? FileManager.default.removeItem(at: tempDir) }
    }

    func testCapturePrompts() async throws {
        let coffee = await ask("coffee 28k")
        XCTAssertEqual(proposals(coffee).map(\.amount), [2_800_000])

        let fuel = await ask("bensin 100rb kemarin")
        XCTAssertEqual(proposals(fuel).map(\.amount), [10_000_000])
        XCTAssertEqual(proposals(fuel).first?.day, Day.string(Day.calendar.date(byAdding: .day, value: -1, to: now)!))

        let two = await ask("lunch 45k and parking 5k")
        XCTAssertEqual(Set(proposals(two).map(\.amount)), [4_500_000, 500_000])

        let zero = await ask("add 0")
        XCTAssertTrue(proposals(zero).isEmpty, "A zero expense must never reach a confirm card")

        let market = await ask("pasar 50rb: 30rb makan 20rb belanja")
        XCTAssertEqual(proposals(market).map { $0.allocations.map(\.amount) }, [[3_000_000, 2_000_000]], "One split expense")

        let big = await ask("add 10 juta")
        // Claude may ask for a category instead; if it proposes, the card must read Rp10.000.000.
        XCTAssertTrue(proposals(big).allSatisfy { $0.amount == 1_000_000_000 }, "\(big)")
    }

    func testQuestionPrompts() async throws {
        for prompt in ["berapa pengeluaran makan bulan ini?", "compare this month vs last", "am I over budget?", "show all cards this month"] {
            let outputs = await ask(prompt)
            XCTAssertFalse(outputs.contains { if case .error = $0 { true } else { false } }, "\(prompt): \(outputs)")
            XCTAssertTrue(proposals(outputs).isEmpty, "\(prompt) must not propose an expense")
        }
    }

    func testEditAndDeleteOnlyPropose() async throws {
        let bookID = try XCTUnwrap(model.books.first?.id)
        let before = model.expenses(for: bookID)
        let delete = await ask("delete my last expense")
        let deletes = changes(delete).filter { $0.updated == nil }
        XCTAssertEqual(deletes.map(\.original.note), ["Lunch"], "Newest expense, shown as a confirm card")

        let edit = await ask("ubah kopi kemarin jadi 30rb")
        XCTAssertEqual(changes(edit).compactMap(\.updated).map(\.amount), [3_000_000])
        XCTAssertEqual(model.expenses(for: bookID), before, "Nothing changes until the user confirms")
    }

    /// Fresh agent per prompt so each golden prompt is judged on its own.
    private func ask(_ prompt: String) async -> [ChatAgent.Output] {
        let agent = ChatAgent(model: model) { [client] body in
            let data = try await client!.send(body)
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let u = json?["usage"] as? [String: Any] ?? [:]
            await MainActor.run {
                self.usage.append((u["input_tokens"] as? Int ?? 0, u["cache_creation_input_tokens"] as? Int ?? 0,
                                   u["cache_read_input_tokens"] as? Int ?? 0))
            }
            return data
        }
        let outputs = await agent.send(prompt, scope: .allCards, now: now)
        print("GOLDEN » \(prompt)")
        outputs.forEach { print("  \($0)") }
        return outputs
    }

    private func changes(_ outputs: [ChatAgent.Output]) -> [ExpenseChange] {
        outputs.compactMap { if case .change(let c) = $0 { c } else { nil } }
    }

    private func proposals(_ outputs: [ChatAgent.Output]) -> [Expense] {
        outputs.compactMap { if case .proposal(let e) = $0 { e } else { nil } }
    }
}
