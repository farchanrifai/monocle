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

/// Paces streamed text: network chunks arrive in bursts, so the bubble reveals what has arrived at a steady rate
/// (about 45 characters a second, faster when a backlog builds up) instead of in jumps. Driven by the view's clock.
@MainActor
final class StreamPacer {
    private(set) var target = ""
    private var shown = 0.0
    private var last: Date?

    /// The part of `target` revealed so far.
    var visible: String { String(target.prefix(Int(shown.rounded(.up)))) }
    var caughtUp: Bool { shown >= Double(target.count) - 0.5 }

    func set(_ text: String) { target = text }
    func reset() { target = ""; shown = 0; last = nil }

    /// Moves the reveal to `date`; returns how many characters are revealed (fractional while the newest one fades in).
    func advance(to date: Date) -> Double {
        let dt = min(max(date.timeIntervalSince(last ?? date), 0), 0.1)
        last = date
        let count = Double(target.count)
        shown = min(count, shown + max(45, (count - shown) * 4) * dt)
        return shown
    }

    /// Lets the reveal catch up before the finished row replaces the streaming bubble (gives up after 1.5s: the view may not be on screen).
    func drain() async {
        for _ in 0..<30 where !caughtUp { try? await Task.sleep(for: .milliseconds(50)) }
    }
}

/// Fades the newest glyphs in: each glyph is `fade` positions behind the newest one before it is fully opaque, so text appears
/// with a soft leading edge as the pacer reveals it. `shown` nil draws the text normally.
struct StreamFadeRenderer: TextRenderer {
    var shown: Double?
    var fade: Double = 12

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        guard let shown else { for line in layout { context.draw(line) }; return }
        var total = 0
        for line in layout { for run in line { total += run.count } }
        let newest = shown - Double(Int(shown.rounded(.up)) - 1) // 0...1: how far the newest character has come in
        var index = 0
        for line in layout {
            for run in line {
                for slice in run {
                    var glyph = context
                    glyph.opacity = min(max((newest + Double(total - 1 - index)) / fade, 0), 1)
                    glyph.draw(slice)
                    index += 1
                }
            }
        }
    }
}

/// Lets a bubble's height glide when its text wraps onto a new line. A text view's own height changes instantly, so the height is
/// measured and applied back as an animated frame; the new line fades in (`StreamFadeRenderer`) while the bubble opens for it.
struct SmoothHeight: ViewModifier {
    @State private var height: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
            .frame(height: height > 0 ? height : nil, alignment: .top)
            .animation(.smooth(duration: 0.35), value: height)
    }
}
