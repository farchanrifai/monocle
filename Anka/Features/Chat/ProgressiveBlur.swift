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
