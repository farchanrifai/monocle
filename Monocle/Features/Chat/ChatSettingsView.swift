import SwiftUI

/// Opt-in switch, disclosure and personal API key for AI chat (CHAT_SPEC §0 rule 6, §9).
struct ChatSettingsView: View {
    @AppStorage("chatEnabled") private var chatEnabled = false
    @AppStorage("chatBackend") private var backend = "claude"
    @State private var keyDraft = ""
    @State private var hasKey = APIKeyStore.read() != nil

    var body: some View {
        Form {
            Section {
                Toggle("Enable AI chat", isOn: $chatEnabled)
                    .accessibilityIdentifier("chatEnabledToggle")
                Picker("Model", selection: $backend) {
                    Text("Claude").tag("claude")
                    Text("Apple Intelligence").tag("apple")
                }
            } footer: {
                Text(backend == "apple"
                     ? (AppleChatAgent.unavailableReason ?? "Chat runs on this iPhone with Apple Intelligence; nothing leaves the device. Expenses are only saved when you tap Save.")
                     : "Your messages, plus the spending data needed to answer them (amounts, dates, notes, category and card names), are sent to Anthropic's Claude. Nothing is sent until you use chat, and expenses are only saved when you tap Save.")
            }

            if backend == "claude" { Section {
                if hasKey {
                    LabeledContent("API key", value: "Saved on this iPhone")
                    Button("Remove key", role: .destructive) {
                        APIKeyStore.delete()
                        hasKey = false
                    }
                } else {
                    SecureField("sk-ant-…", text: $keyDraft)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("chatAPIKeyField")
                    Button("Save key") {
                        hasKey = APIKeyStore.save(keyDraft.trimmingCharacters(in: .whitespacesAndNewlines))
                        keyDraft = ""
                    }
                    .disabled(keyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            } header: {
                Text("Anthropic API key")
            } footer: {
                Text("Stored in the Keychain on this device only. Create one at platform.claude.com.")
            } }
        }
        .navigationTitle("AI Chat")
        .navigationBarTitleDisplayMode(.inline)
    }
}
