import StoreKit
import SwiftUI

struct SettingsView: View {
    #if DEBUG
    @State private var debugRoadmap = ProcessInfo.processInfo.environment["ANKKA_SCREEN"] == "roadmap"
    #endif
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.requestReview) private var requestReview
    @AppStorage(ClaudeConsent.key) private var claudeChoice: Bool?
    @AppStorage("lastBackupExport") private var lastBackupExport: Double = 0

    /// Icon badge + title, with an optional trailing value. One look for every settings row.
    @ViewBuilder
    private func row(_ title: LocalizedStringKey, _ symbol: String, _ color: Color, value: String? = nil) -> some View {
        let label = Label { Text(title) } icon: { SettingsIcon(symbol: symbol, color: color) }
        if let value {
            LabeledContent { Text(value).foregroundStyle(.secondary).lineLimit(1) } label: { label }
        } else {
            label
        }
    }

    /// System follows iOS (Light by day, Dark at night); the other choices pin one look.
    private var appearance: Binding<CardVisualDirection?> {
        Binding(get: { model.autoAppearance ? nil : model.visualDirection },
                set: { direction in
                    guard let direction else { model.autoAppearance = true; return }
                    model.autoAppearance = false
                    model.visualDirection = direction
                })
    }

    private var dataFooter: String {
        guard let cloud = model.cloud else { return "Reset saves a safety backup first." }
        var text = "iCloud sync (Pro) keeps your cards, expenses, settings and chat the same on each iPhone and iPad with your Apple Account; App lock stays on each device. While it's on, Restore and Reset change every synced device. Reset saves a safety backup first."
        if cloud.isEnabled, let problem = cloud.problem { text += "\n\niCloud: \(problem)" }
        else if cloud.isEnabled, let last = cloud.lastSync { text += "\n\nLast synced \(last.formatted(.relative(presentation: .named)))." }
        return text
    }

    var body: some View {
        NavigationStack {
            List {
                if model.pro != nil { SubscriptionSection(model: model) }

                Section {
                    NavigationLink {
                        CategoryManager(model: model)
                    } label: {
                        row("Categories", "tag.fill", .orange, value: "\(model.globalCategories.count)")
                    }
                    .accessibilityIdentifier("manageCategories")
                    NavigationLink {
                        PaymentMethodsView(model: model, cardID: nil)
                    } label: {
                        row("Paid with labels", "creditcard.and.123", .mint, value: model.paymentMethods.isEmpty ? "None" : "\(model.paymentMethods.count)")
                    }
                    .accessibilityIdentifier("paidWithSettings")
                    NavigationLink {
                        CurrencySettingsView(model: model, cardID: nil)
                    } label: {
                        row("Reporting currency", "banknote.fill", .green, value: model.reportingCurrency)
                    }
                    .accessibilityIdentifier("currencySettings")
                    NavigationLink {
                        EntryFormSettingsView(model: model)
                    } label: {
                        row("Add sheet fields", "list.bullet.rectangle", .blue)
                    }
                    .accessibilityIdentifier("entryFormSettings")
                    NavigationLink {
                        ShortcutOrderSettingsView(model: model)
                    } label: {
                        row("Shortcut input order", "arrow.up.arrow.down.square.fill", .pink)
                    }
                    .accessibilityIdentifier("shortcutOrderSettings")
                } header: {
                    Text("Adding expenses")
                } footer: {
                    Text("A card's own currency, default Paid with label and categories are in Customize Card.")
                }

                Section {
                    // One choice: a second "theme" picker that also pinned light or dark read as a bug.
                    Picker(selection: appearance) {
                        Text("System").tag(CardVisualDirection?.none)
                        ForEach(CardVisualDirection.allCases) { Text($0 == .instrument ? "Dark" : $0.rawValue).tag(Optional($0)) }
                    } label: {
                        Label { Text("Appearance") } icon: { SettingsIcon(symbol: "circle.lefthalf.filled", color: .blue) }
                    }
                    .accessibilityIdentifier("appearancePicker")
                } header: {
                    Text("Appearance")
                } footer: {
                    Text("System switches between Light and Dark with your iPhone. Ledger is a light look, Signal a dark one.")
                }

                Section {
                    Toggle(isOn: Binding(get: { claudeChoice == true }, set: { claudeChoice = $0 })) {
                        Label { Text("Chat with Claude") } icon: { SettingsIcon(symbol: "bubble.left.and.text.bubble.right.fill", color: .orange) }
                    }
                    .disabled(!model.isPro)
                    .accessibilityIdentifier("claudeChatToggle")
                    NavigationLink {
                        AppLockSettingsView(model: model)
                    } label: {
                        row("App lock", "lock.shield.fill", MC.red, value: model.settings.appLockTimeout?.title ?? "Off")
                    }
                    .accessibilityIdentifier("appLockSettings")
                } header: {
                    Text("Privacy & Security")
                } footer: {
                    Text("Ankka keeps your spending on this device, and in your iCloud when iCloud sync is on. Chat with Claude (Pro) sends each chat message, with the spending details it needs, to Anthropic to answer it; off, chat uses Apple Intelligence on this iPhone. App lock asks for Face ID or your passcode when you come back.")
                }

                Section {
                    if let cloud = model.cloud {
                        Toggle(isOn: Binding(get: { cloud.isEnabled }, set: { model.setCloudSync($0) })) {
                            Label { Text("iCloud sync") } icon: { SettingsIcon(symbol: "icloud.fill", color: .blue) }
                        }
                        .accessibilityIdentifier("iCloudSyncToggle")
                    }
                    NavigationLink {
                        BackupView(model: model)
                    } label: {
                        row("Backup & restore", "arrow.triangle.2.circlepath", .blue,
                            value: lastBackupExport == 0 ? "Not exported" : Date(timeIntervalSinceReferenceDate: lastBackupExport).formatted(.dateTime.day().month(.abbreviated)))
                    }
                    .accessibilityIdentifier("backupSettings")
                    NavigationLink {
                        CSVInterchangeView(model: model, showsDismissButton: false)
                    } label: {
                        row("CSV export & import", "tablecells.fill", .teal)
                    }
                    .accessibilityIdentifier("csvInterchangeSettings")
                    NavigationLink {
                        ResetDataView(model: model)
                    } label: {
                        Label { Text("Reset data").foregroundStyle(MC.red) } icon: { SettingsIcon(symbol: "trash.fill", color: MC.red) }
                    }
                    .accessibilityIdentifier("resetDataSettings")
                } header: {
                    Text("Data")
                } footer: {
                    Text(dataFooter)
                }

                Section {
                    NavigationLink { WhatsNewHistoryView() } label: {
                        Label { Text("What's new") } icon: { SettingsIcon(symbol: "sparkles", color: MC.red) }
                    }
                    NavigationLink { RoadmapView() } label: {
                        Label { Text("Roadmap") } icon: { SettingsIcon(symbol: "map.fill", color: .green) }
                    }
                    Button { requestReview() } label: {
                        Label { Text("Rate Ankka").foregroundStyle(Color.primary) } icon: { SettingsIcon(symbol: "heart.fill", color: .pink) }
                    }
                    Link(destination: AppLinks.support) {
                        row("Contact support", "envelope.fill", .blue)
                    }
                    .accessibilityIdentifier("supportSettings")
                    Link(destination: AppLinks.privacy) {
                        row("Privacy policy", "hand.raised.fill", .gray)
                    }
                    Link(destination: AppLinks.terms) {
                        row("Terms of use", "doc.text.fill", .gray)
                    }
                } header: {
                    Text("About")
                } footer: {
                    let info = Bundle.main.infoDictionary
                    Text("Ankka \(info?["CFBundleShortVersionString"] as? String ?? "") (\(info?["CFBundleVersion"] as? String ?? ""))")
                        .frame(maxWidth: .infinity).padding(.top, 12)
                }
            }
            .listStyle(.insetGrouped)
            #if DEBUG
            .navigationDestination(isPresented: $debugRoadmap) { RoadmapView() } // ANKKA_SCREEN=roadmap
            #endif
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .confirm) { dismiss() } label: { Image(systemName: "checkmark") }
                        .accessibilityLabel("Done")
                }
            }
        }
    }
}

/// Pro status as the screen's lead row, then restore and offer codes. Apple's own sheets handle managing and redeeming.
private struct SubscriptionSection: View {
    let model: AppModel
    @State private var managing = false
    @State private var redeeming = false
    @State private var restoring = false
    @State private var restoreResult: String?

    private func proLabel(_ title: LocalizedStringKey, _ symbol: String, _ color: Color) -> some View {
        Label { Text(title).foregroundStyle(Color.primary) } icon: { SettingsIcon(symbol: symbol, color: color) }
    }

    var body: some View {
        Section {
            Button {
                if model.isPro { managing = true } else { model.paywall = "" }
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "star.fill")
                        .font(.title2.weight(.semibold)).foregroundStyle(.white)
                        .frame(width: 56, height: 56)
                        .background(MC.red.gradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(model.isPro ? "Ankka Pro" : "Upgrade to Ankka Pro").font(.title3.weight(.semibold)).foregroundStyle(Color.primary)
                        Text(model.isPro ? "Active · Manage subscription"
                             : "Every card, unlimited bills and chat. Free: one card, \(Plan.freeBills) bills, \(Plan.freeQuestionsPerDay) questions a day.")
                            .font(.subheadline).foregroundStyle(Color.secondary)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                }
                .padding(.vertical, 6)
            }
            .accessibilityIdentifier(model.isPro ? "manageSubscription" : "upgradeToPro")
            Button {
                restoring = true
                Task {
                    do {
                        try await model.pro?.restore()
                        restoreResult = model.isPro ? "Ankka Pro is active." : "No Ankka Pro purchase was found for this Apple Account."
                    } catch StoreKitError.userCancelled {
                    } catch { restoreResult = error.localizedDescription }
                    restoring = false
                }
            } label: {
                proLabel(restoring ? "Restoring…" : "Restore purchases", "arrow.clockwise", .blue)
            }
            .disabled(restoring)
            Button { redeeming = true } label: { proLabel("Redeem code", "gift.fill", .pink) }
        }
        .alert(restoreResult ?? "", isPresented: Binding(get: { restoreResult != nil }, set: { if !$0 { restoreResult = nil } })) {
            Button("OK") { restoreResult = nil }
        }
        .manageSubscriptionsSheet(isPresented: $managing)
        .offerCodeRedemption(isPresented: $redeeming) { _ in Task { await model.pro?.refresh() } }
    }
}

struct AppLockSettingsView: View {
    let model: AppModel
    @State private var error: String?
    @State private var saving = false

    var body: some View {
        Form {
            Section {
                if let timeout = model.settings.appLockTimeout {
                    LabeledContent { Text(timeout.title) } label: { Text("Current setting") }
                    Button("Turn off app lock", role: .destructive) { update(nil) }
                        .disabled(saving)
                } else {
                    Text("Off").foregroundStyle(.secondary)
                }
                ForEach(AppLockTimeout.allCases) { timeout in
                    Button { update(timeout) } label: {
                        HStack {
                            Text(timeout.title)
                            Spacer()
                            if timeout == model.settings.appLockTimeout { Image(systemName: "checkmark").foregroundStyle(MC.red) }
                        }
                    }
                    .disabled(saving || timeout == model.settings.appLockTimeout)
                }
            } header: {
                Text("Lock after leaving Ankka")
            } footer: {
                Text("Turning this on or changing its timeout confirms your device authentication. Ankka covers its interface while it is in the app switcher, then asks for Face ID or your device passcode when the timeout has elapsed.")
            }
            Section("Shortcuts") {
                Text("Ankka's Shortcuts ask for Face ID or your passcode before they run. A Shortcut that adds an expense in the background doesn't unlock the app; opening Ankka may still show this lock.")
            }
            if saving { HStack { Spacer(); ProgressView("Saving app lock…"); Spacer() } }
            if let error { Text(error).foregroundStyle(MC.red) }
        }
        .navigationTitle("App lock").navigationBarTitleDisplayMode(.inline)
    }

    private func update(_ timeout: AppLockTimeout?) {
        saving = true
        Task {
            let result = await model.setAppLockTimeout(timeout)
            saving = false
            if case let .failure(error) = result { self.error = error.localizedDescription }
        }
    }
}
