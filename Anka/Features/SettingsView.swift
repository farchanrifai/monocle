import StoreKit
import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.requestReview) private var requestReview

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

    /// System follows iOS; Light and Dark pin it.
    private var appearance: Binding<AppearanceMode?> {
        Binding(get: { model.autoAppearance ? nil : model.manualAppearance },
                set: { mode in
                    if let mode { model.manualAppearance = mode } else { model.autoAppearance = true }
                })
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
                    Picker(selection: appearance) {
                        Text("System").tag(AppearanceMode?.none)
                        Text("Light").tag(AppearanceMode?.some(.light))
                        Text("Dark").tag(AppearanceMode?.some(.dark))
                    } label: {
                        Label { Text("Appearance") } icon: { SettingsIcon(symbol: "circle.lefthalf.filled", color: .blue) }
                    }
                    .accessibilityIdentifier("appearancePicker")
                    Picker(selection: $model.visualDirection) {
                        ForEach(CardVisualDirection.allCases) { Text($0.rawValue).tag($0) }
                    } label: {
                        Label { Text("Theme style") } icon: { SettingsIcon(symbol: "paintpalette.fill", color: .purple) }
                    }
                    .accessibilityIdentifier("themeStylePicker")
                } header: {
                    Text("Appearance")
                }

                Section {
                    NavigationLink {
                        AppLockSettingsView(model: model)
                    } label: {
                        row("App lock", "lock.shield.fill", MC.red, value: model.settings.appLockTimeout?.title ?? "Off")
                    }
                    .accessibilityIdentifier("appLockSettings")
                } header: {
                    Text("Privacy & Security")
                } footer: {
                    Text("Anka keeps your spending on this device. App lock asks for Face ID or your passcode when you come back.")
                }

                Section {
                    NavigationLink {
                        BackupView(model: model)
                    } label: {
                        row("Backup & restore", "arrow.triangle.2.circlepath", .blue)
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
                    Text("Reset saves a safety backup first.")
                }

                Section {
                    Button { requestReview() } label: {
                        Label { Text("Rate Anka").foregroundStyle(Color.primary) } icon: { SettingsIcon(symbol: "heart.fill", color: .pink) }
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
                    Text("Anka \(info?["CFBundleShortVersionString"] as? String ?? "") (\(info?["CFBundleVersion"] as? String ?? ""))")
                        .frame(maxWidth: .infinity).padding(.top, 12)
                }
            }
            .listStyle(.insetGrouped)
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
                        Text(model.isPro ? "Anka Pro" : "Upgrade to Anka Pro").font(.title3.weight(.semibold)).foregroundStyle(Color.primary)
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
                    do { try await model.pro?.restore() } catch { model.error = error.localizedDescription }
                    restoring = false
                }
            } label: {
                proLabel(restoring ? "Restoring…" : "Restore purchases", "arrow.clockwise", .blue)
            }
            .disabled(restoring)
            Button { redeeming = true } label: { proLabel("Redeem code", "gift.fill", .pink) }
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
                Text("Lock after leaving Anka")
            } footer: {
                Text("Turning this on or changing its timeout confirms your device authentication. Anka covers its interface while it is in the app switcher, then asks for Face ID or your device passcode when the timeout has elapsed.")
            }
            Section("Shortcuts") {
                Text("Both Anka Shortcuts always use the system device-authentication policy. A background text shortcut can add an expense only after that system check; it does not unlock the app screen. Quick entry may still show this lock when Anka opens.")
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
