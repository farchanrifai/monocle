import SwiftUI
import UniformTypeIdentifiers

struct BackupDocument: FileDocument {
    static let backupType = UTType(exportedAs: "com.farchan.monocle.backup", conformingTo: .data)
    static var readableContentTypes: [UTType] { [backupType, .json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct BackupView: View {
    let model: AppModel
    @State private var document = BackupDocument(data: Data())
    @State private var exporting = false
    @State private var importing = false
    @State private var candidate: WorkspaceBackup?
    @State private var confirm = false
    @State private var message: String?
    var body: some View {
        Form {
            Section {
                Button("Export full backup", systemImage: "square.and.arrow.up") {
                    do {
                        guard let backups = model.backups else { throw BackupError.unsupported }
                        document = BackupDocument(data: try backups.workspaceSnapshot(currentDraft: model.draft, settings: model.settings).encoded())
                        exporting = true
                    } catch { message = error.localizedDescription }
                }.accessibilityIdentifier("exportBackup")
                Button("Choose backup to restore", systemImage: "arrow.counterclockwise") { importing = true }
                    .accessibilityIdentifier("importBackup")
            } footer: { Text("Includes your cards, categories, expenses, splits, budget history, unfinished draft and settings. Backups include all records and card photos; store them somewhere you trust. Older JSON backups remain supported.") }
            if let candidate {
                Section("Review replacement") {
                    LabeledContent("Cards", value: String(candidate.cards.count))
                    LabeledContent("Exported", value: candidate.exportedAt.formatted(date: .abbreviated, time: .shortened))
                    LabeledContent("Expenses", value: String(candidate.cards.reduce(0) { $0 + $1.expenses.count }))
                    LabeledContent("Categories", value: String(candidate.cards.reduce(0) { $0 + $1.categories.count }))
                    LabeledContent("Budget versions", value: String(candidate.cards.reduce(0) { $0 + $1.budgets.count }))
                    LabeledContent("Total", value: Money.format(Money.sum(candidate.cards.flatMap(\.expenses).map(\.amount))))
                    LabeledContent("Current expenses replaced", value: String(model.allExpenses().count))
                    Button("Replace all app data", role: .destructive) { confirm = true }
                        .accessibilityIdentifier("restoreBackup")
                    Button("Cancel review") { self.candidate = nil }
                }
            }
            Section {
                Button("Export last safety backup") {
                    do {
                        guard let backups = model.backups else { throw BackupError.unsupported }
                        let data = try Data(contentsOf: backups.safetyURL)
                        guard (try? CardBackup.decode(data)) != nil || (try? WorkspaceBackup.decode(data)) != nil else {
                            throw BackupError.invalid
                        }
                        document = BackupDocument(data: data); exporting = true
                    } catch { message = "No readable safety backup is available yet. One is created before each restoration." }
                }
            } footer: { Text("Restoring replaces this card, including its draft and settings. A local safety backup preserves the previous state. Export it before another restoration if you want to keep it.") }
        }.navigationTitle("Backup & restore")
            .fileExporter(isPresented: $exporting, document: document, contentType: BackupDocument.backupType, defaultFilename: "monocle-\(Day.string(.now)).monoclebackup") { result in
                switch result {
                case .success: message = "Backup exported."
                case .failure(let error): message = error.localizedDescription
                }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [BackupDocument.backupType, .json, .data]) { result in
                do {
                    let url = try result.get()
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    guard let backups = model.backups else { throw BackupError.unsupported }
                    candidate = try backups.previewWorkspace(data: Data(contentsOf: url, options: .mappedIfSafe))
                } catch { candidate = nil; message = error.localizedDescription }
            }
            .alert("Replace all app data?", isPresented: $confirm) {
                Button("Replace all data", role: .destructive) {
                    guard let candidate else { return }
                    do { try model.restoreWorkspaceBackup(candidate); self.candidate = nil; message = "Backup restored. Your previous data is available as the safety backup." }
                    catch { message = error.localizedDescription }
                }
                Button("Cancel", role: .cancel) {}
            } message: { Text("All cards, expenses, categories, bills, budgets, drafts, artwork and settings will be replaced. A safety backup will be saved first.") }
            .alert("Backup & restore", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK") { message = nil }
            } message: { Text(message ?? "") }
    }
}
