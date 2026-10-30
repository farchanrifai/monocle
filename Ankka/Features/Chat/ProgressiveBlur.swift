import SwiftUI

/// The chat's surfaces, one set of system semantic colours that follows light and dark. iPhone uses the grouped-free
/// system background ramp (black canvas in dark, raised grey surfaces); the Mac pane keeps its translucent fills.
extension Color {
    /// Behind the transcript.
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
