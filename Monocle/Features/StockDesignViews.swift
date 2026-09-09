import SwiftUI

public struct StockDesignBackgroundView: View {
    let design: StockCardDesign

    public init(design: StockCardDesign) {
        self.design = design
    }

    public var body: some View {
        Group {
            switch design {
            case .sunsetHeat:
                SunsetHeatView()
            case .auroraBorealis:
                AuroraBorealisView()
            case .midnightCosmo:
                MidnightCosmoView()
            case .acidCyber:
                AcidCyberView()
            case .titaniumMetal:
                TitaniumMetalView()
            case .appleAura:
                AppleAuraView()
            case .topographic:
                TopographicView()
            case .neoGrid:
                NeoGridView()
            case .warmParchment:
                WarmParchmentView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }
}

// MARK: - 1. Sunset Heat
struct SunsetHeatView: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.98, green: 0.28, blue: 0.16),
                    Color(red: 0.95, green: 0.12, blue: 0.45),
                    Color(red: 0.58, green: 0.08, blue: 0.62)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [Color.yellow.opacity(0.45), Color.clear],
                center: .topTrailing,
                startRadius: 20,
                endRadius: 260
            )
        }
    }
}

// MARK: - 2. Aurora Borealis
struct AuroraBorealisView: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.02, green: 0.15, blue: 0.28),
                    Color(red: 0.05, green: 0.35, blue: 0.45),
                    Color(red: 0.12, green: 0.05, blue: 0.32)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            AngularGradient(
                gradient: Gradient(colors: [
                    Color.cyan.opacity(0.4),
                    Color.mint.opacity(0.5),
                    Color.purple.opacity(0.4),
                    Color.clear
                ]),
                center: .center,
                angle: .degrees(135)
            )
            .blur(radius: 20)
        }
    }
}

// MARK: - 3. Midnight Cosmos
struct MidnightCosmoView: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.06, green: 0.08, blue: 0.14),
                    Color(red: 0.10, green: 0.14, blue: 0.24),
                    Color(red: 0.04, green: 0.05, blue: 0.09)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [Color(red: 0.35, green: 0.45, blue: 0.85).opacity(0.35), Color.clear],
                center: .bottomTrailing,
                startRadius: 10,
                endRadius: 280
            )
            RadialGradient(
                colors: [Color(red: 0.65, green: 0.25, blue: 0.75).opacity(0.25), Color.clear],
                center: .topLeading,
                startRadius: 10,
                endRadius: 220
            )
        }
    }
}

// MARK: - 4. Acid Cyber
struct AcidCyberView: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.82, green: 0.98, blue: 0.22),
                    Color(red: 0.40, green: 0.95, blue: 0.72),
                    Color(red: 0.15, green: 0.80, blue: 0.88)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [Color.white.opacity(0.45), Color.clear],
                center: .topTrailing,
                startRadius: 10,
                endRadius: 200
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }
}

// MARK: - 5. Titanium Metal
struct TitaniumMetalView: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.78, green: 0.80, blue: 0.83),
                    Color(red: 0.65, green: 0.68, blue: 0.72),
                    Color(red: 0.84, green: 0.86, blue: 0.89)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            // Specular metallic sheen
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.0),
                    .init(color: Color.white.opacity(0.4), location: 0.45),
                    .init(color: Color.white.opacity(0.1), location: 0.55),
                    .init(color: .clear, location: 1.0)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }
}

// MARK: - 6. Apple Aura (Mesh-like)
struct AppleAuraView: View {
    var body: some View {
        ZStack {
            Color(red: 0.98, green: 0.98, blue: 0.97)
            RadialGradient(
                colors: [Color(red: 0.98, green: 0.45, blue: 0.25).opacity(0.65), Color.clear],
                center: .topLeading,
                startRadius: 0,
                endRadius: 160
            )
            RadialGradient(
                colors: [Color(red: 0.98, green: 0.85, blue: 0.25).opacity(0.65), Color.clear],
                center: .topTrailing,
                startRadius: 0,
                endRadius: 150
            )
            RadialGradient(
                colors: [Color(red: 0.35, green: 0.75, blue: 0.95).opacity(0.6), Color.clear],
                center: .bottomTrailing,
                startRadius: 0,
                endRadius: 160
            )
            RadialGradient(
                colors: [Color(red: 0.85, green: 0.40, blue: 0.85).opacity(0.55), Color.clear],
                center: .bottomLeading,
                startRadius: 0,
                endRadius: 140
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }
}

// MARK: - 7. Topographic
struct TopographicView: View {
    var body: some View {
        ZStack {
            Color(red: 0.10, green: 0.12, blue: 0.15)
            Canvas { context, size in
                let count = 8
                for i in 0..<count {
                    var path = Path()
                    let progress = Double(i) / Double(count)
                    let startY = size.height * CGFloat(progress)
                    path.move(to: CGPoint(x: 0, y: startY))
                    path.addCurve(
                        to: CGPoint(x: size.width, y: startY + 30),
                        control1: CGPoint(x: size.width * 0.3, y: startY - 40),
                        control2: CGPoint(x: size.width * 0.7, y: startY + 50)
                    )
                    context.stroke(
                        path,
                        with: .color(Color(red: 0.45, green: 0.75, blue: 0.85).opacity(0.25)),
                        lineWidth: 1.2
                    )
                }
            }
        }
    }
}

// MARK: - 8. Neo Grid
struct NeoGridView: View {
    var body: some View {
        ZStack {
            Color(red: 0.08, green: 0.09, blue: 0.11)
            Canvas { context, size in
                let spacing: CGFloat = 20
                var x: CGFloat = spacing
                while x < size.width {
                    var y: CGFloat = spacing
                    while y < size.height {
                        let rect = CGRect(x: x - 1, y: y - 1, width: 2, height: 2)
                        context.fill(Path(ellipseIn: rect), with: .color(Color.white.opacity(0.22)))
                        y += spacing
                    }
                    x += spacing
                }
            }
            // Accent gradient bar on bottom edge
            VStack {
                Spacer()
                LinearGradient(
                    colors: [Color.cyan.opacity(0.8), Color.mint.opacity(0.8)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(height: 3)
            }
        }
    }
}

// MARK: - 9. Warm Parchment
struct WarmParchmentView: View {
    var body: some View {
        ZStack {
            Color(red: 0.97, green: 0.95, blue: 0.90)
            Canvas { context, size in
                let lineSpacing: CGFloat = 22
                var y: CGFloat = 36
                while y < size.height {
                    var path = Path()
                    path.move(to: CGPoint(x: 16, y: y))
                    path.addLine(to: CGPoint(x: size.width - 16, y: y))
                    context.stroke(path, with: .color(Color.black.opacity(0.06)), lineWidth: 0.5)
                    y += lineSpacing
                }
            }
        }
    }
}
