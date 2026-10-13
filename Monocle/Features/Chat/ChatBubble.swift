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

extension EnvironmentValues {
    /// The user row whose bubble is still growing in (`ChatSession.flightID`).
    @Entry var chatFlightID: UUID? = nil
}

extension ChatSession {
    /// WhatsApp-style send: the bubble appears in its slot at 30% size and grows in place from its tail corner (`GrowIn`, `growDuration`),
    /// the rows above easing up with it on `whatsappGrow`. (The iMessage-style flight was removed; tag `chat-flight-imessage` keeps it.)
    static let growDuration = 0.3
    static let whatsappGrow = Animation.timingCurve(0.15, 0.6, 0.25, 1, duration: 0.3)
    static let replyAnimation = Animation.spring(duration: 0.45, bounce: 0.12)

    /// Appends the user's bubble inside the grow animation; `alongside` runs in the same animation (clearing the draft).
    /// Returns the row to hand to `send(appended:)`.
    func appendUserRow(_ text: String, animated: Bool, alongside: () -> Void) -> ChatRow {
        let row = ChatRow(kind: .user(text))
        flightID = animated ? row.id : nil
        withAnimation(animated ? Self.whatsappGrow : nil) {
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
    /// Set for a user row; the bubble whose row is `flightID` grows in.
    var rowID: UUID? = nil
    @ViewBuilder let content: Content
    @Environment(\.chatFlightID) fileprivate var flightID

    fileprivate var growing: Bool { rowID != nil && rowID == flightID }

    var body: some View {
        content
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .foregroundStyle(isUser ? Color.white : Color.primary)
            .background(BubbleShape(isUser: isUser, hasTail: hasTail).fill(isUser ? MC.red : Color.secondary.opacity(0.16)))
            .modifier(GrowIn(active: growing, anchor: isUser ? .bottomTrailing : .bottomLeading))
            .transition(rowID != nil ? .identity : .opacity)
            .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
            .padding(isUser ? .leading : .trailing, 48)
    }
}

/// Scales the bubble up from its tail corner, driven by the clock rather than by a state change, so the first (small) frame
/// can never wait on an animation transaction: it starts the moment the view is born and eases out over `ChatSession.growDuration`.
private struct GrowIn: ViewModifier {
    var active: Bool
    var anchor: UnitPoint
    @State private var born = Date()

    func body(content: Content) -> some View {
        TimelineView(.animation(paused: !active)) { context in
            let t = min(max(context.date.timeIntervalSince(born) / ChatSession.growDuration, 0), 1)
            content.scaleEffect(active ? 0.3 + 0.7 * (1 - pow(1 - t, 3)) : 1, anchor: anchor)
        }
    }
}

struct TypingDots: View {
    var body: some View {
        Image(systemName: "ellipsis")
            .font(.title3.weight(.bold))
            .symbolEffect(.variableColor.iterative.dimInactiveLayers)
            .foregroundStyle(.secondary)
    }
}
