import SwiftUI

struct ChatInputBar: View {
    @Binding var text: String
    var focused: FocusState<Bool>.Binding
    var isBusy: Bool
    var names: [Character: [String]] = [:]
    var onSend: () -> Void

    /// Changes on every send. A TextField that still has marked text (the word being autocorrected) ignores the cleared binding and
    /// brings the old message back on the next keystroke, so Send gives the field a new identity and refocuses it.
    @State private var fieldID = UUID()

    private var canSend: Bool { !isBusy && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(alignment: .bottom, spacing: 8) {
                MentionTextField(prompt: "Add an expense or ask… (@ card, # category)", text: $text, names: names)
                    .id(fieldID)
                    .lineLimit(1...5)
                    .focused(focused)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))
                Button {
                    let refocus = focused.wrappedValue
                    onSend()
                    fieldID = UUID()
                    if refocus { Task { @MainActor in focused.wrappedValue = true } }
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(canSend ? Color.white : Color.secondary)
                        .frame(width: 44, height: 44)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                // Liquid Glass: red-tinted and interactive when it can send, plain inert glass when it can't.
                .glassEffect(canSend ? .regular.tint(MC.red.opacity(0.85)).interactive() : .regular, in: .circle)
                .disabled(!canSend)
                .accessibilityLabel("Send")
                .accessibilityIdentifier("chatSend")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
