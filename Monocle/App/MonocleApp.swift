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
                    Tab("Recents", systemImage: "list.bullet", value: 0) { RecentsView(model: model) }
                    Tab("Budgets", systemImage: "chart.bar.xaxis", value: 1) { BudgetsView(model: model) }
                    Tab("Bills", systemImage: "calendar", value: 2) { BillsView(model: model) }
                }
                .tint(MC.red)
                .sheet(isPresented: $model.showEntry) { EntryView(model: model) }
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
