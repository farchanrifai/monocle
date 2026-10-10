import AppKit
import UniformTypeIdentifiers
import SwiftUI

struct MacDataTransferView: View {
    @Bindable var state: MacAppState
    let mode: DataTransferSheet
    @Environment(\.dismiss) private var dismiss
    @State private var message: String?
    @State private var candidate: WorkspaceBackup?
    @State private var rawRows: [[String]] = []
    @State private var headers: [String] = []
    @State private var mapping = CSVColumnMapping()
    @State private var hasHeader = true
    @State private var targetCardID: UUID?
    @State private var defaultCategoryID: UUID?
    @State private var importRows: [CSVImportRow] = []

    private var model: AppModel { state.model }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title).font(.title2.bold())
            switch mode {
            case .importCSV: csvImport
            case .exportCSV: exportDescription("Export expenses as a CSV file for spreadsheets.", action: exportCSV)
            case .exportBackup: exportDescription("Create a complete Monocle backup for transfer between iPhone and Mac.", action: exportBackup)
            case .restoreBackup: restoreView
            }
            if let message { Text(message).foregroundStyle(message.hasPrefix("Saved") || message.hasPrefix("Imported") ? .green : .red) }
            Spacer(minLength: 0)
            HStack { Spacer(); Button("Close", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction) }
        }.padding(24).frame(minWidth: 620, minHeight: 420)
        .onAppear { targetCardID = model.activeCardID; defaultCategoryID = model.activeCategories.first?.id }
    }

    private var title: String {
        switch mode { case .importCSV: "Import CSV"; case .exportCSV: "Export CSV"; case .exportBackup: "Export Backup"; case .restoreBackup: "Restore Backup" }
    }

    private func exportDescription(_ text: String, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(text, systemImage: mode == .exportCSV ? "tablecells" : "externaldrive")
            Button(title + "…", action: action).buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder private var csvImport: some View {
        if rawRows.isEmpty {
            Text("Choose a UTF-8 CSV. Monocle detects Date, Amount, Note, and Category columns and reviews every row before saving.")
            Button("Choose CSV…", action: chooseCSV).buttonStyle(.borderedProminent)
        } else {
            HStack {
                Picker("Card", selection: $targetCardID) { ForEach(model.cards) { Text($0.name).tag(Optional($0.id)) } }
                Picker("Default category", selection: $defaultCategoryID) { ForEach(model.activeCategories) { Text($0.name).tag(Optional($0.id)) } }
                Toggle("Header row", isOn: $hasHeader)
            }
            Grid(alignment: .leading) {
                mappingPicker("Date", selection: $mapping.dateIndex)
                mappingPicker("Amount", selection: $mapping.amountIndex)
                mappingPicker("Note", selection: $mapping.noteIndex)
                mappingPicker("Category", selection: $mapping.categoryIndex)
            }
            Button("Review Rows", action: reviewCSV).disabled(!mapping.isValid || targetCardID == nil || defaultCategoryID == nil)
            if !importRows.isEmpty {
                let summary = CSVImportParser.summarize(rows: importRows)
                Text("\(summary.validRows) valid • \(summary.duplicateRows) duplicates • \(summary.errorRows) errors • \(Money.format(summary.totalSpending ?? 0))")
                    .font(.headline)
                Table(importRows) {
                    TableColumn("Import") { row in
                        Toggle("", isOn: Binding(get: { importRows.first(where: { $0.id == row.id })?.isSelectedForImport ?? false }, set: { value in
                            if let index = importRows.firstIndex(where: { $0.id == row.id }) { importRows[index].isSelectedForImport = value }
                        })).labelsHidden().disabled(row.parsedExpense == nil)
                    }.width(55)
                    TableColumn("Row") { Text("\($0.rowNumber)") }.width(45)
                    TableColumn("Status") { row in Text(row.errorMessage ?? (row.isDuplicate ? "Duplicate" : "Ready")) }
                    TableColumn("Amount") { row in Text(row.parsedExpense.map { Money.format($0.amount) } ?? "—").font(.system(.body, design: .monospaced)) }
                    TableColumn("Note") { Text($0.parsedExpense?.note ?? "") }
                }.frame(minHeight: 160)
                Button("Import Selected", action: importCSV).buttonStyle(.borderedProminent)
            }
        }
    }

    private func mappingPicker(_ title: String, selection: Binding<Int?>) -> some View {
        GridRow {
            Text(title)
            Picker(title, selection: selection) {
                Text("Not mapped").tag(Int?.none)
                ForEach(headers.indices, id: \.self) { Text(headers[$0].isEmpty ? "Column \($0 + 1)" : headers[$0]).tag(Optional($0)) }
            }.labelsHidden().frame(width: 260)
        }
    }

    @ViewBuilder private var restoreView: some View {
        if let candidate {
            let expenses = candidate.cards.reduce(0) { $0 + $1.expenses.count }
            Label("Validated Monocle backup", systemImage: "checkmark.shield.fill").foregroundStyle(.green)
            LabeledContent("Exported", value: candidate.exportedAt.formatted())
            LabeledContent("Cards", value: "\(candidate.cards.count)")
            LabeledContent("Expenses", value: "\(expenses)")
            Text("Restoring replaces the current Mac workspace after Monocle creates its safety backup.").foregroundStyle(.secondary)
            Button("Restore Workspace", role: .destructive, action: restore).buttonStyle(.borderedProminent)
        } else {
            Text("Choose an iPhone or Mac .monoclebackup file. Monocle validates it in memory before offering restore.")
            Button("Choose Backup…", action: chooseBackup).buttonStyle(.borderedProminent)
        }
    }

    private func chooseCSV() {
        guard let url = openPanel(types: [.commaSeparatedText, .plainText]) else { return }
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            rawRows = try CSVTokenizer.parse(content: content, delimiter: CSVTokenizer.sniffDelimiter(from: content))
            guard let first = rawRows.first else { throw CocoaError(.fileReadCorruptFile) }
            headers = first
            mapping = CSVImportParser.detectColumnMapping(headers: first)
            message = nil
        } catch { message = error.localizedDescription }
    }

    private func reviewCSV() {
        guard let targetCardID, let defaultCategoryID else { return }
        importRows = CSVImportParser.processRows(rawRows: rawRows, hasHeader: hasHeader, mapping: mapping, targetCardID: targetCardID,
                                                 categories: model.activeCategories(for: targetCardID), defaultCategoryID: defaultCategoryID,
                                                 existingExpenses: model.expenses(for: targetCardID), paymentMethods: model.paymentMethods)
    }

    private func importCSV() {
        guard let targetCardID else { return }
        let expenses = importRows.filter(\.isSelectedForImport).compactMap(\.parsedExpense)
        do { try model.importExpenses(expenses, to: targetCardID); message = "Imported \(expenses.count) expenses." }
        catch { message = error.localizedDescription }
    }

    private func exportCSV() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.commaSeparatedText]; panel.nameFieldStringValue = "monocle-expenses.csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try model.csvExportText(for: nil, dateRange: .allTime).write(to: url, atomically: true, encoding: .utf8); message = "Saved \(url.lastPathComponent)." }
        catch { message = error.localizedDescription }
    }

    private func exportBackup() {
        guard let backups = model.backups else { message = BackupError.unsupported.localizedDescription; return }
        let panel = NSSavePanel(); panel.allowedContentTypes = [UTType(filenameExtension: "monoclebackup") ?? .json]
        panel.nameFieldStringValue = "monocle-\(Day.string(.now)).monoclebackup"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try backups.workspaceSnapshot(currentDraft: model.draft, settings: model.settings).encoded().write(to: url, options: .atomic); message = "Saved \(url.lastPathComponent)." }
        catch { message = error.localizedDescription }
    }

    private func chooseBackup() {
        guard let backups = model.backups, let url = openPanel(types: [UTType(filenameExtension: "monoclebackup") ?? .json]) else { return }
        do { candidate = try backups.previewWorkspace(data: Data(contentsOf: url)); message = nil }
        catch { message = error.localizedDescription }
    }

    private func restore() {
        guard let candidate else { return }
        do { try model.restoreWorkspaceBackup(candidate); message = "Restore completed."; self.candidate = nil }
        catch { message = error.localizedDescription }
    }

    private func openPanel(types: [UTType]) -> URL? {
        let panel = NSOpenPanel(); panel.allowedContentTypes = types; panel.allowsMultipleSelection = false; panel.canChooseDirectories = false
        return panel.runModal() == .OK ? panel.url : nil
    }
}
