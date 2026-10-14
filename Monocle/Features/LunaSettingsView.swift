import SwiftUI

/// Opt-in and per-part switches for sharing with the owner's Luna server (see `LunaBridge`).
struct LunaSettingsView: View {
    var model: AppModel
    @AppStorage(LunaBridge.enabledKey) private var enabled = false
    @AppStorage(LunaBridge.partKey(.bills)) private var bills = true
    @AppStorage(LunaBridge.partKey(.budgets)) private var budgets = true
    @AppStorage(LunaBridge.partKey(.summary)) private var summary = true

    private var canShare: Bool { APIKeyStore.read().map(LunaProxy.isProxyToken) == true }
    private var bridge: LunaBridge { model.lunaBridge }

    var body: some View {
        Form {
            Section {
                Toggle("Share with Luna", isOn: $enabled)
                    .disabled(!canShare)
                    .accessibilityIdentifier("lunaShareToggle")
            } footer: {
                Text(canShare
                     ? "Sends card, bill and category names, bill dates, budget totals and monthly totals to your Luna server (luna-server.farchan.workers.dev). Individual expenses and notes are never sent. Turn this off to stop; nothing is sent while it is off."
                     : "Register this iPhone with an invite code in AI Chat first. Sharing needs the Luna connection, not a personal API key.")
            }
            if enabled && canShare {
                Section("What to share") {
                    Toggle("Bills and due dates", isOn: $bills)
                    Toggle("Budgets", isOn: $budgets)
                    Toggle("Monthly totals by category", isOn: $summary)
                }
                Section {
                    LabeledContent("Last update", value: bridge.lastSync.map { $0.formatted(.relative(presentation: .named)) } ?? "Not yet")
                    if let error = bridge.lastError { Text(error).foregroundStyle(.red).font(.footnote) }
                    Button(bridge.isSending ? "Sending…" : "Send now") { Task { await bridge.push() } }
                        .disabled(bridge.isSending)
                }
            }
        }
        .navigationTitle("Luna")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: enabled) { _, on in if on { bridge.schedule(after: .seconds(1)) } }
        .onChange(of: bills) { _, _ in bridge.schedule(after: .seconds(1)) }
        .onChange(of: budgets) { _, _ in bridge.schedule(after: .seconds(1)) }
        .onChange(of: summary) { _, _ in bridge.schedule(after: .seconds(1)) }
    }
}
