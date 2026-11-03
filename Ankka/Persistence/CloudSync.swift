import CloudKit
import CoreData
import Foundation
import Observation

/// Optional iCloud sync (Pro). Core Data mirrors the store to the user's private CloudKit database; the settings
/// files and card photos ride along as `SyncedFileRecord` rows. Device-only state (App Lock, drafts, the kept card,
/// onboarding and review flags) never leaves the device.
enum CloudSync {
    static let containerID = "iCloud.com.farchan.ankka"
    /// Every save this app makes carries this author, so an iCloud import is anything else in the history.
    static let localAuthor = "app"
    static let enabledKey = "iCloudSync"
    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }
}

extension ExpenseRepository {
    struct SyncedFile { var data: Data; var modifiedAt: Date }

    /// The newest copy of each synced file.
    func syncedFiles() throws -> [String: SyncedFile] {
        var files: [String: SyncedFile] = [:]
        for row in try objects("SyncedFileRecord") {
            guard let name = row.value(forKey: "name") as? String, let data = row.value(forKey: "data") as? Data,
                  let modifiedAt = row.value(forKey: "modifiedAt") as? Date,
                  modifiedAt > files[name]?.modifiedAt ?? .distantPast else { continue }
            files[name] = SyncedFile(data: data, modifiedAt: modifiedAt)
        }
        return files
    }

    func hasSyncedFile(_ name: String) throws -> Bool {
        let request = NSFetchRequest<NSManagedObject>(entityName: "SyncedFileRecord")
        request.predicate = NSPredicate(format: "name == %@", name)
        return try context.count(for: request) > 0
    }

    /// Updates every row with this name (two devices may each have made one; the repair keeps one).
    func saveSyncedFile(_ name: String, data: Data, modifiedAt: Date) throws {
        let request = NSFetchRequest<NSManagedObject>(entityName: "SyncedFileRecord")
        request.predicate = NSPredicate(format: "name == %@", name)
        try transaction {
            var rows = try context.fetch(request)
            if rows.isEmpty { rows = [NSEntityDescription.insertNewObject(forEntityName: "SyncedFileRecord", into: context)] }
            for row in rows {
                row.setValue(name, forKey: "name"); row.setValue(data, forKey: "data"); row.setValue(modifiedAt, forKey: "modifiedAt")
            }
        }
    }

    /// Whether anything but this app wrote the store after `token` (an iCloud import); moves `token` forward.
    func foreignChanges(since token: inout NSPersistentHistoryToken?) -> Bool {
        let request = NSPersistentHistoryChangeRequest.fetchHistory(after: token)
        guard let result = try? context.execute(request) as? NSPersistentHistoryResult,
              let transactions = result.result as? [NSPersistentHistoryTransaction] else { return false }
        if let last = transactions.last { token = last.token }
        return transactions.contains { $0.author != CloudSync.localAuthor }
    }

    /// Deletes the duplicates two devices make while apart (each seeds the Sample card with the same IDs; each can
    /// record the same bill) and keeps what they held. Every device picks the same survivor (highest score, then
    /// CloudKit record name), so their deletes agree; a group waits until all its rows have reached iCloud.
    /// Only deletes and re-points rows, never inserts, so two devices repairing at once converge.
    /// ponytail: scans every row of each entity per refresh; limit it to persistent-history changes if large ledgers stall.
    @discardableResult
    func repairSyncDuplicates(recordName: (NSManagedObject) -> String?) throws -> Bool {
        func id(_ row: NSManagedObject) -> String? { (row.value(forKey: "id") as? UUID)?.uuidString }
        func parent(_ row: NSManagedObject, _ key: String) -> String? {
            (row.value(forKey: key) as? NSManagedObject)?.objectID.uriRepresentation().absoluteString
        }
        func date(_ row: NSManagedObject, _ key: String) -> Double { (row.value(forKey: key) as? Date)?.timeIntervalSince1970 ?? 0 }
        func move(_ children: String, of loser: NSManagedObject, to winner: NSManagedObject, as key: String) {
            for case let child as NSManagedObject in loser.mutableSetValue(forKey: children).allObjects { child.setValue(winner, forKey: key) }
        }
        var changed = false
        try transaction {
            changed = try dedupe("Book", key: id, recordName: recordName) { loser, winner in
                for children in ["expenses", "categories", "budgets", "bills"] { move(children, of: loser, to: winner, as: "book") }
            } || changed
            changed = try dedupe("CategoryRecord", key: { row in id(row).flatMap { id in parent(row, "book").map { "\(id)/\($0)" } } },
                                 recordName: recordName) { loser, winner in
                move("allocations", of: loser, to: winner, as: "category")
            } || changed
            // A bill's expense recorded on two devices has one id; the copy the user edited (amount or note no longer the
            // bill's) wins. ponytail: a category-only edit isn't seen; an updatedAt on ExpenseRecord would be.
            changed = try dedupe("ExpenseRecord", key: id, score: { row in
                guard (row.value(forKey: "source") as? String)?.hasPrefix("bill") == true, let expenseID = row.value(forKey: "id") as? UUID else { return 0 }
                let request = NSFetchRequest<NSManagedObject>(entityName: "BillOccurrenceRecord")
                request.predicate = NSPredicate(format: "expenseID == %@", expenseID as NSUUID)
                request.fetchLimit = 1
                guard let rule = (try? context.fetch(request))?.first?.value(forKey: "rule") as? NSManagedObject else { return 0 }
                let edited = (row.value(forKey: "amount") as? Int64) != (rule.value(forKey: "amount") as? Int64)
                    || (row.value(forKey: "note") as? String) != (rule.value(forKey: "name") as? String)
                return edited ? 1 : 0
            }, recordName: recordName) || changed
            changed = try dedupe("BudgetRecord", key: { row in (row.value(forKey: "effectiveDay") as? String).flatMap { day in parent(row, "book").map { "\(day)/\($0)" } } },
                                 recordName: recordName) || changed
            changed = try dedupe("BillRuleRecord", key: id, recordName: recordName) { loser, winner in
                move("occurrences", of: loser, to: winner, as: "rule")
            } || changed
            // One occurrence per bill and due day; a recorded one wins, and the other copy's bill expense goes with it.
            changed = try dedupe("BillOccurrenceRecord", key: { row in (row.value(forKey: "dueDay") as? String).flatMap { day in parent(row, "rule").map { "\(day)/\($0)" } } },
                                 score: { ($0.value(forKey: "expenseID") == nil ? 0 : 1e12) + date($0, "updatedAt") },
                                 recordName: recordName) { loser, winner in
                guard let expenseID = loser.value(forKey: "expenseID") as? UUID,
                      expenseID != winner.value(forKey: "expenseID") as? UUID else { return }
                let request = NSFetchRequest<NSManagedObject>(entityName: "ExpenseRecord")
                request.predicate = NSPredicate(format: "id == %@ AND source BEGINSWITH %@", expenseID as NSUUID, "bill")
                for expense in try context.fetch(request) { context.delete(expense) }
            } || changed
            changed = try dedupe("SyncedFileRecord", key: { $0.value(forKey: "name") as? String },
                                 score: { date($0, "modifiedAt") }, recordName: recordName) || changed
        }
        return changed
    }

    private func dedupe(_ entity: String, key: (NSManagedObject) -> String?, score: (NSManagedObject) -> Double = { _ in 0 },
                        recordName: (NSManagedObject) -> String?,
                        merge: (_ loser: NSManagedObject, _ winner: NSManagedObject) throws -> Void = { _, _ in }) throws -> Bool {
        var groups: [String: [NSManagedObject]] = [:]
        for row in try objects(entity) { if let key = key(row) { groups[key, default: []].append(row) } }
        var changed = false
        for rows in groups.values where rows.count > 1 {
            let names = rows.compactMap(recordName)
            guard names.count == rows.count else { continue }
            let ranked = zip(rows, names).sorted { (score($0.0), $0.1) > (score($1.0), $1.1) }.map(\.0)
            for loser in ranked.dropFirst() {
                try merge(loser, ranked[0])
                context.delete(loser)
                changed = true
            }
        }
        context.processPendingChanges() // cascades land before the next entity is grouped
        return changed
    }
}

/// The settings files and card photos as `SyncedFileRecord` rows; the newest whole file wins.
@MainActor
final class CloudFileSync {
    static let workspace = "workspace.json", settings = "settings.json", chat = "chat.json", artworkPrefix = "CardArtwork/"
    /// Whole files, newest wins: two devices changing one between syncs keep the later.
    static let documents = [workspace, settings, chat]
    /// Settings keys that stay on this device: the open card and App Lock.
    static let localSettingsKeys = ["book", "appLockTimeout"]
    static let adoptedKey = "iCloudSyncAdopted", stampsKey = "iCloudSyncStamps"

    var enabled: Bool
    private let repository: ExpenseRepository
    private let directory: URL
    private let artworks: CardArtworkStore
    private let defaults: UserDefaults
    private var applying = false

    init(repository: ExpenseRepository, directory: URL, artworks: CardArtworkStore = .shared, defaults: UserDefaults = .standard) {
        self.repository = repository
        self.directory = directory
        self.artworks = artworks
        self.defaults = defaults
        enabled = repository.partialGraph
    }

    /// Whether this device has taken iCloud's copy once since sync was turned on. Nothing goes up before that,
    /// so a new device's fresh settings never replace the ones already in iCloud.
    var adopted: Bool {
        get { defaults.bool(forKey: Self.adoptedKey) }
        set { defaults.set(newValue, forKey: Self.adoptedKey); if !newValue { stamps = [:] } }
    }
    /// The iCloud date of each settings file this device holds.
    private var stamps: [String: Date] {
        get { defaults.dictionary(forKey: Self.stampsKey) as? [String: Date] ?? [:] }
        set { defaults.set(newValue, forKey: Self.stampsKey) }
    }

    /// After a local write of a settings file, the chat or a card photo.
    func upload(_ name: String, data: Data) throws {
        guard enabled, adopted, !applying else { return }
        // A photo's file name is unique and its bytes never change, so one copy in iCloud is enough.
        if name.hasPrefix(Self.artworkPrefix), try repository.hasSyncedFile(name) { return }
        let now = Date.now
        try repository.saveSyncedFile(name, data: name == Self.settings ? Self.sharedSettings(data) : data, modifiedAt: now)
        if !name.hasPrefix(Self.artworkPrefix) { stamps[name] = now }
    }

    /// The first import on this device: iCloud's settings replace this device's, this device's photos go up.
    func adopt() throws {
        guard enabled, !adopted else { return }
        adopted = true
        let remote = try repository.syncedFiles()
        for name in Self.documents where remote[name] == nil {
            if let data = try? Data(contentsOf: directory.appendingPathComponent(name)) { try upload(name, data: data) }
        }
        let photos = (try? FileManager.default.contentsOfDirectory(atPath: artworks.artworkDirectory.path)) ?? []
        for filename in photos where CardArtworkStore.isValidFilename(filename) && remote[Self.artworkPrefix + filename] == nil {
            if let data = artworks.loadArtworkData(filename: filename) { try upload(Self.artworkPrefix + filename, data: data) }
        }
        _ = try pull()
    }

    /// Writes iCloud's newer settings, chat and missing photos to this device; true when anything changed.
    func pull() throws -> Bool {
        guard enabled, adopted else { return false }
        applying = true
        defer { applying = false }
        var changed = false
        var stamps = self.stamps
        for (name, file) in try repository.syncedFiles() {
            if name.hasPrefix(Self.artworkPrefix) {
                let filename = String(name.dropFirst(Self.artworkPrefix.count))
                guard CardArtworkStore.isValidFilename(filename), artworks.loadArtworkData(filename: filename) == nil else { continue }
                try artworks.importArtworkData(file.data, filename: filename)
                changed = true
            } else if Self.documents.contains(name), file.modifiedAt > stamps[name] ?? .distantPast {
                let url = directory.appendingPathComponent(name)
                let data = name == Self.settings ? try Self.merged(remote: file.data, local: try? Data(contentsOf: url)) : file.data
                // A copy this version can't read (a newer app on the other device) stays in iCloud, untouched here.
                let readable = switch name {
                case Self.settings: (try? JSONDecoder().decode(PrototypeSettings.self, from: data)) != nil
                case Self.workspace: (try? JSONDecoder().decode(WorkspacePreferences.self, from: data)) != nil
                default: (try? JSONSerialization.jsonObject(with: data)) is [String: Any]
                }
                guard readable else { continue }
                try data.write(to: url, options: .atomic)
                stamps[name] = file.modifiedAt
                changed = true
            }
        }
        self.stamps = stamps
        return changed
    }

    static func sharedSettings(_ data: Data) throws -> Data {
        var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        for key in localSettingsKeys { object.removeValue(forKey: key) }
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    static func merged(remote: Data, local: Data?) throws -> Data {
        var object = try JSONSerialization.jsonObject(with: remote) as? [String: Any] ?? [:]
        let mine = local.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        for key in localSettingsKeys { object[key] = mine[key] }
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }
}

/// Listens for iCloud imports, repairs duplicates, pulls synced files and refreshes the app.
@MainActor @Observable
final class CloudSyncMonitor {
    private(set) var isEnabled: Bool
    private(set) var lastSync: Date?
    private(set) var problem: String?
    @ObservationIgnored weak var model: AppModel?
    @ObservationIgnored let files: CloudFileSync
    @ObservationIgnored private let repository: ExpenseRepository
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var token: NSPersistentHistoryToken?
    @ObservationIgnored private var pending: Task<Void, Never>?
    @ObservationIgnored private var observers: [any NSObjectProtocol] = []

    init(repository: ExpenseRepository, directory: URL, defaults: UserDefaults = .standard) {
        self.repository = repository
        self.defaults = defaults
        files = CloudFileSync(repository: repository, directory: directory, defaults: defaults)
        isEnabled = repository.partialGraph
        token = repository.container.persistentStoreCoordinator.currentPersistentHistoryToken(fromStores: nil)
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .NSPersistentStoreRemoteChange, object: repository.container.persistentStoreCoordinator,
                                            queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleRefresh() }
        })
        observers.append(center.addObserver(forName: NSPersistentCloudKitContainer.eventChangedNotification, object: repository.container,
                                            queue: .main) { [weak self] note in
            guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey] as? NSPersistentCloudKitContainer.Event,
                  let end = event.endDate else { return }
            let failure = event.error?.localizedDescription, isImport = event.type == .import
            MainActor.assumeIsolated { self?.finished(at: end, failure: failure, isImport: isImport) }
        })
    }

    /// Reopens the store with or without mirroring; the data on this device stays either way.
    func setEnabled(_ on: Bool) throws {
        guard on != isEnabled else { return }
        try repository.setCloudSync(on)
        defaults.set(on, forKey: CloudSync.enabledKey)
        isEnabled = on
        files.enabled = on
        if !on { files.adopted = false; problem = nil; lastSync = nil }
        token = repository.container.persistentStoreCoordinator.currentPersistentHistoryToken(fromStores: nil)
        model?.applySyncedChanges()
    }

    /// A local write of a settings file or card photo.
    func upload(_ name: String, data: Data) {
        do { try files.upload(name, data: data) } catch { problem = error.localizedDescription }
    }

    /// Repairs, pulls files and reloads the app. Runs at launch and after each import.
    func refresh() {
        guard isEnabled else { return }
        do {
            try repository.repairSyncDuplicates { [repository] row in repository.container.recordID(for: row.objectID)?.recordName }
            _ = try files.pull()
        } catch { problem = error.localizedDescription }
        model?.applySyncedChanges()
    }

    private func finished(at end: Date, failure: String?, isImport: Bool) {
        guard isEnabled else { return }
        problem = failure
        guard failure == nil else { return }
        lastSync = end
        if isImport && !files.adopted {
            do { try files.adopt() } catch { problem = error.localizedDescription }
            refresh()
        }
    }

    /// Imports arrive in bursts; one refresh after they settle.
    private func scheduleRefresh() {
        guard isEnabled else { return }
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled, let self, self.repository.foreignChanges(since: &self.token) else { return }
            self.refresh()
        }
    }
}
