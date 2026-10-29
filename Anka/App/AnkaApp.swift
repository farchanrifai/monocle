import StoreKit
import SwiftUI

@main
struct AnkaApp: App {
    @State private var model = AppModel.shared
    var body: some Scene {
        WindowGroup {
            RootView(model: model)
        }
    }
}

struct RootView: View {
    @Bindable var model: AppModel
    @Environment(\.scenePhase) private var phase
    var body: some View {
        Group {
            if let failure = model.startupError {
                ContentUnavailableView("Unable to open your workspace", systemImage: "externaldrive.badge.exclamationmark", description: Text(failure + "\nThe existing store has not been reset."))
            } else if model.appLock.blocksContent {
                AppLockView(lock: model.appLock)
            } else {
                TabView(selection: $model.selectedTab) {
                    Tab("Home", systemImage: "house", value: 0) {
                        NavigationStack {
                            CardHomeView(model: model)
                                .toolbar(.hidden, for: .navigationBar)
                        }
                        .toolbar(.hidden, for: .tabBar)
                    }
                    Tab("Budgets", systemImage: "chart.pie", value: 1) {
                        NavigationStack { BudgetsView(model: model) }
                            .toolbar(.hidden, for: .tabBar)
                    }
                }
                .toolbar(.hidden, for: .tabBar)
                .safeAreaBar(edge: .bottom) { if model.pushedDepth == 0 { BottomNavigation(model: model) } }
                .tint(MC.red)
                .sheet(isPresented: $model.showEntry, onDismiss: {
                    if !model.draftNeedsConfirmation { model.discardDraft() }
                }) { EntryView(model: model).proPaywall(model) }
                .sensoryFeedback(.success, trigger: model.saveFeedback)
                .modifier(ReviewPrompt(model: model))
                .alert("Discard the unfinished expense?", isPresented: Binding(get: { model.pendingEntry != nil }, set: { if !$0 { model.pendingEntry = nil } })) {
                    Button("Discard and continue", role: .destructive) { model.discardAndOpenPendingEntry() }
                    Button("Keep draft", role: .cancel) { model.pendingEntry = nil }
                } message: { Text("You have an unfinished expense from an interruption. Discard it to open this expense.") }
                .sheet(isPresented: $model.showSettings) { SettingsView(model: model).proPaywall(model) }
                .fullScreenCover(isPresented: $model.showChat) { ChatView(model: model, session: model.chat).proPaywall(model) }
                .modifier(ProPresentation(model: model))
                .alert(model.spendingCurrencyQuestion, isPresented: Binding(get: { model.spendingCurrencySuggestion != nil && !model.showEntry },
                                                                             set: { if !$0 { model.spendingCurrencySuggestion = nil } })) {
                    Button("Use it") { Task { await model.acceptSpendingCurrencySuggestion() } }
                    Button("Not now", role: .cancel) { model.spendingCurrencySuggestion = nil }
                } message: { Text("New expenses on this card will start in that currency, and the card shows an ≈ amount in it.") }
                .alert("Check this", isPresented: Binding(get: { model.error != nil && !model.showEntry }, set: { if !$0 { model.error = nil } })) {
                    Button("OK") { model.error = nil }
                } message: { Text(model.error ?? "") }
            }
        }
        .preferredColorScheme(model.preferredColorScheme)
        #if DEBUG
        // Screenshot hook: ANKA_SCREEN=entry|settings|chat|customize opens that screen on launch.
        .task {
            switch ProcessInfo.processInfo.environment["ANKA_SCREEN"] {
            case "entry": model.openEntry(for: model.activeCardID)
            case "settings": model.showSettings = true
            case "chat": model.showChat = true
            case "customize": if let card = model.orderedCards.last { model.customizerTarget = .existing(card) }
            default: break
            }
        }
        #endif
        .onChange(of: phase) { _, phase in
            if phase != .active {
                model.persistDraft()
                model.appLock.suspend()
            } else {
                model.appLock.resume()
                do { try model.reload() } catch { model.report(error) }
            }
        }
        .onChange(of: model.draft) { _, _ in model.persistDraft() }
        .onOpenURL { url in
            guard url.scheme == "anka" else { return }
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            let queryItems = components?.queryItems ?? []
            let host = url.host ?? ""

            if host == "entry" {
                let catIDStr = queryItems.first(where: { $0.name == "category" })?.value
                let catID = catIDStr.flatMap(UUID.init)
                let cardIDStr = queryItems.first(where: { $0.name == "book" || $0.name == "card" })?.value
                let cardID = cardIDStr.flatMap(UUID.init)
                model.openEntry(for: cardID, categoryID: catID)
            } else if host == "card" || host == "book" {
                let cardIDStr = queryItems.first(where: { $0.name == "id" })?.value
                let cardID = cardIDStr.flatMap(UUID.init) ?? model.activeCardID
                model.openCardInHome(id: cardID)
            } else if host == "stack" {
                let stackIDStr = queryItems.first(where: { $0.name == "id" })?.value
                if let stackID = stackIDStr.flatMap(UUID.init) ?? model.activeStackID {
                    model.openStackInHome(id: stackID)
                }
            } else if host == "home" || host == "today" {
                model.showEntry = false
                model.showSettings = false
                model.selectedTab = 0
            } else if host == "budgets" {
                model.showEntry = false
                model.showSettings = false
                model.selectedTab = 1
            } else if host == "analytics" {
                model.showEntry = false
                model.showSettings = false
                model.selectedTab = 0
                model.showAnalytics = true
            } else if host == "chat" {
                model.showEntry = false
                model.showSettings = false
                model.chatPrefill = queryItems.first(where: { $0.name == "q" })?.value
                model.showChat = true
            } else if host == "session" {
                if url.path == "/end" {
                    model.sessionManager.endSession()
                } else if !model.sessionManager.isSessionActive {
                    model.showStartSessionSheet = true
                }
            }
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
            Text("anka is locked").font(.title2.weight(.semibold))
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

/// Asks for an App Store rating once per version, after the 10th expense saved in this app. The system
/// decides whether the prompt actually shows (at most three times a year).
private struct ReviewPrompt: ViewModifier {
    let model: AppModel
    @Environment(\.requestReview) private var requestReview
    @AppStorage("savesTowardReview") private var saves = 0
    @AppStorage("reviewRequestedVersion") private var requestedVersion = ""

    func body(content: Content) -> some View {
        content.onChange(of: model.saveFeedback) {
            let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
            guard requestedVersion != version else { return }
            saves += 1
            guard saves >= 10 else { return }
            requestedVersion = version
            saves = 0
            Task { try? await Task.sleep(for: .seconds(1)); requestReview() } // after the save sheet closes
        }
    }
}
