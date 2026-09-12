import SwiftUI
import UniformTypeIdentifiers

// MARK: - CSV Document for FileExporter

struct CSVFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText, .plainText] }
    var text: String

    init(text: String = "") {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        if let data = configuration.file.regularFileContents {
            text = String(decoding: data, as: UTF8.self)
        } else {
            text = ""
        }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = Data(text.utf8)
        return FileWrapper(regularFileWithContents: data)
    }
}

// MARK: - CSV Interchange View

struct CSVInterchangeView: View {
    @Bindable var model: AppModel
    var initialTab: Int = 0
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTab: Int
    @State private var exportScope: ExportScope = .activeBook
    @State private var exportDateRange: CSVDateRangeScope = .allTime
    @State private var customStartDate: Date = Calendar.current.date(byAdding: .day, value: -30, to: .now) ?? .now
    @State private var customEndDate: Date = .now
    @State private var isExporting = false
    @State private var exportDocument = CSVFileDocument()

    // Import State
    @State private var isFileImporterPresented = false
    @State private var importedFileName: String = ""
    @State private var importedRawRows: [[String]] = []
    @State private var detectedDelimiter: Character = ","
    @State private var columnMapping = CSVColumnMapping()
    @State private var targetBookID: UUID
    @State private var defaultCategoryID: UUID?
    @State private var skipDuplicates = true
    @State private var processedRows: [CSVImportRow] = []
    @State private var importErrorMessage: String?
    @State private var showImportConfirmation = false

    enum ExportScope: String, CaseIterable, Identifiable {
        case activeBook = "Current card"
        case allBooks = "All cards"
        var id: String { rawValue }
    }

    init(model: AppModel, initialTab: Int = 0) {
        self.model = model
        self.initialTab = initialTab
        _selectedTab = State(initialValue: initialTab)
        _targetBookID = State(initialValue: model.activeBookID)
    }

    private var targetBookCategories: [ExpenseCategory] {
        model.activeCategories
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Interchange Mode", selection: $selectedTab) {
                    Text("Export").tag(0)
                    Text("Import").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .accessibilityIdentifier("csvModePicker")

                if selectedTab == 0 {
                    exportView
                } else {
                    importView
                }
            }
            .navigationTitle("CSV Data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("dismissCSVView")
                }
            }
            .fileExporter(
                isPresented: $isExporting,
                document: exportDocument,
                contentType: .commaSeparatedText,
                defaultFilename: "monocle-expenses-\(Day.string(.now)).csv"
            ) { result in
                switch result {
                case .success:
                    model.showToast("CSV exported successfully")
                case .failure(let error):
                    model.showToast("Export failed: \(error.localizedDescription)")
                }
            }
            .fileImporter(
                isPresented: $isFileImporterPresented,
                allowedContentTypes: [.commaSeparatedText, .tabSeparatedText, .plainText]
            ) { result in
                handleFileSelection(result)
            }
            .alert("Import Expenses?", isPresented: $showImportConfirmation) {
                Button("Import", role: .none) {
                    executeImport()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                let count = processedRows.filter { $0.isSelectedForImport && $0.parsedExpense != nil }.count
                let bookName = model.books.first { $0.id == targetBookID }?.name ?? "selected card"
                Text("Are you sure you want to import \(count) expenses into \(bookName)?")
            }
            .onAppear {
                if defaultCategoryID == nil {
                    defaultCategoryID = targetBookCategories.first?.id
                }
            }
        }
    }

    // MARK: - Export View

    private var exportView: some View {
        Form {
            Section("Export Scope & Filters") {
                Picker("Scope", selection: $exportScope) {
                    ForEach(ExportScope.allCases) { scope in
                        Text(scope.rawValue).tag(scope)
                    }
                }
                .accessibilityIdentifier("exportScopePicker")

                Picker("Date Range", selection: $exportDateRange) {
                    ForEach(CSVDateRangeScope.allCases) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .accessibilityIdentifier("exportDateRangePicker")

                if exportDateRange == .custom {
                    DatePicker("From", selection: $customStartDate, displayedComponents: .date)
                    DatePicker("To", selection: $customEndDate, displayedComponents: .date)
                }
            }

            let exportExpenses = currentExportExpenses()
            let totalSpent = exportExpenses.reduce(0) { $0 + $1.amount }

            Section("Summary") {
                LabeledContent("Transactions", value: "\(exportExpenses.count)")
                LabeledContent("Total Spending", value: Money.format(totalSpent))
            }

            Section("Preview (First 3 Rows)") {
                let sampleCSV = model.csvExportText(
                    for: exportScope == .activeBook ? model.activeBookID : nil,
                    dateRange: exportDateRange,
                    customStartDate: customStartDate,
                    customEndDate: customEndDate
                )
                let previewLines = sampleCSV.components(separatedBy: "\r\n").prefix(4).joined(separator: "\n")
                Text(previewLines.isEmpty ? "No records to export" : previewLines)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(5)
            }

            Section {
                Button {
                    let csvText = model.csvExportText(
                        for: exportScope == .activeBook ? model.activeBookID : nil,
                        dateRange: exportDateRange,
                        customStartDate: customStartDate,
                        customEndDate: customEndDate
                    )
                    exportDocument = CSVFileDocument(text: csvText)
                    isExporting = true
                } label: {
                    Label("Export to File", systemImage: "square.and.arrow.up")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .disabled(exportExpenses.isEmpty)
                .accessibilityIdentifier("exportCSVButton")

                if !exportExpenses.isEmpty {
                    let csvContent = model.csvExportText(
                        for: exportScope == .activeBook ? model.activeBookID : nil,
                        dateRange: exportDateRange,
                        customStartDate: customStartDate,
                        customEndDate: customEndDate
                    )
                    ShareLink(item: csvContent, preview: SharePreview("Monocle Expenses CSV", image: Image(systemName: "tablecells"))) {
                        Label("Share CSV", systemImage: "square.and.arrow.up.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .accessibilityIdentifier("shareCSVLink")
                }
            } footer: {
                Text("Exports RFC 4180 standard CSV including Date, Time, Book, Category, whole IDR Amount, Note, and Source.")
            }
        }
    }

    private func currentExportExpenses() -> [Expense] {
        let rawList: [Expense]
        if exportScope == .activeBook {
            rawList = model.expenses(for: model.activeBookID)
        } else {
            var all: [Expense] = []
            for b in model.books {
                all.append(contentsOf: model.expenses(for: b.id))
            }
            rawList = all
        }

        let calendar = Calendar.current
        let now = Date.now
        switch exportDateRange {
        case .allTime:
            return rawList
        case .thisMonth:
            let start = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
            let startDay = Day.string(start)
            return rawList.filter { $0.day >= startDay }
        case .lastMonth:
            guard let prevMonth = calendar.date(byAdding: .month, value: -1, to: now),
                  let startOfLast = calendar.date(from: calendar.dateComponents([.year, .month], from: prevMonth)),
                  let startOfThis = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) else { return rawList }
            let startDay = Day.string(startOfLast)
            let endDay = Day.string(startOfThis)
            return rawList.filter { $0.day >= startDay && $0.day < endDay }
        case .custom:
            let startDay = Day.string(min(customStartDate, customEndDate))
            let endDay = Day.string(max(customStartDate, customEndDate))
            return rawList.filter { $0.day >= startDay && $0.day <= endDay }
        }
    }

    // MARK: - Import View

    private var importView: some View {
        Form {
            Section {
                Button {
                    isFileImporterPresented = true
                } label: {
                    HStack {
                        Image(systemName: "doc.badge.plus")
                            .font(.title2)
                            .foregroundStyle(MC.red)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(importedFileName.isEmpty ? "Select CSV File" : importedFileName)
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Text(importedRawRows.isEmpty ? "Tap to browse files" : "Delimiter: \(delimiterName(detectedDelimiter)) · \(importedRawRows.count - 1) data rows")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 4)
                }
                .accessibilityIdentifier("selectCSVButton")
            } header: {
                Text("Source File")
            }

            if let importErrorMessage {
                Section {
                    Label(importErrorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(MC.red)
                        .font(.footnote)
                }
            }

            if !importedRawRows.isEmpty {
                Section("Target Card & Category") {
                    Picker("Destination Card", selection: $targetBookID) {
                        ForEach(model.books) { book in
                            Text(book.name).tag(book.id)
                        }
                    }
                    .onChange(of: targetBookID) { _, _ in
                        reprocessImportRows()
                    }
                    .accessibilityIdentifier("importDestinationBookPicker")

                    if let chosenCat = defaultCategoryID {
                        Picker("Default Category", selection: Binding(
                            get: { chosenCat },
                            set: { defaultCategoryID = $0; reprocessImportRows() }
                        )) {
                            ForEach(targetBookCategories) { cat in
                                Label(cat.name, systemImage: cat.symbol).tag(cat.id)
                            }
                        }
                        .accessibilityIdentifier("importDefaultCategoryPicker")
                    }

                    Toggle("Skip Suspected Duplicates", isOn: $skipDuplicates)
                        .onChange(of: skipDuplicates) { _, skip in
                            for idx in processedRows.indices {
                                if processedRows[idx].isDuplicate {
                                    processedRows[idx].isSelectedForImport = !skip
                                }
                            }
                        }
                        .accessibilityIdentifier("skipDuplicatesToggle")
                }

                Section("Column Mapping") {
                    let headers = importedRawRows.first ?? []
                    Picker("Date Column", selection: Binding(
                        get: { columnMapping.dateIndex ?? -1 },
                        set: { columnMapping.dateIndex = $0 >= 0 ? $0 : nil; reprocessImportRows() }
                    )) {
                        Text("Not selected").tag(-1)
                        ForEach(Array(headers.enumerated()), id: \.offset) { idx, header in
                            Text(header.isEmpty ? "Column \(idx + 1)" : header).tag(idx)
                        }
                    }
                    .accessibilityIdentifier("dateColumnPicker")

                    Picker("Amount Column", selection: Binding(
                        get: { columnMapping.amountIndex ?? -1 },
                        set: { columnMapping.amountIndex = $0 >= 0 ? $0 : nil; reprocessImportRows() }
                    )) {
                        Text("Not selected").tag(-1)
                        ForEach(Array(headers.enumerated()), id: \.offset) { idx, header in
                            Text(header.isEmpty ? "Column \(idx + 1)" : header).tag(idx)
                        }
                    }
                    .accessibilityIdentifier("amountColumnPicker")

                    Picker("Note Column", selection: Binding(
                        get: { columnMapping.noteIndex ?? -1 },
                        set: { columnMapping.noteIndex = $0 >= 0 ? $0 : nil; reprocessImportRows() }
                    )) {
                        Text("None (Default Note)").tag(-1)
                        ForEach(Array(headers.enumerated()), id: \.offset) { idx, header in
                            Text(header.isEmpty ? "Column \(idx + 1)" : header).tag(idx)
                        }
                    }

                    Picker("Category Column", selection: Binding(
                        get: { columnMapping.categoryIndex ?? -1 },
                        set: { columnMapping.categoryIndex = $0 >= 0 ? $0 : nil; reprocessImportRows() }
                    )) {
                        Text("None (Use Default Category)").tag(-1)
                        ForEach(Array(headers.enumerated()), id: \.offset) { idx, header in
                            Text(header.isEmpty ? "Column \(idx + 1)" : header).tag(idx)
                        }
                    }
                }

                // Summary Chips
                let summary = CSVImportParser.summarize(rows: processedRows)
                Section {
                    HStack(spacing: 12) {
                        summaryChip(title: "Ready", count: summary.validRows, color: .green)
                        summaryChip(title: "Duplicate", count: summary.duplicateRows, color: .orange)
                        summaryChip(title: "Error", count: summary.errorRows, color: .red)
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))

                    LabeledContent("Total Spending to Add", value: Money.format(summary.totalSpending))
                } header: {
                    Text("Import Preview & Review")
                }

                // Parsed Rows Preview
                Section("Rows to Import (\(processedRows.filter(\.isSelectedForImport).count))") {
                    ForEach(processedRows) { row in
                        importRowView(row)
                    }
                }

                // Action Button
                let eligible = processedRows.filter { $0.isSelectedForImport && $0.parsedExpense != nil }
                Section {
                    Button {
                        showImportConfirmation = true
                    } label: {
                        Label("Import \(eligible.count) Expenses", systemImage: "arrow.down.doc.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .foregroundStyle(Color.white)
                    }
                    .listRowBackground(eligible.isEmpty ? Color.gray.opacity(0.3) : MC.red)
                    .disabled(eligible.isEmpty)
                    .accessibilityIdentifier("executeImportButton")
                }
            }
        }
    }

    private func summaryChip(title: String, count: Int, color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(count)")
                .font(.title3.weight(.bold).monospacedDigit())
                .foregroundStyle(color)
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }

    private func importRowView(_ row: CSVImportRow) -> some View {
        HStack(spacing: 12) {
            if row.errorMessage != nil {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
            } else {
                Button {
                    toggleRowSelection(row.id)
                } label: {
                    Image(systemName: row.isSelectedForImport ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(row.isSelectedForImport ? MC.red : Color.secondary.opacity(0.4))
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 3) {
                if let exp = row.parsedExpense {
                    HStack {
                        Text(Day.title(exp.day))
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(Money.format(exp.amount))
                            .font(.subheadline.weight(.bold).monospacedDigit())
                    }
                    HStack(spacing: 6) {
                        Text(exp.note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer()
                        if row.isDuplicate {
                            Text("DUPLICATE")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.orange)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(Color.orange.opacity(0.15)))
                        }
                    }
                } else {
                    Text("Row #\(row.rowNumber)")
                        .font(.subheadline.weight(.semibold))
                    Text(row.errorMessage ?? "Invalid row")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func toggleRowSelection(_ id: UUID) {
        if let idx = processedRows.firstIndex(where: { $0.id == id }) {
            processedRows[idx].isSelectedForImport.toggle()
        }
    }

    private func delimiterName(_ char: Character) -> String {
        switch char {
        case ",": return "Comma (,)"
        case ";": return "Semicolon (;)"
        case "\t": return "Tab (\\t)"
        default: return String(char)
        }
    }

    // MARK: - Import Logic

    private func handleFileSelection(_ result: Result<URL, any Error>) {
        do {
            let url = try result.get()
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }

            let fileSize = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard fileSize <= BookBackup.maximumBytes else { throw BackupError.tooLarge }
            let data = try Data(contentsOf: url)
            guard data.count <= BookBackup.maximumBytes else { throw BackupError.tooLarge }
            guard let content = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
                throw NSError(domain: "MonocleCSV", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to read CSV text encoding."])
            }

            importedFileName = url.lastPathComponent
            detectedDelimiter = CSVTokenizer.sniffDelimiter(from: content)
            let rows = CSVTokenizer.parse(content: content, delimiter: detectedDelimiter)
            guard rows.count <= 10_001 else { throw BackupError.tooLarge }
            guard rows.count > 1 else {
                throw NSError(domain: "MonocleCSV", code: 2, userInfo: [NSLocalizedDescriptionKey: "CSV has no data rows."])
            }

            importedRawRows = rows
            importErrorMessage = nil

            // Auto-detect column mapping
            let headers = rows.first ?? []
            columnMapping = CSVImportParser.detectColumnMapping(headers: headers)

            reprocessImportRows()
        } catch {
            importErrorMessage = error.localizedDescription
            importedRawRows = []
            processedRows = []
        }
    }

    private func reprocessImportRows() {
        let categories = targetBookCategories
        if !categories.contains(where: { $0.id == defaultCategoryID }) { defaultCategoryID = categories.first?.id }
        guard !importedRawRows.isEmpty, let defaultCat = defaultCategoryID else {
            processedRows = []
            return
        }
        let existingExpenses = model.expenses(for: targetBookID)

        let parsed = CSVImportParser.processRows(
            rawRows: importedRawRows,
            hasHeader: true,
            mapping: columnMapping,
            targetBookID: targetBookID,
            categories: targetBookCategories,
            defaultCategoryID: defaultCat,
            existingExpenses: existingExpenses
        )

        // Apply skipDuplicates filter
        var adjusted = parsed
        if skipDuplicates {
            for i in adjusted.indices {
                if adjusted[i].isDuplicate {
                    adjusted[i].isSelectedForImport = false
                }
            }
        }
        processedRows = adjusted
    }

    private func executeImport() {
        let toImport = processedRows.filter { $0.isSelectedForImport }.compactMap { $0.parsedExpense }
        guard !toImport.isEmpty else { return }

        do {
            try model.importExpenses(toImport, to: targetBookID)
            dismiss()
        } catch {
            importErrorMessage = "Failed to import: \(error.localizedDescription)"
        }
    }
}
