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

/// Shared geometry between the composer field and the bubble it becomes, so a sent message morphs out of the field as in Messages.
struct ChatFlight {
    var namespace: Namespace.ID
    var id: UUID?
}

extension EnvironmentValues {
    @Entry var chatFlight: ChatFlight? = nil
}

extension ChatSession {
    /// Appends the user's bubble inside a spring so its shape grows out of the composer field (`ChatFlight`), then lets go of the flight.
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
    /// Set for a user row; the bubble whose row is the flight morphs from the composer field.
    var rowID: UUID? = nil
    @ViewBuilder let content: Content
    @Environment(\.chatFlight) fileprivate var flight
    @State private var landed = false

    fileprivate var flying: Bool { rowID != nil && rowID == flight?.id }

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
        if flying, let flight { fill.matchedGeometryEffect(id: "flight", in: flight.namespace, isSource: false) } else { fill }
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
