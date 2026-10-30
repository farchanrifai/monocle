import SwiftUI
import UIKit

struct ChatInputBar: View {
    @Binding var text: String
    var focused: FocusState<Bool>.Binding
    var isBusy: Bool
    var names: [Character: [String]] = [:]
    var onSend: () -> Void

    private var canSend: Bool { !isBusy && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(alignment: .bottom, spacing: 8) {
                MentionTextField(prompt: "Add an expense or ask… (@ card, # category)", text: $text, names: names)
                    .lineLimit(1...5)
                    .focused(focused)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .frame(minHeight: 44) // one line matches the Send button
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 22))
                Button {
                    onSend()
                    // A field that still has marked text (the word being autocorrected) ignores the cleared binding and brings the
                    // old message back on the next keystroke, so the text view is emptied directly. The keyboard stays up.
                    (UIResponder.current as? UITextView)?.text = ""
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

private extension UIResponder {
    private static weak var found: UIResponder?
    /// The first responder, found by sending an action down the responder chain.
    static var current: UIResponder? {
        found = nil
        UIApplication.shared.sendAction(#selector(capture), to: nil, from: nil, for: nil)
        return found
    }
    @objc private func capture() { Self.found = self }
}
