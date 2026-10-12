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
    /// Draws the sent bubble flying out of the composer as in Messages, in two phases timed separately:
    /// `x` (0 → 1, quick, ease-in-out) collapses the field's shape sideways into the bubble's width and height while it stays at the field's level,
    /// the message riding inside it; `y` (0 → 1, slower) then lifts it into the bubble's resting frame, the text growing back to full size.
    /// One-shot: nothing is drawn unless `active`.
    func chatFlightLayer(from: CGRect, x: CGFloat, y: CGFloat, active: Bool, label: Text?) -> some View {
        overlayPreferenceValue(ChatFlightTarget.self) { anchor in
            GeometryReader { proxy in
                if active, let anchor, from.width > 0 {
                    let to = proxy[anchor]
                    let left = from.minX + (to.minX - from.minX) * x
                    let right = from.maxX + (to.maxX - from.maxX) * x
                    // Squashed thin while it collapses (the text with it), then stretched back to full size as it lifts.
                    let squash = 1 - 0.4 * x * x * (1 - y)
                    let height = (from.height + (to.height - from.height) * x) * squash
                    let textScale = 1 - 0.28 * x * x * (1 - y)
                    let midY = from.midY + (to.midY - from.midY) * y
                    let shape = BubbleShape(isUser: true, hasTail: true)
                    ZStack(alignment: .leading) {
                        shape.fill(MC.red.opacity(0.45 + 0.55 * x))
                        // Wrapped at the bubble's final inner width so it never re-wraps; clipped to the shape while that is still narrower.
                        label?.foregroundStyle(.white)
                            .textRenderer(MentionChipRenderer(chip: .black.opacity(0.28)))
                            .frame(width: to.width - 28, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .scaleEffect(x: textScale, y: textScale * squash, anchor: .leading)
                            .padding(.leading, 14)
                    }
                    .clipShape(shape)
                    .frame(width: right - left, height: height)
                    .position(x: (left + right) / 2, y: midY)
                    .transition(.identity)
                }
            }
            .allowsHitTesting(false)
        }
    }
}

extension ChatSession {
    /// Shape from a 60fps recording of Messages on the Mac, slowed about 1.4x for a softer feel: the sideways sweep is a symmetric bell, fastest near 100ms and done by
    /// ~180ms; the lift starts at ~110ms (overlapping the end of the sweep) and decelerates until ~380ms. The transcript uses the lift too.
    static let sweepAnimation = Animation.easeInOut(duration: 0.26)
    /// The bubble's lift is a spring so it overshoots its slot a little and settles back (bouncier than Messages, on purpose);
    /// the rows above ease without overshoot on the measured curve.
    static let liftAnimation = Animation.spring(duration: 0.6, bounce: 0.3).delay(0.16)
    static let imessageRows = Animation.timingCurve(0.2, 0.8, 0.3, 1, duration: 0.4).delay(0.16)

    /// How a sent message arrives. `imessage`: the field's shape flies up into the slot. `whatsapp` (default while trying it): no flight;
    /// the bubble appears in its slot at ~15% size and grows in place from its tail corner, the rows above easing up with it
    /// (read off a 60fps recording: ~0.17s after send, 99% grown in ~0.15s, ease-out, no overshoot).
    /// Switch with `defaults write <bundle id> chatSendStyle imessage` (or `whatsapp`). `chat-flight-imessage` is the tagged iMessage baseline.
    enum SendStyle { case imessage, whatsapp }
    static var sendStyle: SendStyle { UserDefaults.standard.string(forKey: "chatSendStyle") == "imessage" ? .imessage : .whatsapp }
    static let whatsappGrow = Animation.timingCurve(0.15, 0.6, 0.25, 1, duration: 0.26).delay(0.22)
    static var rowsAnimation: Animation { sendStyle == .whatsapp ? whatsappGrow : imessageRows }

    /// Appends the user's bubble inside a spring so its shape flies out of the composer field (`chatFlightLayer`), then lets go of the flight.
    /// `alongside` runs in the same animation (clearing the draft). Returns the row to hand to `send(appended:)`.
    func appendUserRow(_ text: String, animated: Bool, alongside: () -> Void) -> ChatRow {
        let row = ChatRow(kind: .user(text))
        flightID = animated ? row.id : nil
        // The rows above move while the bubble lifts, not before (as in Messages).
        withAnimation(animated ? Self.rowsAnimation : nil) {
            alongside()
            rows.append(row)
        }
        if animated {
            Task {
                try? await Task.sleep(for: .milliseconds(Self.sendStyle == .whatsapp ? 800 : 1000)) // iMessage: fallback, the view clears the flight when the lift completes
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

    fileprivate var flying: Bool { rowID != nil && rowID == flightID }
    /// iMessage style: a travelling copy is drawn elsewhere, so this bubble stays invisible until it lands.
    fileprivate var hiddenForFlight: Bool { flying && ChatSession.sendStyle == .imessage }
    /// WhatsApp style: this bubble itself grows from its tail corner.
    @State private var grown = false
    fileprivate var growing: Bool { flying && ChatSession.sendStyle == .whatsapp }

    var body: some View {
        content
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .foregroundStyle(isUser ? Color.white : Color.primary)
            // The travelling copy (shape and text) is drawn by `chatFlightLayer`; this one appears when it lands.
            .opacity(hiddenForFlight ? 0 : 1)
            .background { shape }
            .scaleEffect(growing && !grown ? 0.15 : 1, anchor: isUser ? .bottomTrailing : .bottomLeading)
            .onAppear { if growing { withAnimation(ChatSession.whatsappGrow) { grown = true } } }
            .transition(rowID != nil ? .identity : .opacity)
            .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
            .padding(isUser ? .leading : .trailing, 48)
    }
}

extension ChatBubble {
    @ViewBuilder fileprivate var shape: some View {
        let fill = BubbleShape(isUser: isUser, hasTail: hasTail).fill(isUser ? MC.red : Color.secondary.opacity(0.16))
        if hiddenForFlight { fill.opacity(0).anchorPreference(key: ChatFlightTarget.self, value: .bounds) { $0 } } else { fill }
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
