import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let monocleBackup = UTType(exportedAs: "com.farchan.monocle.backup", conformingTo: .json)
}
struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.monocleBackup, .json] }
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
    @State private var candidate: BookBackup?
    @State private var confirm = false
    @State private var message: String?
    var body: some View {
        Form {
            Section {
                Button("Export full backup", systemImage: "square.and.arrow.up") {
                    do {
                        guard let backups = model.backups else { throw BackupError.unsupported }
                        document = BackupDocument(data: try backups.snapshot(draft: model.draft, settings: model.settings).encoded())
                        exporting = true
                    } catch { message = error.localizedDescription }
                }.accessibilityIdentifier("exportBackup")
                Button("Choose backup to restore", systemImage: "arrow.counterclockwise") { importing = true }
                    .accessibilityIdentifier("importBackup")
            } footer: { Text("Includes your sample book, categories, expenses, splits, unfinished draft and settings. Backups are readable JSON files; store them somewhere you trust.") }
            if let candidate {
                Section("Review replacement") {
                    LabeledContent("Book", value: candidate.bookName)
                    LabeledContent("Exported", value: candidate.exportedAt.formatted(date: .abbreviated, time: .shortened))
                    LabeledContent("Expenses", value: String(candidate.expenses.count))
                    LabeledContent("Categories", value: String(candidate.categories.count))
                    LabeledContent("Total", value: Money.format(candidate.total))
                    LabeledContent("Current expenses replaced", value: String(model.expenses.count))
                    Button("Replace current book", role: .destructive) { confirm = true }
                        .accessibilityIdentifier("restoreBackup")
                    Button("Cancel review") { self.candidate = nil }
                }
            }
            Section {
                Button("Export last safety backup") {
                    do {
                        guard let backups = model.backups else { throw BackupError.unsupported }
                        let data = try Data(contentsOf: backups.safetyURL)
                        _ = try BookBackup.decode(data)
                        document = BackupDocument(data: data); exporting = true
                    } catch { message = "No readable safety backup is available yet. One is created before each restoration." }
                }
            } footer: { Text("Restoring replaces this book, including its draft and settings. A local safety backup preserves the previous state. Export it before another restoration if you want to keep it.") }
        }.navigationTitle("Backup & restore")
            .fileExporter(isPresented: $exporting, document: document, contentType: .monocleBackup, defaultFilename: "monocle-\(Day.string(.now)).monoclebackup") { result in
                switch result {
                case .success: message = "Backup exported."
                case .failure(let error): message = error.localizedDescription
                }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.data]) { result in
                do {
                    let url = try result.get()
                    let access = url.startAccessingSecurityScopedResource()
                    defer { if access { url.stopAccessingSecurityScopedResource() } }
                    let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                    guard size <= BookBackup.maximumBytes else { throw BackupError.tooLarge }
                    guard let backups = model.backups else { throw BackupError.unsupported }
                    candidate = try backups.preview(data: Data(contentsOf: url, options: .mappedIfSafe))
                } catch { candidate = nil; message = error.localizedDescription }
            }
            .alert("Replace your current book?", isPresented: $confirm) {
                Button("Replace book", role: .destructive) {
                    guard let candidate else { return }
                    do { try model.restoreBackup(candidate); self.candidate = nil; message = "Book restored. Your previous book is available as the safety backup." }
                    catch { message = error.localizedDescription }
                }
                Button("Cancel", role: .cancel) {}
            } message: { Text("Current expenses, categories, draft and settings will be replaced. A safety backup will be saved first.") }
            .alert("Backup & restore", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK") { message = nil }
            } message: { Text(message ?? "") }
    }
}
