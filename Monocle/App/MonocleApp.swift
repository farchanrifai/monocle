import SwiftUI

@main
struct MonocleApp: App {
    @State private var model = AppModel.shared
    var body: some Scene {
        WindowGroup { RootView(model: model) }
    }
}

struct RootView: View {
    @Bindable var model: AppModel
    @Environment(\.scenePhase) private var phase
    var body: some View {
        Group {
            if let failure = model.startupError {
                ContentUnavailableView("Unable to open your book", systemImage: "externaldrive.badge.exclamationmark", description: Text(failure + "\nThe existing store has not been reset."))
            } else {
                TabView(selection: $model.selectedTab) {
                    Tab("Recents", systemImage: "list.bullet", value: 0) { RecentsView(model: model).toolbar(.hidden, for: .tabBar) }
                    Tab("Budgets", systemImage: "chart.bar.xaxis", value: 1) { BudgetsView(model: model).toolbar(.hidden, for: .tabBar) }
                    Tab("Bills", systemImage: "calendar", value: 2) { BillsView(model: model).toolbar(.hidden, for: .tabBar) }
                }
                .toolbar(.hidden, for: .tabBar)
                .safeAreaBar(edge: .bottom) { BottomNavigation(model: model) }
                .tint(MC.red)
                .sheet(isPresented: $model.showEntry, onDismiss: {
                    if !model.draftNeedsConfirmation { model.discardDraft() }
                }) { EntryView(model: model) }
                .sensoryFeedback(.success, trigger: model.saveFeedback)
                .alert("Discard the unfinished expense?", isPresented: Binding(get: { model.pendingEntry != nil }, set: { if !$0 { model.pendingEntry = nil } })) {
                    Button("Discard and continue", role: .destructive) { model.discardAndOpenPendingEntry() }
                    Button("Keep draft", role: .cancel) { model.pendingEntry = nil }
                } message: { Text("You have an unfinished expense from an interruption. Discard it to open this transaction.") }
                .sheet(isPresented: $model.showSettings) { SettingsView(model: model) }
                .alert("Check this", isPresented: Binding(get: { model.error != nil && !model.showEntry }, set: { if !$0 { model.error = nil } })) {
                    Button("OK") { model.error = nil }
                } message: { Text(model.error ?? "") }
            }
        }
        .onChange(of: phase) { _, phase in
            if phase != .active { model.persistDraft() }
            else { do { try model.reload() } catch { model.error = error.localizedDescription } }
        }
        .onChange(of: model.draft) { _, _ in model.persistDraft() }
        .onOpenURL { url in
            guard url.scheme == "monocle", url.host == "entry" else { return }
            model.openEntry()
        }
    }
}
