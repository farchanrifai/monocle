import SwiftUI

/// First launch: what Monocle does → the workspace currency → the user's card (or a backup) → the Pro trial.
struct OnboardingView: View {
    let model: AppModel
    private enum Step { case welcome, currency, card, trial }
    @State private var step = Step.welcome
    @State private var currency = Locale.current.currency?.identifier ?? "USD"
    @State private var cardName = "My card"
    @State private var keepSample = true
    @State private var error: String?

    /// The device's currency first, then the common ones, then every ISO code by name.
    private var currencies: [String] {
        let common = [Locale.current.currency?.identifier].compactMap { $0 } + Money.commonCurrencies
        let rest = Locale.commonISOCurrencyCodes.filter { !common.contains($0) }.sorted { name($0) < name($1) }
        var seen = Set<String>()
        return (common + rest).filter { seen.insert($0).inserted }
    }

    private func name(_ code: String) -> String { Locale.current.localizedString(forCurrencyCode: code) ?? code }

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .welcome: welcome
                case .currency: currencyStep
                case .card: cardStep
                case .trial: trial
                }
            }
            .animation(.smooth, value: step)
            .alert("Check this", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") { error = nil }
            } message: { Text(error ?? "") }
        }
        .tint(MC.red)
        .interactiveDismissDisabled()
        .proPaywall(model)
        // A restored backup with real cards needs no further setup.
        .onChange(of: model.needsOnboarding) { _, needs in
            if !needs, step != .trial {
                UserDefaults.standard.set(true, forKey: "onboarded")
                model.showOnboarding = false
            }
        }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 28) {
            Spacer()
            Text("monocle").font(.system(size: 44, weight: .bold))
            VStack(alignment: .leading, spacing: 20) {
                feature("creditcard.fill", "A card for each part of life", "Daily spending, a trip, a project: each keeps its own expenses and budget.")
                feature("calendar.badge.clock", "Budgets and bills", "See what's left this month and never miss a recurring payment.")
                feature("lock.shield.fill", "Stays on your iPhone", "No account, no ads, no tracking. Chat runs on Apple Intelligence on the device.")
            }
            Spacer()
            Button { step = .currency } label: { Text("Continue").frame(maxWidth: .infinity) }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .accessibilityIdentifier("onboardingContinue")
        }
        .padding(24)
    }

    private func feature(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol).font(.title2).foregroundStyle(MC.red).frame(width: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    private var currencyStep: some View {
        Form {
            Section {
                Picker("Currency", selection: $currency) {
                    ForEach(currencies, id: \.self) { code in Text("\(name(code)) (\(code))").tag(code) }
                }
                .pickerStyle(.wheel)
                .labelsHidden()
            } footer: {
                Text("Budgets and totals use this currency. Pro adds cards and expenses in other currencies.")
            }
        }
        .navigationTitle("Your currency")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Next") {
                    do { try model.setUpCurrency(currency); step = .card } catch { self.error = error.localizedDescription }
                }
                .accessibilityIdentifier("onboardingCurrencyNext")
            }
        }
    }

    private var cardStep: some View {
        Form {
            Section {
                TextField("Card name", text: $cardName).accessibilityIdentifier("onboardingCardName")
            } header: {
                Text("Your card")
            } footer: {
                Text("Free includes one card. You can rename it any time.")
            }
            Section {
                Toggle("Keep the Sample card", isOn: $keepSample)
            } footer: {
                Text("A practice card with example spending. Try things on it (up to \(Plan.sampleEntries) entries), then hide or delete it.")
            }
            Section {
                NavigationLink("Restore a backup instead") { BackupView(model: model) }
            } footer: {
                Text("Moving from another install? Restore its .monoclebackup file.")
            }
        }
        .navigationTitle("Set up")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Back") { step = .currency } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Next") {
                    do { try model.finishOnboarding(cardName: cardName, keepSample: keepSample); step = .trial }
                    catch { self.error = error.localizedDescription }
                }
                .accessibilityIdentifier("onboardingCardNext")
            }
        }
    }

    private var trial: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "star.circle.fill").font(.system(size: 64)).foregroundStyle(MC.red)
            Text("Try Pro free for a week").font(.title.bold()).multilineTextAlignment(.center)
            Text("More cards and stacks, unlimited bills, widgets, Analytics and every Shortcut. Cancel any time in Settings.")
                .font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Spacer()
            Button { model.paywall = "Try every Pro feature free for a week." } label: { Text("See Pro").frame(maxWidth: .infinity) }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .accessibilityIdentifier("onboardingSeePro")
            Button("Not now") { model.showOnboarding = false }
                .accessibilityIdentifier("onboardingNotNow")
        }
        .padding(24)
        // Buying or closing the paywall ends onboarding too.
        .onChange(of: model.showPaywall) { _, open in if !open { model.showOnboarding = false } }
    }
}
