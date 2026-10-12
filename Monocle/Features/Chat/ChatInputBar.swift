import SwiftUI

struct ChatInputBar: View {
    @Binding var text: String
    var focused: FocusState<Bool>.Binding
    var isBusy: Bool
    var names: [Character: [String]] = [:]
    var onSend: () -> Void

    private var canSend: Bool { !isBusy && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            MentionTextField(prompt: "Add an expense or ask… (@ card, # category)", text: $text, names: names)
                .lineLimit(1...5)
                .focused(focused)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))
            Button(action: onSend) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(canSend ? MC.red : Color.secondary.opacity(0.4), in: Circle())
            }
            .buttonStyle(PressFeedbackStyle())
            .disabled(!canSend)
            .accessibilityLabel("Send")
            .accessibilityIdentifier("chatSend")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(alignment: .bottom) {
            ProgressiveBlur(edge: .bottom, solid: 56, fade: 36, tint: Color(uiColor: .systemBackground))
                .ignoresSafeArea(edges: .bottom)
        }
    }
}
