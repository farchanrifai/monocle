import Foundation

// MARK: - CSV Record & Date Range Scope

enum CSVDateRangeScope: String, CaseIterable, Identifiable, Sendable {
    case allTime = "All time"
    case thisMonth = "This month"
    case lastMonth = "Last month"
    case custom = "Custom range"

    var id: String { rawValue }
}

struct CSVColumnMapping: Equatable, Sendable {
    var dateIndex: Int?
    var amountIndex: Int?
    var noteIndex: Int?
    var categoryIndex: Int?
    var splitsIndex: Int?
    var paidWithIndex: Int? = nil
    var currencyIndex: Int? = nil
    var originalAmountIndex: Int? = nil
    var rateIndex: Int? = nil

    init(dateIndex: Int? = nil, amountIndex: Int? = nil, noteIndex: Int? = nil, categoryIndex: Int? = nil, splitsIndex: Int? = nil) {
        self.dateIndex = dateIndex
        self.amountIndex = amountIndex
        self.noteIndex = noteIndex
        self.categoryIndex = categoryIndex
        self.splitsIndex = splitsIndex
    }

    var isValid: Bool {
        dateIndex != nil && amountIndex != nil
    }
}

struct CSVImportRow: Identifiable, Sendable {
    let id: UUID
    let rowNumber: Int
    let rawValues: [String]
    var parsedExpense: Expense?
    var isDuplicate: Bool
    var errorMessage: String?
    var isSelectedForImport: Bool

    init(
        id: UUID = UUID(),
        rowNumber: Int,
        rawValues: [String],
        parsedExpense: Expense? = nil,
        isDuplicate: Bool = false,
        errorMessage: String? = nil,
        isSelectedForImport: Bool = true
    ) {
        self.id = id
        self.rowNumber = rowNumber
        self.rawValues = rawValues
        self.parsedExpense = parsedExpense
        self.isDuplicate = isDuplicate
        self.errorMessage = errorMessage
        self.isSelectedForImport = isSelectedForImport
    }
}

struct CSVImportSummary: Equatable, Sendable {
    let totalRows: Int
    let validRows: Int
    let duplicateRows: Int
    let errorRows: Int
    let totalSpending: Int64?

    init(totalRows: Int, validRows: Int, duplicateRows: Int, errorRows: Int, totalSpending: Int64?) {
        self.totalRows = totalRows
        self.validRows = validRows
        self.duplicateRows = duplicateRows
        self.errorRows = errorRows
        self.totalSpending = totalSpending
    }
}

// MARK: - RFC 4180 CSV Tokenizer

struct CSVParseError: LocalizedError, Equatable {
    let record: Int
    let reason: String
    var errorDescription: String? { "CSV record \(record): \(reason). No records were imported." }
}

struct CSVExactSplit: Codable {
    let category: String
    let amount: String
}

enum CSVTokenizer {
    /// Sniffs the most probable delimiter (, ; \t) from the header or sample lines.
    static func sniffDelimiter(from content: String) -> Character {
        var first = ""
        for character in content {
            if character.isNewline {
                if !first.trimmingCharacters(in: .whitespaces).isEmpty { break }
                first = ""
            } else { first.append(character) }
        }
        guard !first.isEmpty else { return "," }

        var commaCount = 0
        var semiCount = 0
        var tabCount = 0
        var inQuotes = false

        for ch in first {
            if ch == "\"" {
                inQuotes.toggle()
            } else if !inQuotes {
                if ch == "," { commaCount += 1 }
                else if ch == ";" { semiCount += 1 }
                else if ch == "\t" { tabCount += 1 }
            }
        }

        if tabCount > commaCount && tabCount > semiCount { return "\t" }
        if semiCount > commaCount { return ";" }
        return ","
    }

    /// Strict quoted fields, escaped quotes and multiline values. Limits are enforced while
    /// tokenizing so malformed/oversized input never reaches a partial import review.
    static func parse(content: String, delimiter: Character = ",", maximumRecords: Int = 10_001, maximumFieldBytes: Int = 1_048_576) throws -> [[String]] {
        guard content.utf8.count <= 10 * 1_024 * 1_024 else { throw CSVParseError(record: 1, reason: "File exceeds 10 MiB") }
        enum State { case start, unquoted, quoted, closed }
        var state = State.start
        var rows: [[String]] = []
        var fields: [String] = []
        var field = ""
        var fieldBytes = 0
        var record = 1
        var iterator = content.makeIterator()
        var character = iterator.next()
        func finishField() throws {
            guard fields.count < 100 else { throw CSVParseError(record: record, reason: "More than 100 columns") }
            fields.append(field)
            field = ""; fieldBytes = 0; state = .start
        }
        func finishRecord() throws {
            try Task.checkCancellation()
            try finishField()
            // Keep interior blank records so review record numbers remain accurate.
            guard rows.count < maximumRecords else { throw CSVParseError(record: record, reason: "Too many records") }
            rows.append(fields); fields = []; record += 1
        }
        while let char = character {
            character = iterator.next()
            let newline = char == "\n" || char == "\r" || char == "\r\n"
            if state == .quoted {
                if char == "\"" {
                    if character == "\"" { field.append("\""); fieldBytes += 1; character = iterator.next() }
                    else { state = .closed }
                } else { field.append(char); fieldBytes += char.utf8.count }
            } else if char == delimiter {
                try finishField()
            } else if newline {
                if char == "\r" && character == "\n" { character = iterator.next() }
                try finishRecord()
            } else if state == .closed {
                throw CSVParseError(record: record, reason: "Unexpected character after closing quote")
            } else if char == "\"" {
                guard state == .start else { throw CSVParseError(record: record, reason: "Quote inside an unquoted field") }
                state = .quoted
            } else {
                state = .unquoted; field.append(char); fieldBytes += char.utf8.count
            }
            guard fieldBytes <= maximumFieldBytes else { throw CSVParseError(record: record, reason: "Field exceeds supported size") }
        }
        guard state != .quoted else { throw CSVParseError(record: record, reason: "Unclosed quoted field") }
        if state != .start || !fields.isEmpty || !field.isEmpty { try finishRecord() }
        while let last = rows.last, last.allSatisfy({ $0.isEmpty }) { rows.removeLast() }
        return rows
    }

    /// Escapes a field according to RFC 4180.
    static func escape(_ field: String, delimiter: Character = ",") -> String {
        let needsQuotes = field.contains(delimiter) || field.contains("\"") || field.contains("\n") || field.contains("\r")
        if needsQuotes {
            let escaped = field.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return field
    }
}

// MARK: - CSV Export Generator

enum CSVExportGenerator {
    static func generate(
        expenses: [Expense],
        categories: [ExpenseCategory],
        cards: [Card] = [],
        paymentMethods: [PaymentMethod] = []
    ) -> String {
        let headers = ["Date", "Time", "Card", "Category", "Amount", "Note", "Source", "Splits", "Paid with", "Currency", "Original amount", "Rate"]
        let paidWithMap = Dictionary(uniqueKeysWithValues: paymentMethods.map { ($0.id, $0.name) })
        var lines: [String] = []
        lines.append(headers.map { CSVTokenizer.escape($0) }.joined(separator: ","))

        let categoryMap = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0.name) })
        let cardMap = Dictionary(uniqueKeysWithValues: cards.map { ($0.id, $0.name) })

        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "en_US_POSIX")
        timeFormatter.dateFormat = "HH:mm:ss"

        for expense in expenses {
            let dateStr = expense.day
            let timeStr = timeFormatter.string(from: expense.createdAt)
            let cardName = expense.cardID.flatMap { cardMap[$0] } ?? "Default"

            let categoryStr: String
            if expense.splits.count == 1, let first = expense.splits.first {
                categoryStr = categoryMap[first.categoryID] ?? "General"
            } else if expense.splits.count > 1 {
                categoryStr = expense.splits.map { alloc in
                    let name = categoryMap[alloc.categoryID] ?? "General"
                    let amountInt = Money.exactDigits(alloc.amount)
                    return "\(name) (\(amountInt))"
                }.joined(separator: " + ")
            } else {
                categoryStr = "General"
            }

            // Exact locale-independent IDR decimals for spreadsheet math and round trips.
            let amountStr = Money.exactDigits(expense.amount)
            let noteStr = expense.note
            let sourceStr = expense.source

            let exactSplits = expense.splits.map { CSVExactSplit(category: categoryMap[$0.categoryID] ?? "General", amount: Money.exactDigits($0.amount)) }
            let splitData = (try? JSONEncoder().encode(exactSplits)) ?? Data()
            let splits = String(data: splitData, encoding: .utf8) ?? ""
            let paidWith = expense.paidWithID.flatMap { paidWithMap[$0] } ?? ""
            let original = expense.originalAmount.map(Money.exactDigits) ?? ""
            let row = [dateStr, timeStr, cardName, categoryStr, amountStr, noteStr, sourceStr, splits, paidWith,
                       expense.originalCurrency ?? "", original, expense.rate ?? ""]
            lines.append(row.map { CSVTokenizer.escape($0) }.joined(separator: ","))
        }

        return lines.joined(separator: "\r\n")
    }
}

// MARK: - CSV Import Parser & Engine

enum CSVImportParser {
    private struct DuplicateKey: Hashable {
        let day: String
        let amount: Int64
        let note: String
        init(day: String, amount: Int64, note: String) {
            self.day = day
            self.amount = amount
            self.note = note.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
    }

    /// Auto-detect column mappings from header names.
    static func detectColumnMapping(headers: [String]) -> CSVColumnMapping {
        var mapping = CSVColumnMapping()

        for (idx, rawHeader) in headers.enumerated() {
            let h = rawHeader.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

            if h == "splits" { mapping.splitsIndex = idx }
            if h == "paid with" || h == "dibayar dengan" { mapping.paidWithIndex = idx }
            if h == "currency" || h == "mata uang" { mapping.currencyIndex = idx }
            if h == "original amount" { mapping.originalAmountIndex = idx }
            if h == "rate" || h == "kurs" { mapping.rateIndex = idx }

            // Date matches
            if mapping.dateIndex == nil {
                if h == "date" || h == "tanggal" || h == "tgl" || h == "waktu" || h.contains("trans date") || h.contains("tgl transaksi") {
                    mapping.dateIndex = idx
                }
            }

            // Amount matches
            if mapping.amountIndex == nil {
                if h == "amount" || h == "jumlah" || h == "nominal" || h == "total" || h == "debit" || h == "debet" || h == "biaya" || h == "pengeluaran" || h == "spending" || h == "harga" || h == "nilai" {
                    mapping.amountIndex = idx
                }
            }

            // Note/Description matches
            if mapping.noteIndex == nil {
                if h == "note" || h == "notes" || h == "description" || h == "deskripsi" || h == "keterangan" || h == "memo" || h == "transaksi" || h == "uraian" || h == "merchant" || h == "payee" || h == "narration" || h == "detail" || h == "rincian" {
                    mapping.noteIndex = idx
                }
            }

            // Category matches
            if mapping.categoryIndex == nil {
                if h == "category" || h == "kategori" || h == "pos" || h == "group" || h == "tipe" || h == "type" || h == "klasifikasi" {
                    mapping.categoryIndex = idx
                }
            }
        }

        // Secondary fallback if still unmapped: partial substring
        if mapping.dateIndex == nil {
            for (idx, rawHeader) in headers.enumerated() {
                let h = rawHeader.lowercased()
                if h.contains("date") || h.contains("tanggal") {
                    mapping.dateIndex = idx
                    break
                }
            }
        }

        if mapping.amountIndex == nil {
            for (idx, rawHeader) in headers.enumerated() {
                let h = rawHeader.lowercased()
                if h.contains("amount") || h.contains("jumlah") || h.contains("nominal") {
                    mapping.amountIndex = idx
                    break
                }
            }
        }

        if mapping.noteIndex == nil {
            for (idx, rawHeader) in headers.enumerated() {
                let h = rawHeader.lowercased()
                if h.contains("note") || h.contains("desc") || h.contains("detail") || h.contains("merchant") || h.contains("keterangan") || h.contains("uraian") || h.contains("memo") || h.contains("rincian") {
                    mapping.noteIndex = idx
                    break
                }
            }
        }

        if mapping.categoryIndex == nil {
            for (idx, rawHeader) in headers.enumerated() {
                let h = rawHeader.lowercased()
                if h.contains("categor") || h.contains("kategori") || h.contains("klasifikasi") {
                    mapping.categoryIndex = idx
                    break
                }
            }
        }

        return mapping
    }

    /// Multi-strategy date parser returning (YYYY-MM-DD, Date).
    static func parseDate(_ input: String) -> (day: String, date: Date)? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // 1. Direct YYYY-MM-DD validation
        if let d = Day.date(trimmed) {
            return (trimmed, d)
        }

        // 2. Candidate formats
        let formats = [
            "yyyy-MM-dd",
            "dd/MM/yyyy",
            "d/M/yyyy",
            "dd-MM-yyyy",
            "d-M-yyyy",
            "MM/dd/yyyy",
            "M/d/yyyy",
            "yyyy/MM/dd",
            "yyyy-MM-dd'T'HH:mm:ssZ",
            "yyyy-MM-dd'T'HH:mm:ss.SSSZ",
            "yyyy-MM-dd HH:mm:ss",
            "dd MMM yyyy",
            "d MMM yyyy"
        ]

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.calendar = Day.calendar
        formatter.isLenient = false

        for fmt in formats {
            formatter.dateFormat = fmt
            if let parsed = formatter.date(from: trimmed) {
                let dayString = Day.string(parsed)
                return (dayString, parsed)
            }
        }

        return nil
    }

    /// Flexible amount parser returning minor units (100 = Rp 1).
    static func parseAmount(_ input: String) -> Int64? {
        var str = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !str.isEmpty else { return nil }

        // Banking exports commonly encode spending as a negative/debit.
        if str.hasPrefix("("), str.hasSuffix(")") {
            str = String(str.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
        }
        if str.hasPrefix("-") { str = String(str.dropFirst()).trimmingCharacters(in: .whitespaces) }
        if str.hasPrefix("idr") { str = String(str.dropFirst(3)).trimmingCharacters(in: .whitespaces) }
        else if str.hasPrefix("rp") { str = String(str.dropFirst(2)).trimmingCharacters(in: .whitespaces) }
        if str.hasPrefix("-") { str = String(str.dropFirst()).trimmingCharacters(in: .whitespaces) }

        let locale: Locale
        if let comma = str.lastIndex(of: ","), let dot = str.lastIndex(of: ".") {
            locale = Locale(identifier: comma > dot ? "id_ID" : "en_US")
        } else if str.contains(",") {
            let suffix = str.split(separator: ",", omittingEmptySubsequences: false).last ?? ""
            locale = Locale(identifier: suffix.count == 3 && !str.hasSuffix("k") ? "en_US" : "id_ID")
        } else if str.contains(".") {
            let suffix = str.split(separator: ".", omittingEmptySubsequences: false).last ?? ""
            locale = Locale(identifier: suffix.count == 3 && !str.hasSuffix("k") ? "id_ID" : "en_US")
        } else {
            locale = Locale(identifier: "en_US")
        }
        // External CSV and accepted history may retain exact minor units; never round.
        if let whole = try? Money.parse(str, locale: locale) { return whole }
        let decimal = locale.decimalSeparator ?? "."
        let grouping = locale.groupingSeparator ?? ","
        let pattern = "^(?:[0-9]+|[0-9]{1,3}(?:" + NSRegularExpression.escapedPattern(for: grouping) + "[0-9]{3})+)(?:" + NSRegularExpression.escapedPattern(for: decimal) + "[0-9]{1,2})?$"
        guard str.range(of: pattern, options: .regularExpression) != nil else { return nil }
        return try? Money.parseExact(str.replacingOccurrences(of: grouping, with: "").replacingOccurrences(of: decimal, with: "."))
    }

    /// Check if candidate matches an existing expense.
    static func isDuplicate(
        day: String,
        amount: Int64,
        note: String,
        existingExpenses: [Expense]
    ) -> Bool {
        let normNote = note.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return existingExpenses.contains { exp in
            exp.day == day &&
            exp.amount == amount &&
            exp.note.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normNote
        }
    }

    /// Parses raw table rows into CSVImportRow items using the specified mapping and target card context.
    static func processRows(
        rawRows: [[String]],
        hasHeader: Bool,
        mapping: CSVColumnMapping,
        targetCardID: UUID,
        categories: [ExpenseCategory],
        defaultCategoryID: UUID,
        existingExpenses: [Expense],
        paymentMethods: [PaymentMethod] = []
    ) -> [CSVImportRow] {
        guard mapping.isValid else { return [] }

        let rowsToProcess = hasHeader ? Array(rawRows.dropFirst()) : rawRows
        var result: [CSVImportRow] = []
        result.reserveCapacity(rowsToProcess.count)
        var seen = Set(existingExpenses.map { DuplicateKey(day: $0.day, amount: $0.amount, note: $0.note) })

        let categoryByName = Dictionary(categories.map { ($0.name.trimmingCharacters(in: .whitespaces).lowercased(), $0.id) }) { first, _ in first }

        for (offset, rowValues) in rowsToProcess.enumerated() {
            if Task.isCancelled { return [] }
            let rowNumber = hasHeader ? (offset + 2) : (offset + 1)

            guard let dateIdx = mapping.dateIndex, rowValues.indices.contains(dateIdx),
                  let amountIdx = mapping.amountIndex, rowValues.indices.contains(amountIdx) else {
                result.append(CSVImportRow(
                    rowNumber: rowNumber,
                    rawValues: rowValues,
                    errorMessage: "Missing required date or amount column"
                ))
                continue
            }

            let dateRaw = rowValues[dateIdx]
            let amountRaw = rowValues[amountIdx]

            guard let dateParsed = parseDate(dateRaw) else {
                result.append(CSVImportRow(
                    rowNumber: rowNumber,
                    rawValues: rowValues,
                    errorMessage: "Invalid date '\(dateRaw)'"
                ))
                continue
            }

            guard let amountParsed = parseAmount(amountRaw) else {
                result.append(CSVImportRow(
                    rowNumber: rowNumber,
                    rawValues: rowValues,
                    errorMessage: "Invalid amount '\(amountRaw)'"
                ))
                continue
            }

            var note = ""
            if let noteIdx = mapping.noteIndex, rowValues.indices.contains(noteIdx) {
                note = rowValues[noteIdx].trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if note.isEmpty {
                note = "Imported expense"
            }

            var categoryID = defaultCategoryID
            if let catIdx = mapping.categoryIndex, rowValues.indices.contains(catIdx) {
                let catRaw = rowValues[catIdx].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if let matched = categoryByName[catRaw] {
                    categoryID = matched
                } else {
                    let matches = categoryByName.filter { name, _ in
                        !catRaw.isEmpty && (name.contains(catRaw) || catRaw.contains(name))
                    }
                    if matches.count == 1, let match = matches.first { categoryID = match.value }
                }
            }

            var splits: [Split] = [.init(categoryID: categoryID, amount: amountParsed)]
            if let splitIndex = mapping.splitsIndex, rowValues.indices.contains(splitIndex), !rowValues[splitIndex].isEmpty {
                do {
                    let exact = try JSONDecoder().decode([CSVExactSplit].self, from: Data(rowValues[splitIndex].utf8))
                    splits = try exact.map { split in
                        guard let id = categoryByName[split.category.trimmingCharacters(in: .whitespaces).lowercased()] else { throw EntryError.missingCategory }
                        return Split(categoryID: id, amount: try Money.parseExact(split.amount))
                    }
                    guard try Money.checkedSum(splits.map(\.amount)) == amountParsed,
                          !splits.isEmpty, Set(splits.map(\.categoryID)).count == splits.count else { throw EntryError.splitMismatch }
                } catch {
                    result.append(CSVImportRow(rowNumber: rowNumber, rawValues: rowValues, errorMessage: "Invalid exact splits: \(error.localizedDescription)", isSelectedForImport: false))
                    continue
                }
            }

            // Paid with matches an existing label by name; an unknown name is left unset.
            let paidWithName = mapping.paidWithIndex.flatMap { rowValues.indices.contains($0) ? rowValues[$0] : nil }?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let paidWithID = paidWithName.flatMap { name in
                paymentMethods.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.id
            }
            var expense = Expense(
                id: UUID(),
                amount: amountParsed,
                day: dateParsed.day,
                note: note,
                splits: splits,
                source: "csv_import",
                createdAt: dateParsed.date,
                cardID: targetCardID,
                paidWithID: paidWithID
            )
            // Amount stays the reporting amount; a foreign original comes along only when currency, amount and rate are all valid.
            func cell(_ index: Int?) -> String? {
                index.flatMap { rowValues.indices.contains($0) ? rowValues[$0].trimmingCharacters(in: .whitespacesAndNewlines) : nil }.flatMap { $0.isEmpty ? nil : $0 }
            }
            if let code = cell(mapping.currencyIndex)?.uppercased(), Money.isCurrencyCode(code), code != Money.reportingCurrency,
               let original = cell(mapping.originalAmountIndex).flatMap({ try? Money.parseExact($0) }),
               let rate = cell(mapping.rateIndex), let value = Decimal(string: rate, locale: Locale(identifier: "en_US_POSIX")), value > 0 {
                expense.originalAmount = original; expense.originalCurrency = code; expense.rate = rate; expense.rateSource = .manual
            }

            do { try expense.validate(categories: categories) }
            catch {
                result.append(CSVImportRow(rowNumber: rowNumber, rawValues: rowValues, errorMessage: error.localizedDescription, isSelectedForImport: false))
                continue
            }
            let duplicate = !seen.insert(DuplicateKey(day: dateParsed.day, amount: amountParsed, note: note)).inserted
            result.append(CSVImportRow(
                rowNumber: rowNumber,
                rawValues: rowValues,
                parsedExpense: expense,
                isDuplicate: duplicate,
                isSelectedForImport: !duplicate
            ))
        }

        return result
    }

    /// Calculate summary counts from processed rows.
    static func summarize(rows: [CSVImportRow]) -> CSVImportSummary {
        var valid = 0
        var duplicates = 0
        var errors = 0
        var selectedAmounts: [Int64] = []

        for row in rows {
            if row.errorMessage != nil || row.parsedExpense == nil {
                errors += 1
            } else if row.isDuplicate {
                duplicates += 1
                if row.isSelectedForImport, let exp = row.parsedExpense {
                    selectedAmounts.append(exp.amount)
                }
            } else {
                valid += 1
                if row.isSelectedForImport, let exp = row.parsedExpense {
                    selectedAmounts.append(exp.amount)
                }
            }
        }

        return CSVImportSummary(
            totalRows: rows.count,
            validRows: valid,
            duplicateRows: duplicates,
            errorRows: errors,
            totalSpending: try? Money.checkedSum(selectedAmounts)
        )
    }
}
