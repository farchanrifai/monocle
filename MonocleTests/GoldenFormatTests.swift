import XCTest
@testable import Monocle

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
        workspace.books[0].book.spendingCurrency = "JPY"
        workspace.books[0].book.defaultPaidWithID = method.id
        workspace.books[0].expenses[0].paidWithID = method.id
        let amount = workspace.books[0].expenses[0].amount
        workspace.books[0].expenses[0].originalAmount = amount / 100
        workspace.books[0].expenses[0].originalCurrency = "JPY"
        workspace.books[0].expenses[0].rate = "100"
        workspace.books[0].expenses[0].rateSource = .fetched
        workspace.books[1].budgets[0].totalUntilDay = "2027-03-31"
        if let match = workspace.books.first(where: { $0.book.id == workspace.settings.book.id }) { workspace.settings.book = match.book }
        for index in workspace.books.indices {
            var draft = ExpenseDraft(); draft.id = workspace.books[index].book.id; draft.bookID = workspace.books[index].book.id
            draft.date = date; draft.createdAt = date; draft.note = "Draft \(index)"; draft.paidWithID = method.id
            workspace.books[index].draft = draft
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
        try check("workspace-v8.monoclebackup", { try richWorkspace().encoded() }) { try WorkspaceBackup.decode($0).encoded() }
        try check("preferences.json", { try encoder.encode(richWorkspace().preferences) }) {
            try encoder.encode(JSONDecoder().decode(WorkspacePreferences.self, from: $0))
        }
        try check("settings.json", { try encoder.encode(richWorkspace().settings) }) {
            try encoder.encode(JSONDecoder().decode(PrototypeSettings.self, from: $0))
        }
        try check("draft.json", { try encoder.encode(richWorkspace().books[0].draft) }) {
            try encoder.encode(JSONDecoder().decode(ExpenseDraft.self, from: $0))
        }
        var widget = WidgetSnapshot.sample
        widget.updatedAt = date; widget.activeBook.id = UUID(uuidString: "B0000000-0000-0000-0000-000000000001")!
        try check("widget.json", { try encoder.encode(widget) }) {
            try encoder.encode(JSONDecoder().decode(WidgetSnapshot.self, from: $0))
        }
    }
}
