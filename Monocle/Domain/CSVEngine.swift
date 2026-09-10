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

    init(dateIndex: Int? = nil, amountIndex: Int? = nil, noteIndex: Int? = nil, categoryIndex: Int? = nil) {
        self.dateIndex = dateIndex
        self.amountIndex = amountIndex
        self.noteIndex = noteIndex
        self.categoryIndex = categoryIndex
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
    let totalSpending: Int64

    init(totalRows: Int, validRows: Int, duplicateRows: Int, errorRows: Int, totalSpending: Int64) {
        self.totalRows = totalRows
        self.validRows = validRows
        self.duplicateRows = duplicateRows
        self.errorRows = errorRows
        self.totalSpending = totalSpending
    }
}

// MARK: - RFC 4180 CSV Tokenizer

enum CSVTokenizer {
    /// Sniffs the most probable delimiter (, ; \t) from the header or sample lines.
    static func sniffDelimiter(from content: String) -> Character {
        let lines = content.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard let first = lines.first else { return "," }

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

    /// Parses CSV content into rows and fields per RFC 4180.
    static func parse(content: String, delimiter: Character = ",") -> [[String]] {
        var rows: [[String]] = []
        var currentRow: [String] = []
        var currentField = ""
        var inQuotes = false

        var iterator = content.makeIterator()
        var peekChar: Character? = iterator.next()

        while let char = peekChar {
            peekChar = iterator.next()

            if inQuotes {
                if char == "\"" {
                    if peekChar == "\"" {
                        // Escaped quote: "" -> "
                        currentField.append("\"")
                        peekChar = iterator.next()
                    } else {
                        // Closing quote
                        inQuotes = false
                    }
                } else {
                    currentField.append(char)
                }
            } else {
                if char == "\"" {
                    inQuotes = true
                } else if char == delimiter {
                    currentRow.append(currentField.trimmingCharacters(in: .whitespaces))
                    currentField = ""
                } else if char.isNewline || char == "\r\n" || char == "\n" || char == "\r" {
                    if char == "\r" && peekChar == "\n" {
                        peekChar = iterator.next()
                    }
                    currentRow.append(currentField.trimmingCharacters(in: .whitespaces))
                    currentField = ""
                    rows.append(currentRow)
                    currentRow = []
                } else {
                    currentField.append(char)
                }
            }
        }

        // Flush any trailing field/row
        if !currentField.isEmpty || !currentRow.isEmpty {
            currentRow.append(currentField.trimmingCharacters(in: .whitespaces))
            rows.append(currentRow)
        }

        // Remove completely blank trailing rows
        return rows.filter { row in
            !row.isEmpty && row.contains { !$0.isEmpty }
        }
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
        books: [BookProfile] = []
    ) -> String {
        let headers = ["Date", "Time", "Book", "Category", "Amount", "Note", "Source"]
        var lines: [String] = []
        lines.append(headers.map { CSVTokenizer.escape($0) }.joined(separator: ","))

        let categoryMap = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0.name) })
        let bookMap = Dictionary(uniqueKeysWithValues: books.map { ($0.id, $0.name) })

        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "en_US_POSIX")
        timeFormatter.dateFormat = "HH:mm:ss"

        for expense in expenses {
            let dateStr = expense.day
            let timeStr = timeFormatter.string(from: expense.createdAt)
            let bookName = expense.bookID.flatMap { bookMap[$0] } ?? "Default"

            let categoryStr: String
            if expense.allocations.count == 1, let first = expense.allocations.first {
                categoryStr = categoryMap[first.categoryID] ?? "General"
            } else if expense.allocations.count > 1 {
                categoryStr = expense.allocations.map { alloc in
                    let name = categoryMap[alloc.categoryID] ?? "General"
                    let amountInt = alloc.amount / 100
                    return "\(name) (\(amountInt))"
                }.joined(separator: " + ")
            } else {
                categoryStr = "General"
            }

            // Unformatted whole IDR amount for spreadsheet math (e.g. 50000)
            let amountInt = expense.amount / 100
            let amountStr = String(amountInt)
            let noteStr = expense.note
            let sourceStr = expense.source

            let row = [dateStr, timeStr, bookName, categoryStr, amountStr, noteStr, sourceStr]
            lines.append(row.map { CSVTokenizer.escape($0) }.joined(separator: ","))
        }

        return lines.joined(separator: "\r\n")
    }
}

// MARK: - CSV Import Parser & Engine

enum CSVImportParser {
    /// Auto-detect column mappings from header names.
    static func detectColumnMapping(headers: [String]) -> CSVColumnMapping {
        var mapping = CSVColumnMapping()

        for (idx, rawHeader) in headers.enumerated() {
            let h = rawHeader.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

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

        // Strip currency prefixes
        if str.hasPrefix("rp") {
            str = String(str.dropFirst(2)).trimmingCharacters(in: .whitespaces)
        } else if str.hasPrefix("idr") {
            str = String(str.dropFirst(3)).trimmingCharacters(in: .whitespaces)
        }

        // Handle parentheses as negative/debit: "(50000)" -> "50000"
        if str.hasPrefix("(") && str.hasSuffix(")") {
            str = String(str.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
        }

        // Strip leading negative sign if present (since in banking CSVs negative = debit/spent)
        if str.hasPrefix("-") {
            str = String(str.dropFirst()).trimmingCharacters(in: .whitespaces)
        }

        // Handle suffix 'k' for thousands
        var thousandsMultiplier: Int64 = 1
        if str.hasSuffix("k") {
            thousandsMultiplier = 1000
            str = String(str.dropLast()).trimmingCharacters(in: .whitespaces)
        }

        // Determine if European punctuation (dot thousand, comma decimal) or standard (comma thousand, dot decimal)
        // E.g. "50.000,00" vs "50,000.00" vs "50000"
        let hasComma = str.contains(",")
        let hasDot = str.contains(".")

        var clean = ""
        if hasDot && hasComma {
            let lastDot = str.lastIndex(of: ".")!
            let lastComma = str.lastIndex(of: ",")!
            if lastComma > lastDot {
                // European: 1.234,56 -> remove dots, split on comma
                let parts = str.components(separatedBy: ",")
                let whole = parts[0].replacingOccurrences(of: ".", with: "")
                clean = whole
            } else {
                // US: 1,234.56 -> remove commas, split on dot
                let parts = str.components(separatedBy: ".")
                let whole = parts[0].replacingOccurrences(of: ",", with: "")
                clean = whole
            }
        } else if hasComma {
            // Only comma: could be decimal (50,5) or thousand (50,000)
            let parts = str.components(separatedBy: ",")
            if parts.count == 2 && parts[1].count <= 2 {
                // Decimal: take whole part
                clean = parts[0]
            } else {
                // Thousands
                clean = str.replacingOccurrences(of: ",", with: "")
            }
        } else if hasDot {
            // Only dot: could be thousand in IDR (50.000) or decimal (50.00)
            let parts = str.components(separatedBy: ".")
            if parts.count == 2 && parts[1].count == 2 && (Int(parts[1]) == 0 || Int(parts[1]) == 00) {
                // E.g. 50.00 decimal
                clean = parts[0]
            } else {
                // IDR thousand separator: 50.000 -> 50000
                clean = str.replacingOccurrences(of: ".", with: "")
            }
        } else {
            clean = str
        }

        clean = clean.filter { $0.isNumber }
        guard let wholeUnits = Int64(clean), wholeUnits > 0, wholeUnits <= (Money.maximum / 100) else {
            return nil
        }

        let multiplied = wholeUnits * thousandsMultiplier
        guard multiplied <= (Money.maximum / 100) else { return nil }

        return multiplied * 100 // Convert to minor units
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

    /// Parses raw table rows into CSVImportRow items using the specified mapping and target book context.
    static func processRows(
        rawRows: [[String]],
        hasHeader: Bool,
        mapping: CSVColumnMapping,
        targetBookID: UUID,
        categories: [ExpenseCategory],
        defaultCategoryID: UUID,
        existingExpenses: [Expense]
    ) -> [CSVImportRow] {
        guard mapping.isValid else { return [] }

        let rowsToProcess = hasHeader ? Array(rawRows.dropFirst()) : rawRows
        var result: [CSVImportRow] = []

        let categoryByName = Dictionary(categories.map { ($0.name.trimmingCharacters(in: .whitespaces).lowercased(), $0.id) }) { first, _ in first }

        for (offset, rowValues) in rowsToProcess.enumerated() {
            let rowNumber = hasHeader ? (offset + 2) : (offset + 1)

            guard let dateIdx = mapping.dateIndex, dateIdx < rowValues.count,
                  let amountIdx = mapping.amountIndex, amountIdx < rowValues.count else {
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
            if let noteIdx = mapping.noteIndex, noteIdx < rowValues.count {
                note = rowValues[noteIdx].trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if note.isEmpty {
                note = "Imported expense"
            }

            var categoryID = defaultCategoryID
            if let catIdx = mapping.categoryIndex, catIdx < rowValues.count {
                let catRaw = rowValues[catIdx].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if let matched = categoryByName[catRaw] {
                    categoryID = matched
                } else {
                    // Try partial match
                    for (catName, id) in categoryByName {
                        if catName.contains(catRaw) || catRaw.contains(catName) {
                            categoryID = id
                            break
                        }
                    }
                }
            }

            let duplicate = isDuplicate(day: dateParsed.day, amount: amountParsed, note: note, existingExpenses: existingExpenses)

            let expense = Expense(
                id: UUID(),
                amount: amountParsed,
                day: dateParsed.day,
                note: note,
                allocations: [.init(categoryID: categoryID, amount: amountParsed)],
                source: "csv_import",
                createdAt: dateParsed.date,
                bookID: targetBookID
            )

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
        var totalSpending: Int64 = 0

        for row in rows {
            if row.errorMessage != nil || row.parsedExpense == nil {
                errors += 1
            } else if row.isDuplicate {
                duplicates += 1
                if row.isSelectedForImport, let exp = row.parsedExpense {
                    totalSpending += exp.amount
                }
            } else {
                valid += 1
                if row.isSelectedForImport, let exp = row.parsedExpense {
                    totalSpending += exp.amount
                }
            }
        }

        return CSVImportSummary(
            totalRows: rows.count,
            validRows: valid,
            duplicateRows: duplicates,
            errorRows: errors,
            totalSpending: totalSpending
        )
    }
}
