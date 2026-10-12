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

/// The user row whose bubble is still flying out of the composer (`ChatSession.flightID`). Its own shape stays invisible
/// and reports where it will rest; `ChatFlightLayer` draws the travelling shape.
extension EnvironmentValues {
    @Entry var chatFlightID: UUID? = nil
}

struct ChatFlightTarget: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) { value = nextValue() ?? value }
}

extension View {
    /// Draws the red bubble shape moving from `from` (the composer field, in this view's coordinates) to the flying bubble's
    /// resting frame as `progress` goes 0 → 1. One-shot: nothing is drawn unless `active`.
    func chatFlightLayer(from: CGRect, progress: CGFloat, active: Bool) -> some View {
        overlayPreferenceValue(ChatFlightTarget.self) { anchor in
            GeometryReader { proxy in
                if active, let anchor, from.width > 0 {
                    let to = proxy[anchor]
                    let t = progress
                    let frame = CGRect(x: from.minX + (to.minX - from.minX) * t, y: from.minY + (to.minY - from.minY) * t,
                                       width: from.width + (to.width - from.width) * t, height: from.height + (to.height - from.height) * t)
                    BubbleShape(isUser: true, hasTail: true).fill(MC.red)
                        .frame(width: frame.width, height: frame.height)
                        .position(x: frame.midX, y: frame.midY)
                }
            }
            .allowsHitTesting(false)
        }
    }
}

extension ChatSession {
    /// Appends the user's bubble inside a spring so its shape flies out of the composer field (`chatFlightLayer`), then lets go of the flight.
    /// `alongside` runs in the same animation (clearing the draft). Returns the row to hand to `send(appended:)`.
    func appendUserRow(_ text: String, animated: Bool, alongside: () -> Void) -> ChatRow {
        let row = ChatRow(kind: .user(text))
        flightID = animated ? row.id : nil
        withAnimation(animated ? .spring(response: 0.45, dampingFraction: 0.82) : nil) {
            alongside()
            rows.append(row)
        }
        if animated {
            Task {
                try? await Task.sleep(for: .milliseconds(800))
                if flightID == row.id { flightID = nil }
            }
        }
        return row
    }
}

struct ChatBubble<Content: View>: View {
    let isUser: Bool
    let hasTail: Bool
    /// Set for a user row; the bubble whose row is the flight hides its shape until the travelling copy lands.
    var rowID: UUID? = nil
    @ViewBuilder let content: Content
    @Environment(\.chatFlightID) fileprivate var flightID
    @State private var landed = false

    fileprivate var flying: Bool { rowID != nil && rowID == flightID }

    var body: some View {
        content
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .foregroundStyle(isUser ? Color.white : Color.primary)
            // The text stays where it will rest and fades in while the shape travels; only the shape morphs, so nothing re-wraps mid-flight.
            .opacity(flying && !landed ? 0 : 1)
            .onAppear { if flying { withAnimation(.easeIn(duration: 0.22).delay(0.18)) { landed = true } } }
            .background { shape }
            .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
            .padding(isUser ? .leading : .trailing, 48)
    }
}

extension ChatBubble {
    @ViewBuilder fileprivate var shape: some View {
        let fill = BubbleShape(isUser: isUser, hasTail: hasTail).fill(isUser ? MC.red : Color.secondary.opacity(0.16))
        if flying { fill.opacity(0).anchorPreference(key: ChatFlightTarget.self, value: .bounds) { $0 } } else { fill }
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
