import XCTest
@testable import Ankka

/// Files written by older builds must keep loading. These fixtures were written before the
/// Book → Card code rename; decoding and re-encoding them must give the same bytes, so no
/// stored key changed. If a fixture is missing (first run), it's written and the test fails once.
@MainActor
final class GoldenFormatTests: XCTestCase {
    private var fixtures: URL { URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures") }
    private let date = Date(timeIntervalSince1970: 1_790_899_200)

    private func richWorkspace() -> WorkspaceBackup {
        var workspace = DemoWorkspace.make(now: date)
        let method = PaymentMethod(id: UUID(uuidString: "A0000000-0000-0000-0000-000000000001")!, name: "BCA debit", kind: .bank)
        workspace.preferences.paymentMethods = [method]
        workspace.preferences.hiddenEntryFields = [.currency]
        workspace.preferences.stacks[0].capLimit = 900_000_000
        workspace.cards[0].card.spendingCurrency = "JPY"
        workspace.cards[0].card.defaultPaidWithID = method.id
        workspace.cards[0].expenses[0].paidWithID = method.id
        let amount = workspace.cards[0].expenses[0].amount
        workspace.cards[0].expenses[0].originalAmount = amount / 100
        workspace.cards[0].expenses[0].originalCurrency = "JPY"
        workspace.cards[0].expenses[0].rate = "100"
        workspace.cards[0].expenses[0].rateSource = .fetched
        workspace.cards[1].budgets[0].totalUntilDay = "2027-03-31"
        if let match = workspace.cards.first(where: { $0.card.id == workspace.settings.card.id }) { workspace.settings.card = match.card }
        for index in workspace.cards.indices {
            var draft = ExpenseDraft(); draft.id = workspace.cards[index].card.id; draft.cardID = workspace.cards[index].card.id
            draft.date = date; draft.createdAt = date; draft.note = "Draft \(index)"; draft.paidWithID = method.id
            workspace.cards[index].draft = draft
        }
        return workspace
    }

    private func check(_ name: String, _ make: () throws -> Data, decodeAndEncode: (Data) throws -> Data) throws {
        let url = fixtures.appendingPathComponent(name)
        guard let stored = try? Data(contentsOf: url) else {
            try FileManager.default.createDirectory(at: fixtures, withIntermediateDirectories: true)
            // Stored already normalized (a draft keeps only its civil day), so a correct build reproduces it exactly.
            try decodeAndEncode(make()).write(to: url)
            XCTFail("Wrote missing fixture \(name); run again.")
            return
        }
        XCTAssertEqual(try decodeAndEncode(stored), stored, "\(name) no longer round-trips byte for byte")
    }

    func testStoredFormatsStillRoundTripByteForByte() throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        try check("workspace-v8.ankkabackup", { try richWorkspace().encoded() }) { try WorkspaceBackup.decode($0).encoded() }
        try check("preferences.json", { try encoder.encode(richWorkspace().preferences) }) {
            try encoder.encode(JSONDecoder().decode(WorkspacePreferences.self, from: $0))
        }
        try check("settings.json", { try encoder.encode(richWorkspace().settings) }) {
            try encoder.encode(JSONDecoder().decode(PrototypeSettings.self, from: $0))
        }
        try check("draft.json", { try encoder.encode(richWorkspace().cards[0].draft) }) {
            try encoder.encode(JSONDecoder().decode(ExpenseDraft.self, from: $0))
        }
        var widget = WidgetSnapshot.sample
        widget.updatedAt = date; widget.activeCard.id = UUID(uuidString: "B0000000-0000-0000-0000-000000000001")!
        try check("widget.json", { try encoder.encode(widget) }) {
            try encoder.encode(JSONDecoder().decode(WidgetSnapshot.self, from: $0))
        }
    }
}
