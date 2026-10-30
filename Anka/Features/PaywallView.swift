import StoreKit
import SwiftUI

/// Where the store listing, paywall and Settings link to. Replace the privacy page once it is hosted.
enum AppLinks {
    static let terms = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    static let privacy = URL(string: "https://pakaryan.com/anka/privacy")! // site repo ~/Xcode/pakaryan
    static let support = URL(string: "mailto:anka@pakaryan.com?subject=Anka%20support")!
}

/// Apple's subscription sheet with the Free vs Pro comparison on top. Apple takes the payment.
struct PaywallView: View {
    let model: AppModel
    /// Why it opened, e.g. "Free includes one card." Empty for a plain upgrade.
    let reason: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SubscriptionStoreView(productIDs: ProStore.productIDs) { PaywallHeader(reason: reason) }
        .subscriptionStoreButtonLabel(.multiline)
        .storeButton(.visible, for: .restorePurchases, .redeemCode)
        .subscriptionStorePolicyDestination(url: AppLinks.terms, for: .termsOfService)
        .subscriptionStorePolicyDestination(url: AppLinks.privacy, for: .privacyPolicy)
        .tint(MC.red)
        .onInAppPurchaseCompletion { _, result in
            if case .success(.success) = result {
                await model.pro?.refresh()
                dismiss()
            }
        }
        .accessibilityIdentifier("paywall")
    }
}

/// The paywall's top: what Pro adds, as a Free vs Pro table.
struct PaywallHeader: View {
    let reason: String

    /// Mirrors docs/planning/app-store-release.md ▸ Free and Pro.
    private static let rows: [(feature: String, free: String, pro: String)] = [
        ("Cards", "1", "Unlimited + Stacks"),
        ("Bills", "3", "Unlimited"),
        ("Currencies", "Yours", "Any, with rates"),
        ("Analytics", "Totals", "Trends"),
        ("Widgets", "—", "All + Live Activities"),
        ("Shortcuts", "Add Expense", "All"),
        ("Chat", "\(Plan.freeQuestionsPerDay) a day", "Unlimited"),
        ("Card looks", "Default", "Customizer"),
        ("CSV", "Export", "Import too"),
    ]

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "creditcard.and.123")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(MC.red)
            Text("Anka Pro").font(.largeTitle.bold())
            if !reason.isEmpty {
                Text(reason).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            comparison
            Text("Renews automatically until cancelled. Cancel anytime in Settings › Subscriptions. Backup, export and App Lock are always free.")
                .multilineTextAlignment(.center)
                .font(.footnote).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
    }

    private var comparison: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
            GridRow {
                Text("")
                Text("Free").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text("Pro").font(.caption.weight(.semibold)).foregroundStyle(MC.red)
            }
            ForEach(Self.rows, id: \.feature) { row in
                GridRow {
                    Text(row.feature).font(.subheadline.weight(.medium))
                    Text(row.free).font(.subheadline).foregroundStyle(.secondary)
                    Text(row.pro).font(.subheadline)
                }
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// A lapsed subscriber with several cards picks the one that stays writable. Shown until they choose.
struct KeptCardPicker: View {
    let model: AppModel
    @State private var choice: UUID?
    @State private var confirming = false

    private var cards: [Card] { model.cards.filter { $0.kind == .real } }

    var body: some View {
        NavigationStack {
            List(cards) { card in
                Button { choice = card.id } label: {
                    HStack {
                        Text(card.name).foregroundStyle(Color.primary)
                        Spacer()
                        if choice == card.id { Image(systemName: "checkmark").foregroundStyle(MC.red) }
                    }
                }
                .accessibilityIdentifier("keptCard-\(card.name)")
            }
            .safeAreaInset(edge: .top) {
                Text("Free includes one card. Pick the one you'll keep adding to; the others stay viewable, exportable and deletable.")
                    .font(.callout).foregroundStyle(.secondary).padding(.horizontal).padding(.vertical, 8)
            }
            .navigationTitle("Keep one card")
            .scrollEdgeEffectStyle(.soft, for: .all)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Keep") { confirming = true }.disabled(choice == nil)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Upgrade") { model.paywall = "" }
                }
            }
            .alert("Keep this card?", isPresented: $confirming) {
                Button("Keep") { model.keptCardID = choice }
                Button("Cancel", role: .cancel) {}
            } message: { Text("You can't change this later. Upgrading to Pro unlocks every card again.") }
            .proPaywall(model)
        }
        // Preselect the card in use, else the first real one (the Sample card isn't a choice).
        .onAppear { choice = choice ?? (cards.contains { $0.id == model.activeCardID } ? model.activeCardID : cards.first?.id) }
        .interactiveDismissDisabled()
    }
}

extension View {
    /// Presents the paywall from this view when the model asks for it. Attach to the root and to each sheet,
    /// since a sheet can only present from the topmost view.
    func proPaywall(_ model: AppModel, when topmost: Bool = true) -> some View {
        sheet(isPresented: Binding(get: { topmost && model.showPaywall }, set: { model.showPaywall = $0 })) {
            #if DEBUG
            // A simctl launch has no StoreKit products, so Apple's sheet hides the header; this shows it alone.
            if ProcessInfo.processInfo.environment["ANKA_SHOW_PAYWALL"] == "header" {
                ScrollView { PaywallHeader(reason: model.paywall ?? "") }
            } else {
                PaywallView(model: model, reason: model.paywall ?? "")
            }
            #else
            PaywallView(model: model, reason: model.paywall ?? "")
            #endif
        }
    }
}

/// The root's paywall, onboarding and, after a lapse, the kept-card picker (kept out of RootView's long modifier chain).
struct ProPresentation: ViewModifier {
    let model: AppModel
    func body(content: Content) -> some View {
        content
            // Only when nothing covers the root: a second presenter for the same paywall makes SwiftUI tear down
            // and rebuild the presented screen (onboarding restarted at its first step).
            .proPaywall(model, when: !model.showOnboarding && !model.needsKeptCardChoice && !model.showSettings && !model.showEntry && !model.showChat)
            .fullScreenCover(isPresented: Binding(get: { model.needsKeptCardChoice && !model.showPaywall && !model.showOnboarding }, set: { _ in })) {
                KeptCardPicker(model: model)
            }
            .fullScreenCover(isPresented: Binding(get: { model.showOnboarding }, set: { model.showOnboarding = $0 })) {
                OnboardingView(model: model)
            }
    }
}
