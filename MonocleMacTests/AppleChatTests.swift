import FoundationModels
import SwiftUI
import XCTest
@testable import MonocleMac

/// Apple Intelligence chat: every Claude tool schema converts, and (when the model is available on this Mac)
/// the CHAT_SPEC golden prompts run on-device. The probe prints each reply so it can be compared by eye.
@MainActor
final class AppleChatTests: XCTestCase {
    func testEveryToolSchemaConverts() throws {
        XCTAssertEqual(ChatAgent.tools.count, 10)
        for tool in ChatAgent.tools {
            let name = try XCTUnwrap(tool["name"] as? String)
            let schema = try XCTUnwrap(tool["input_schema"] as? [String: Any])
            XCTAssertNoThrow(try GenerationSchema(root: AppleChatAgent.schema(schema, name: name), dependencies: []), name)
            XCTAssertNoThrow(try GenerationSchema(root: AppleChatAgent.schema(schema, name: name, categories: ["Food & Drink", "Leisure"]), dependencies: []), name)
        }
    }

    func testRupiahParsing() {
        XCTAssertEqual(AppleChatAgent.rupiah("28rb"), 28_000)
        XCTAssertEqual(AppleChatAgent.rupiah("100k"), 100_000)
        XCTAssertEqual(AppleChatAgent.rupiah("1,5jt"), 1_500_000)
        XCTAssertEqual(AppleChatAgent.rupiah("2 juta"), 2_000_000)
        XCTAssertEqual(AppleChatAgent.rupiah("Rp28.000"), 28_000)
        XCTAssertEqual(AppleChatAgent.rupiah("50000"), 50_000)
        XCTAssertNil(AppleChatAgent.rupiah("kopi"))
        XCTAssertNil(AppleChatAgent.rupiah("0k"))
    }

    func testDoneClaimsBesideAPendingCardAreDropped() {
        let card: [ChatAgent.Output] = [.proposal(Expense(amount: 28_000_00, day: "2026-10-10", note: "Kopi", splits: [], cardID: UUID()))]
        XCTAssertTrue(AppleChatAgent.claimsDone("Your coffee has been updated to Rp30.000.", beside: card))
        XCTAssertTrue(AppleChatAgent.claimsDone("Kopi sudah ditambahkan.", beside: card))
        XCTAssertFalse(AppleChatAgent.claimsDone("Check the card to add it.", beside: card))
        XCTAssertFalse(AppleChatAgent.claimsDone("You added 3 expenses yesterday.", beside: []), "No card, nothing to contradict")
    }

    func testGoldenPromptsOnDevice() async throws {
        try XCTSkipIf(AppleChatAgent.unavailableReason != nil, AppleChatAgent.unavailableReason ?? "")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repo = try ExpenseRepository(inMemory: true)
        let daily = try repo.createCard(named: "Daily")
        let categories = try repo.categories(in: daily.id)
        let food = try XCTUnwrap(categories.first { $0.name == "Food & Drink" })
        let transport = try XCTUnwrap(categories.first { $0.name == "Transport" })
        let now = Date.now
        for (rupiah, daysAgo, note, category) in [(45_000, 0, "Lunch", food), (28_000, 1, "Kopi", food), (100_000, 3, "Bensin", transport),
                                                  (60_000, 35, "Makan malam", food), (50_000, 40, "Parkir", transport)] {
            let minor = Int64(rupiah) * 100
            let day = Day.string(Day.calendar.date(byAdding: .day, value: -daysAgo, to: now)!)
            try repo.save(Expense(amount: minor, day: day, note: note, splits: [.init(categoryID: category.id, amount: minor)],
                                  cardID: daily.id), in: daily.id)
        }
        let model = AppModel(expenses: try ExpenseService(store: repo), state: FileLocalStateStore(directory: directory))
        try model.reload()
        let scope = AnalyticsFilterScope.card(id: daily.id, name: daily.name)

        var budget = BudgetVersion.initial(overallLimit: 3_000_000_00, startDay: 1, date: now, cardID: daily.id)
        budget.categoryLimits = [CategoryBudget(categoryID: food.id, limit: 50_000_00)]
        try repo.save(budget, in: daily.id)
        try model.reload()
        let yesterday = Day.string(Day.calendar.date(byAdding: .day, value: -1, to: now)!)

        func expenses(_ o: [ChatAgent.Output]) -> [Expense] { o.compactMap { if case .proposal(let e) = $0 { e } else { nil } } }
        func changes(_ o: [ChatAgent.Output]) -> [ExpenseChange] { o.compactMap { if case .change(let c) = $0 { c } else { nil } } }
        func text(_ o: [ChatAgent.Output]) -> String { o.compactMap { if case .text(let t) = $0 { t } else { nil } }.joined(separator: " ") }
        // Each golden prompt with what a right answer looks like (CHAT_SPEC §10).
        let golden: [(String, ([ChatAgent.Output]) -> Bool)] = [
            ("coffee 28k", { expenses($0).map(\.amount) == [28_000_00] && expenses($0).allSatisfy { !$0.note.isEmpty } }),
            ("bensin 100rb kemarin", { expenses($0).map(\.amount) == [100_000_00] && expenses($0).first?.day == yesterday }),
            ("lunch 45k and parking 5k", { Set(expenses($0).map(\.amount)) == [45_000_00, 5_000_00] }),
            ("pasar 50rb: 30rb makan 20rb belanja", { expenses($0).map { $0.splits.map(\.amount) } == [[30_000_00, 20_000_00]] }),
            ("netflix 186rb tiap bulan tanggal 5", { o in o.contains { if case .bill(let b) = $0 { b.recurrence == .monthly(day: 5) && b.amount == 186_000_00 } else { false } } }),
            ("berapa pengeluaran makan bulan ini?", { text($0).contains("73") }),
            ("compare this month vs last", { text($0).contains("113") || (text($0).contains("173") && text($0).lowercased().contains("up")) }),
            ("am I over budget?", { text($0).contains("73") || text($0).contains("23") }),
            ("ganti kopi kemarin jadi 30rb", { changes($0).map { $0.updated?.amount } == [30_000_00] }),
            ("hapus parkir", { changes($0).map { $0.original.note } == ["Parkir"] && changes($0).first?.updated == nil }),
        ]
        var report = "APPLE GOLDEN\n"
        var proposals = 0, passed = 0
        for (prompt, isRight) in golden {
            let agent = AppleChatAgent(model: model) // fresh per prompt: the on-device context window is small
            let start = Date.now
            let outputs = await agent.send(prompt, scope: scope, now: now)
            let ok = isRight(outputs)
            passed += ok ? 1 : 0
            report += "\n\(ok ? "✓" : "✗") \(prompt)  (\(String(format: "%.1fs", Date.now.timeIntervalSince(start))))\n"
            agent.toolLog.forEach { report += "  tool: \($0)\n" }
            for output in outputs {
                switch output {
                case .text(let text): report += "  text: \(text)\n"
                case .proposal(let e): proposals += 1; report += "  proposal: \(e.amount / 100) \(e.note) \(e.day) parts=\(e.splits.map { $0.amount / 100 })\n"
                case .change(let c): report += "  change: \(c.original.note) -> \(c.updated.map { "\($0.amount / 100)" } ?? "DELETE")\n"
                case .bill(let b): report += "  bill: \(b.name) \(b.amount / 100) \(b.recurrence)\n"
                case .chart(let chart): report += "  chart: \(chart.style.rawValue) \(chart.items.count) items\n"
                case .notice(let text): report += "  notice: \(text)\n"
                case .error(let text): report += "  ERROR: \(text)\n"
                }
            }
        }
        // A follow-up conversation in one session: the last turn must break last month down by category.
        let chat = AppleChatAgent(model: model)
        var last: [ChatAgent.Output] = []
        for prompt in ["what do my expenses look like?", "how about last month?", "what categories?"] {
            last = await chat.send(prompt, scope: scope, now: now)
            report += "\n» \(prompt)\n" + chat.toolLog.suffix(2).map { "  tool: \($0.prefix(160))\n" }.joined() + "  text: \(text(last))\n"
        }
        let followUp = last.contains { if case .chart = $0 { true } else { false } } && text(last).contains("60")
        report += "\(followUp ? "✓" : "✗") follow-up keeps last month\n"
        passed += followUp ? 1 : 0
        report += "\nSCORE \(passed)/\(golden.count + 1)\n"
        print(report)
        try report.write(to: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("apple-golden.txt"), atomically: true, encoding: .utf8)
        XCTAssertGreaterThan(proposals, 0, "The on-device model proposed nothing at all")
    }
}

/// Renders every chat chart style to PNGs (container tmp/chat-charts/) so layout can be checked by eye.
@MainActor
final class ChatChartRenderTests: XCTestCase {
    func testEveryChartStyleRenders() throws {
        let charts: [ChatChart] = [
            ChatChart(style: .donut, title: "Last month · All cards", items: [
                .init(label: "Home", value: 185_000_00), .init(label: "Food & Drink", value: 129_000_00),
                .init(label: "Leisure", value: 65_000_00), .init(label: "Transport", value: 32_000_00)]),
            ChatChart(style: .bars, title: "This month · All cards", items: [
                .init(label: "Daily", value: 173_000_00), .init(label: "Tokyo Travel", value: 52_000_00)]),
            ChatChart(style: .trend, title: "Last 30 days · Daily", items: (0..<20).map {
                .init(label: Day.string(Day.calendar.date(byAdding: .day, value: -$0, to: .now)!), value: Int64(($0 * 37 % 9) * 15_000_00)) }),
            ChatChart(style: .comparison, title: "Last month vs This month · Daily", items: [
                .init(label: "Total", value: 173_000_00, reference: 60_000_00),
                .init(label: "Transport", value: 100_000_00, reference: 0),
                .init(label: "Food & Drink", value: 73_000_00, reference: 60_000_00)], series: ["Last month", "This month"]),
            ChatChart(style: .budget, title: "Budget this cycle · Daily", items: [
                .init(label: "Overall", value: 173_000_00, reference: 3_000_000_00),
                .init(label: "Food & Drink", value: 73_000_00, reference: 50_000_00)]),
        ]
        let folder = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("chat-charts")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // 640 ≈ Mac chat column, 345 ≈ iPhone transcript width.
        for chart in charts { for width in [640, 345] as [CGFloat] {
            let renderer = ImageRenderer(content: ChatChartView(chart: chart).frame(width: width).padding(12).background(.white))
            renderer.scale = 2
            let image = try XCTUnwrap(renderer.nsImage, chart.style.rawValue)
            let rep = try XCTUnwrap(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
            try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: folder.appendingPathComponent("\(chart.style.rawValue)-\(Int(width)).png"))
        } }
    }
}

final class DemoWorkspaceTests: XCTestCase {
    func testDemoWorkspacePassesBackupValidationAndIsLarge() throws {
        let demo = try DemoWorkspace.make().normalized()
        XCTAssertEqual(demo.cards.count, 5)
        XCTAssertEqual(demo.preferences.stacks.map(\.name), ["Everyday", "Travel", "Work"])
        XCTAssertGreaterThan(demo.cards.reduce(0) { $0 + $1.expenses.count }, 1500)
        XCTAssertEqual(DemoWorkspace.make(now: .distantPast).cards[0].expenses.count,
                       DemoWorkspace.make(now: .distantPast).cards[0].expenses.count, "Deterministic")
    }
}
