import XCTest
@testable import Monocle

final class CSVTests: XCTestCase {

    // MARK: - Tokenizer & Delimiter Sniffing

    func testRFC4180TokenizerStandardComma() throws {
        let content = """
        Date,Amount,Note
        2026-09-11,50000,"Coffee, black"
        2026-09-12,120000,"Dinner with ""VIP"" guests"
        2026-09-13,75000,"Multi-line
        memo here"
        """

        let rows = try CSVTokenizer.parse(content: content, delimiter: ",")
        XCTAssertEqual(rows.count, 4)

        XCTAssertEqual(rows[0], ["Date", "Amount", "Note"])
        XCTAssertEqual(rows[1], ["2026-09-11", "50000", "Coffee, black"])
        XCTAssertEqual(rows[2], ["2026-09-12", "120000", "Dinner with \"VIP\" guests"])
        XCTAssertEqual(rows[3], ["2026-09-13", "75000", "Multi-line\nmemo here"])
    }

    func testDelimiterSniffing() {
        let commaCSV = "Date,Amount,Note\n2026-09-11,50000,Lunch"
        let semiCSV = "Date;Amount;Note\n2026-09-11;50000;Lunch"
        let tabCSV = "Date\tAmount\tNote\n2026-09-11\t50000\tLunch"

        XCTAssertEqual(CSVTokenizer.sniffDelimiter(from: commaCSV), ",")
        XCTAssertEqual(CSVTokenizer.sniffDelimiter(from: semiCSV), ";")
        XCTAssertEqual(CSVTokenizer.sniffDelimiter(from: tabCSV), "\t")
    }

    func testCSVTokenizerSemicolon() throws {
        let content = "Tanggal;Nominal;Keterangan\r\n2026-09-11;45000;Kopi Pagi\r\n2026-09-12;80000;Bensin"
        let rows = try CSVTokenizer.parse(content: content, delimiter: ";")
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows[1], ["2026-09-11", "45000", "Kopi Pagi"])
        XCTAssertEqual(rows[2], ["2026-09-12", "80000", "Bensin"])
    }

    // MARK: - Date Parsing

    func testDateParsingMultiFormat() {
        // YYYY-MM-DD
        let d1 = CSVImportParser.parseDate("2026-09-11")
        XCTAssertEqual(d1?.day, "2026-09-11")

        // DD/MM/YYYY
        let d2 = CSVImportParser.parseDate("15/08/2026")
        XCTAssertEqual(d2?.day, "2026-08-15")

        // DD-MM-YYYY
        let d3 = CSVImportParser.parseDate("24-12-2026")
        XCTAssertEqual(d3?.day, "2026-12-24")

        // ISO8601 with time
        let d4 = CSVImportParser.parseDate("2026-05-20T14:30:00Z")
        XCTAssertEqual(d4?.day, "2026-05-20")

        // Invalid
        XCTAssertNil(CSVImportParser.parseDate("not-a-date"))
        XCTAssertNil(CSVImportParser.parseDate(""))
    }

    // MARK: - Amount Parsing

    func testAmountParsingMultiFormat() {
        // Plain integer
        XCTAssertEqual(CSVImportParser.parseAmount("50000"), 50_000_00)

        // Indonesian thousand dot
        XCTAssertEqual(CSVImportParser.parseAmount("50.000"), 50_000_00)
        XCTAssertEqual(CSVImportParser.parseAmount("1.250.000"), 1_250_000_00)

        // Currency prefixes
        XCTAssertEqual(CSVImportParser.parseAmount("Rp 75.000"), 75_000_00)
        XCTAssertEqual(CSVImportParser.parseAmount("IDR 100000"), 100_000_00)

        // Negative values (debit expenses)
        XCTAssertEqual(CSVImportParser.parseAmount("-28000"), 28_000_00)
        XCTAssertEqual(CSVImportParser.parseAmount("-Rp 35.000"), 35_000_00)
        XCTAssertEqual(CSVImportParser.parseAmount("(45000)"), 45_000_00)

        // Thousands suffix 'k'
        XCTAssertEqual(CSVImportParser.parseAmount("28k"), 28_000_00)
        XCTAssertEqual(CSVImportParser.parseAmount("150k"), 150_000_00)

        // Decimal style (European 50.000,00 vs US 50,000.00)
        XCTAssertEqual(CSVImportParser.parseAmount("50.000,00"), 50_000_00)
        XCTAssertEqual(CSVImportParser.parseAmount("50,000.00"), 50_000_00)

        // Invalid
        XCTAssertNil(CSVImportParser.parseAmount("abc"))
        XCTAssertNil(CSVImportParser.parseAmount("0"))
        XCTAssertNil(CSVImportParser.parseAmount("-0"))
    }

    // MARK: - Column Mapping

    func testColumnMappingDetection() {
        let englishHeaders = ["Date", "Amount", "Description", "Category"]
        let m1 = CSVImportParser.detectColumnMapping(headers: englishHeaders)
        XCTAssertEqual(m1.dateIndex, 0)
        XCTAssertEqual(m1.amountIndex, 1)
        XCTAssertEqual(m1.noteIndex, 2)
        XCTAssertEqual(m1.categoryIndex, 3)

        let indonesianHeaders = ["Tanggal Transaksi", "Nominal", "Keterangan", "Kategori"]
        let m2 = CSVImportParser.detectColumnMapping(headers: indonesianHeaders)
        XCTAssertEqual(m2.dateIndex, 0)
        XCTAssertEqual(m2.amountIndex, 1)
        XCTAssertEqual(m2.noteIndex, 2)
        XCTAssertEqual(m2.categoryIndex, 3)

        let bankHeaders = ["No", "Trans Date", "Merchant / Detail", "Debit", "Credit"]
        let m3 = CSVImportParser.detectColumnMapping(headers: bankHeaders)
        XCTAssertEqual(m3.dateIndex, 1)
        XCTAssertEqual(m3.noteIndex, 2)
        XCTAssertEqual(m3.amountIndex, 3)
    }

    // MARK: - CSV Export Generator

    func testCSVExportGenerator() throws {
        let cardID = UUID()
        let foodCat = ExpenseCategory(id: UUID(), name: "Food & Drink", symbol: "cup.and.saucer")
        let transCat = ExpenseCategory(id: UUID(), name: "Transport", symbol: "tram")
        let categories = [foodCat, transCat]
        let cards = [Card(id: cardID, name: "Daily", kind: .demo, colorIndex: 0)]

        let exp1 = Expense(
            id: UUID(),
            amount: 35_000_00,
            day: "2026-09-10",
            note: "Coffee, Iced Latte",
            splits: [.init(categoryID: foodCat.id, amount: 35_000_00)],
            source: "manual",
            createdAt: Date.now,
            cardID: cardID
        )

        let exp2 = Expense(
            id: UUID(),
            amount: 80_000_00,
            day: "2026-09-11",
            note: "Commute & Snack",
            splits: [
                .init(categoryID: foodCat.id, amount: 30_000_00),
                .init(categoryID: transCat.id, amount: 50_000_00)
            ],
            source: "manual",
            createdAt: Date.now,
            cardID: cardID
        )

        // Paid with round-trips by label name; an unknown name imports unset.
        let bca = PaymentMethod(name: "BCA debit")
        var paid = exp1; paid.paidWithID = bca.id
        paid.originalAmount = 30_000; paid.originalCurrency = "JPY"; paid.rate = "116.67"; paid.rateSource = .fetched
        let paidCSV = CSVExportGenerator.generate(expenses: [paid, exp2], categories: categories, cards: cards, paymentMethods: [bca])
        let paidRows = try CSVTokenizer.parse(content: paidCSV, delimiter: ",")
        XCTAssertEqual(paidRows[1][8], "BCA debit")
        let paidMapping = CSVImportParser.detectColumnMapping(headers: paidRows[0])
        XCTAssertEqual(paidMapping.paidWithIndex, 8)
        let imported = CSVImportParser.processRows(rawRows: paidRows, hasHeader: true, mapping: paidMapping, targetCardID: cardID,
                                                   categories: categories, defaultCategoryID: foodCat.id, existingExpenses: [],
                                                   paymentMethods: [bca])
        XCTAssertEqual(imported.compactMap(\.parsedExpense).map(\.paidWithID), [bca.id, nil])
        XCTAssertEqual(imported.first?.parsedExpense?.originalCurrency, "JPY")
        XCTAssertEqual(imported.first?.parsedExpense?.originalAmount, 30_000)
        XCTAssertNil(imported.last?.parsedExpense?.originalCurrency)
        let unknown = CSVImportParser.processRows(rawRows: paidRows, hasHeader: true, mapping: paidMapping, targetCardID: cardID,
                                                  categories: categories, defaultCategoryID: foodCat.id, existingExpenses: [])
        XCTAssertEqual(unknown.compactMap(\.parsedExpense).compactMap(\.paidWithID), [])

        let csv = CSVExportGenerator.generate(expenses: [exp1, exp2], categories: categories, cards: cards)
        let rows = try CSVTokenizer.parse(content: csv, delimiter: ",")

        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows[0], ["Date", "Time", "Card", "Category", "Amount", "Note", "Source", "Splits", "Paid with", "Currency", "Original amount", "Rate"])

        // Row 1
        XCTAssertEqual(rows[1][0], "2026-09-10")
        XCTAssertEqual(rows[1][2], "Daily")
        XCTAssertEqual(rows[1][3], "Food & Drink")
        XCTAssertEqual(rows[1][4], "35000")
        XCTAssertEqual(rows[1][5], "Coffee, Iced Latte")

        // Row 2 (Split)
        XCTAssertEqual(rows[2][0], "2026-09-11")
        XCTAssertEqual(rows[2][2], "Daily")
        XCTAssertTrue(rows[2][3].contains("Food & Drink (30000)"))
        XCTAssertTrue(rows[2][3].contains("Transport (50000)"))
        XCTAssertEqual(rows[2][4], "80000")
        XCTAssertEqual(rows[2][5], "Commute & Snack")
    }

    @MainActor
    func testAllCardExportUsesCategoriesFromEveryCard() throws {
        let store = try ExpenseRepository(inMemory: true)
        try store.prepareSampleCard()
        let travel = GlobalCategory(name: "Rail Pass", symbol: "tram.fill")
        let second = try store.createCard(named: "Travel", initialCategories: [travel])
        try store.save(
            Expense(amount: 80_000_00, day: "2026-09-11", note: "Airport train",
                    splits: [.init(categoryID: travel.id, amount: 80_000_00)], cardID: second.id),
            in: second.id
        )
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = try ExpenseService(store: store)
        let model = AppModel(expenses: service, state: FileLocalStateStore(directory: directory))

        let csv = model.csvExportText(for: nil, dateRange: .allTime)

        XCTAssertTrue(csv.contains("Rail Pass"))
        XCTAssertFalse(csv.contains("General"))
    }

    // MARK: - Row Processing & Duplicate Detection

    func testRowProcessingAndDuplicateDetection() {
        let cardID = UUID()
        let foodCat = ExpenseCategory(id: UUID(), name: "Food & Drink", symbol: "cup.and.saucer")
        let categories = [foodCat]

        let existingExpense = Expense(
            amount: 50_000_00,
            day: "2026-09-11",
            note: "Sushi Lunch",
            splits: [.init(categoryID: foodCat.id, amount: 50_000_00)],
            cardID: cardID
        )

        let rawRows = [
            ["Date", "Amount", "Note"],
            ["2026-09-11", "50000", "Sushi Lunch"], // Exact duplicate!
            ["2026-09-11", "25000", "Matcha Latte"], // New
            ["invalid-date", "10000", "Bad row"]     // Error
        ]

        let mapping = CSVColumnMapping(dateIndex: 0, amountIndex: 1, noteIndex: 2)

        let rows = CSVImportParser.processRows(
            rawRows: rawRows,
            hasHeader: true,
            mapping: mapping,
            targetCardID: cardID,
            categories: categories,
            defaultCategoryID: foodCat.id,
            existingExpenses: [existingExpense]
        )

        XCTAssertEqual(rows.count, 3)

        // Row 1: Duplicate
        XCTAssertTrue(rows[0].isDuplicate)
        XCTAssertFalse(rows[0].isSelectedForImport)
        XCTAssertEqual(rows[0].parsedExpense?.amount, 50_000_00)

        // Row 2: Valid new expense
        XCTAssertFalse(rows[1].isDuplicate)
        XCTAssertTrue(rows[1].isSelectedForImport)
        XCTAssertEqual(rows[1].parsedExpense?.amount, 25_000_00)
        XCTAssertEqual(rows[1].parsedExpense?.note, "Matcha Latte")

        // Row 3: Error
        XCTAssertNotNil(rows[2].errorMessage)
        XCTAssertNil(rows[2].parsedExpense)

        let summary = CSVImportParser.summarize(rows: rows)
        XCTAssertEqual(summary.totalRows, 3)
        XCTAssertEqual(summary.validRows, 1)
        XCTAssertEqual(summary.duplicateRows, 1)
        XCTAssertEqual(summary.errorRows, 1)
        XCTAssertEqual(summary.totalSpending, 25_000_00)
    }

    // MARK: - Batch Persistence

    @MainActor
    func testBatchSaveExpensesInExpenseService() throws {
        let store = try ExpenseRepository(inMemory: true)
        let card = try store.createCard(named: "Batch Test")
        let cats = try store.categories(in: card.id)
        let defaultCat = cats[0]

        let expenseService = try ExpenseService(store: store)

        let exp1 = Expense(amount: 15_000_00, day: "2026-09-11", note: "Snack 1", splits: [.init(categoryID: defaultCat.id, amount: 15_000_00)], cardID: card.id)
        let exp2 = Expense(amount: 25_000_00, day: "2026-09-11", note: "Snack 2", splits: [.init(categoryID: defaultCat.id, amount: 25_000_00)], cardID: card.id)
        let exp3 = Expense(amount: 35_000_00, day: "2026-09-11", note: "Snack 3", splits: [.init(categoryID: defaultCat.id, amount: 35_000_00)], cardID: card.id)

        try expenseService.saveExpenses([exp1, exp2, exp3], in: card.id)

        let saved = try store.expenses(in: card.id)
        XCTAssertEqual(saved.count, 3)
        XCTAssertTrue(saved.contains(where: { $0.note == "Snack 1" }))
        XCTAssertTrue(saved.contains(where: { $0.note == "Snack 2" }))
        XCTAssertTrue(saved.contains(where: { $0.note == "Snack 3" }))
    }
}

extension CSVTests {
    func testMalformedAmountsAreNotSilentlyChanged() {
        XCTAssertNil(CSVImportParser.parseAmount("abc123"))
        // External CSV preserves exact minor units; manual Money.parse remains whole IDR.
        XCTAssertEqual(CSVImportParser.parseAmount("50.50"), 5_050)
        XCTAssertEqual(CSVImportParser.parseAmount("50,50"), 5_050)
        XCTAssertNil(CSVImportParser.parseAmount("50.5001"))
        XCTAssertNil(CSVImportParser.parseAmount("50,5001"))
        XCTAssertNil(CSVImportParser.parseAmount("1,2,3"))
        XCTAssertEqual(CSVImportParser.parseAmount("1.5k"), 150000)
        XCTAssertEqual(CSVImportParser.parseAmount("1,5k"), 150000)
    }
}

extension CSVTests {
    func testImportFindsDuplicatesWithinFileAndPreservesBlankCategoryDefault() {
        let categories = ExpenseCategory.defaults
        let rows = [["2026-09-01", "1000", "Coffee", ""], ["2026-09-01", "1000", " coffee ", ""]]
        let parsed = CSVImportParser.processRows(rawRows: rows, hasHeader: false,
            mapping: CSVColumnMapping(dateIndex: 0, amountIndex: 1, noteIndex: 2, categoryIndex: 3),
            targetCardID: UUID(), categories: categories, defaultCategoryID: categories[1].id, existingExpenses: [])
        XCTAssertFalse(parsed[0].isDuplicate)
        XCTAssertTrue(parsed[1].isDuplicate)
        XCTAssertEqual(parsed[0].parsedExpense?.splits.first?.categoryID, categories[1].id)
        let invalid = CSVImportParser.processRows(rawRows: rows, hasHeader: false,
            mapping: CSVColumnMapping(dateIndex: -1, amountIndex: 1), targetCardID: UUID(),
            categories: categories, defaultCategoryID: categories[0].id, existingExpenses: [])
        XCTAssertNil(invalid[0].parsedExpense)
    }
}
