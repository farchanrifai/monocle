import SwiftUI

@main
struct MonocleApp: App {
    @State private var model = AppModel.shared
    var body: some Scene {
        WindowGroup {
            if ProcessInfo.processInfo.arguments.contains("-book-home-prototype") {
                NavigationStack { BookHomePrototype() }
            } else {
                RootView(model: model)
            }
        }
    }
}

struct RootView: View {
    @Bindable var model: AppModel
    @Environment(\.scenePhase) private var phase
    var body: some View {
        Group {
            if let failure = model.startupError {
                ContentUnavailableView("Unable to open your book", systemImage: "externaldrive.badge.exclamationmark", description: Text(failure + "\nThe existing store has not been reset."))
            } else if model.appLock.blocksContent {
                AppLockView(lock: model.appLock)
            } else {
                TabView(selection: $model.selectedTab) {
                    Tab("Recents", systemImage: "rectangle.stack", value: 0) { BookHomeView(model: model).toolbar(.hidden, for: .tabBar) }
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
        .preferredColorScheme(model.preferredColorScheme)
        .onChange(of: phase) { _, phase in
            if phase != .active {
                model.persistDraft()
                model.appLock.suspend()
            } else {
                model.appLock.resume()
                do { try model.reload() } catch { model.error = error.localizedDescription }
            }
        }
        .onChange(of: model.draft) { _, _ in model.persistDraft() }
        .onOpenURL { url in
            guard url.scheme == "monocle", url.host == "entry" else { return }
            model.openEntry()
        }
    }
}

private struct AppLockView: View {
    @Bindable var lock: AppLockController
    @State private var error: String?

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "lock.fill").font(.system(size: 38)).foregroundStyle(MC.red)
            Text("monocle is locked").font(.title2.weight(.semibold))
            Text("Unlock with Face ID or your device passcode.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            Button {
                Task {
                    let result = await lock.unlock()
                    if case let .failure(error) = result { self.error = error.localizedDescription }
                }
            } label: {
                Label(lock.isAuthenticating ? "Unlocking…" : "Unlock", systemImage: "faceid")
            }
            .buttonStyle(.borderedProminent).tint(MC.red).disabled(lock.isAuthenticating)
            if let error { Text(error).font(.footnote).foregroundStyle(MC.red).multilineTextAlignment(.center) }
            Spacer()
        }
        .padding(28).frame(maxWidth: .infinity, maxHeight: .infinity).background(MC.paper)
        .accessibilityIdentifier("appLockScreen")
    }
}
