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

// MARK: - Native Liquid Glass System

struct LiquidGlassModifier: ViewModifier {
    var cornerRadius: CGFloat = 16
    var tint: Color? = nil
    var specularIntensity: Double = 0.22
    var interactive: Bool = false

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        if let tint {
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .fill(tint)
                        }
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            stops: [
                                .init(color: .white.opacity(specularIntensity), location: 0.0),
                                .init(color: .white.opacity(specularIntensity * 0.4), location: 0.35),
                                .init(color: .white.opacity(0.03), location: 0.7),
                                .init(color: .white.opacity(0.08), location: 1.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.75
                    )
            }
            .glassEffect(tint != nil ? .regular.tint(tint!).interactive(interactive) : .regular.interactive(interactive), in: .rect(cornerRadius: cornerRadius))
    }
}

struct LiquidGlassKeyStyle: ButtonStyle {
    var cornerRadius: CGFloat = 12
    var isDestructiveOrAction: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isDestructiveOrAction ? MC.red : Color.primary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(configuration.isPressed ? Color.primary.opacity(0.12) : Color.primary.opacity(0.04))
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            stops: [
                                .init(color: .white.opacity(configuration.isPressed ? 0.36 : 0.20), location: 0.0),
                                .init(color: .white.opacity(0.04), location: 0.8)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.75
                    )
            }
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.94 : 1.0)
            .animation(reduceMotion ? nil : .snappy(duration: 0.12), value: configuration.isPressed)
    }
}

extension View {
    func liquidGlass(cornerRadius: CGFloat = 16, tint: Color? = nil, specularIntensity: Double = 0.22, interactive: Bool = false) -> some View {
        modifier(LiquidGlassModifier(cornerRadius: cornerRadius, tint: tint, specularIntensity: specularIntensity, interactive: interactive))
    }
}

