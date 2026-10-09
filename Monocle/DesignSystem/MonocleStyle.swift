import SwiftUI

enum MC {
    static let red = Color(red: 0.83, green: 0.16, blue: 0.12)
    static let ink = Color(red: 0.10, green: 0.105, blue: 0.10)
    static let paper = Color(uiColor: .systemGroupedBackground)
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
    static let line = Color.primary.opacity(0.10)
    static func label(_ size: CGFloat = 10) -> Font { .system(size: size, weight: .medium, design: .monospaced) }
}

struct Eyebrow: View {
    let text: String
    var body: some View {
        Text(text.uppercased()).font(.caption2.monospaced()).tracking(1.5).foregroundStyle(.secondary)
    }
}

struct RecordButton: View {
    let title: String
    var symbol: String = "plus"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .semibold))
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
        }
        .buttonStyle(PressFeedbackStyle())
        .glassEffect(.regular.tint(MC.red.opacity(0.85)).interactive(), in: .capsule)
        .environment(\.colorScheme, .dark)
    }
}

struct CategoryMark: View {
    let symbol: String
    var body: some View {
        Image(systemName: symbol).font(.system(size: 18, weight: .regular))
            .frame(width: 42, height: 42).background(MC.surface, in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(MC.line, lineWidth: 0.5)).accessibilityHidden(true)
    }
}

/// Standard Apple Settings icon badge with rounded square gradient backing.
struct SettingsIcon: View {
    let symbol: String
    let color: Color

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 28, height: 28)
            .background(color.gradient, in: RoundedRectangle(cornerRadius: 6.5, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// Brief, interruptible touch feedback; accessibility preferences remove scaling.
struct PressFeedbackStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(reduceMotion ? .easeOut(duration: 0.1) : .snappy(duration: 0.2), value: configuration.isPressed)
    }
}

/// Material that fades out with a smoothstep (no hard shoulder, no visible cutoff), the same recipe as the
/// Home and Analytics headers. `solid` is fully covered; `fade` eases to clear away from `edge`.
// ponytail: Home/Analytics keep their own copies (Home's fades with scroll); migrate them here when touched.
struct ProgressiveBlur: View {
    var edge: VerticalEdge = .top
    var solid: CGFloat
    var fade: CGFloat = 62
    var tint: Color

    var body: some View {
        let total = solid + fade
        let stops: [Gradient.Stop] = [.init(color: .black, location: 0)] + (0...16).map { step in
            let t = CGFloat(step) / 16
            return .init(color: .black.opacity(Double(1 - t * t * (3 - 2 * t))), location: (solid + fade * t) / total)
        }
        Rectangle()
            .fill(.ultraThinMaterial)
            .overlay(tint.opacity(0.52))
            .mask { LinearGradient(stops: stops, startPoint: edge == .top ? .top : .bottom, endPoint: edge == .top ? .bottom : .top) }
            .frame(height: total)
            .allowsHitTesting(false)
    }
}
