import SwiftUI

/// Rounded bubble with an optional Messages-style tail on the sender's bottom corner.
struct BubbleShape: Shape {
    var isUser: Bool
    var hasTail: Bool

    func path(in rect: CGRect) -> Path {
        let bubble = Path(roundedRect: rect, cornerRadius: 18, style: .continuous)
        guard hasTail else { return bubble }
        let x = isUser ? rect.maxX : rect.minX
        let d: CGFloat = isUser ? 1 : -1
        var tail = Path()
        tail.move(to: CGPoint(x: x, y: rect.maxY - 16))
        tail.addQuadCurve(to: CGPoint(x: x + 5 * d, y: rect.maxY), control: CGPoint(x: x, y: rect.maxY - 4))
        tail.addQuadCurve(to: CGPoint(x: x - 12 * d, y: rect.maxY - 1), control: CGPoint(x: x - 3 * d, y: rect.maxY))
        tail.addLine(to: CGPoint(x: x - 12 * d, y: rect.maxY - 16))
        tail.closeSubpath()
        return bubble.union(tail)
    }
}

struct ChatBubble<Content: View>: View {
    let isUser: Bool
    let hasTail: Bool
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .foregroundStyle(isUser ? Color.white : Color.primary)
            .background(BubbleShape(isUser: isUser, hasTail: hasTail).fill(isUser ? MC.red : Color.secondary.opacity(0.16)))
            .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
            .padding(isUser ? .leading : .trailing, 48)
    }
}

struct TypingBubble: View {
    var body: some View {
        ChatBubble(isUser: false, hasTail: true) {
            Image(systemName: "ellipsis")
                .font(.title3.weight(.bold))
                .symbolEffect(.variableColor.iterative.dimInactiveLayers)
                .foregroundStyle(.secondary)
        }
        .accessibilityLabel("Monocle is typing")
    }
}
