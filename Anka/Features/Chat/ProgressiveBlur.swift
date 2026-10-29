import SwiftUI

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

/// The chat's surfaces, one set of system semantic colours that follows light and dark. iPhone uses the grouped-free
/// system background ramp (black canvas in dark, raised grey surfaces); the Mac pane keeps its translucent fills.
extension Color {
    /// Behind the transcript, the composer fade and the top fade.
    static var chatCanvas: Color {
        #if canImport(UIKit)
        Color(uiColor: .systemBackground)
        #else
        Color(nsColor: .windowBackgroundColor)
        #endif
    }
    /// Assistant bubbles and proposal/chart cards.
    static var chatSurface: Color {
        #if canImport(UIKit)
        Color(uiColor: .secondarySystemBackground)
        #else
        Color.secondary.opacity(0.12)
        #endif
    }
    /// Bar tracks and chart reference marks inside a card.
    static var chatTrack: Color {
        #if canImport(UIKit)
        Color(uiColor: .tertiarySystemFill)
        #else
        Color.secondary.opacity(0.12)
        #endif
    }
}
