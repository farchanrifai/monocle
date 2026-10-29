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
            case .deepOcean:
                DeepOceanView()
            case .rosePetal:
                SoftGradientView(colors: [
                    Color(red: 1.00, green: 0.88, blue: 0.90),
                    Color(red: 0.98, green: 0.74, blue: 0.80),
                    Color(red: 0.96, green: 0.80, blue: 0.74)
                ])
            case .goldenHour:
                SoftGradientView(colors: [
                    Color(red: 1.00, green: 0.91, blue: 0.58),
                    Color(red: 1.00, green: 0.75, blue: 0.42),
                    Color(red: 0.98, green: 0.60, blue: 0.40)
                ])
            case .duskMesh:
                MeshStockView(colors: [
                    Color(red: 0.10, green: 0.07, blue: 0.28), Color(red: 0.24, green: 0.10, blue: 0.45), Color(red: 0.12, green: 0.12, blue: 0.40),
                    Color(red: 0.38, green: 0.12, blue: 0.50), Color(red: 0.55, green: 0.18, blue: 0.55), Color(red: 0.22, green: 0.14, blue: 0.52),
                    Color(red: 0.65, green: 0.22, blue: 0.48), Color(red: 0.35, green: 0.16, blue: 0.50), Color(red: 0.14, green: 0.10, blue: 0.36)
                ])
            case .meadowMesh:
                MeshStockView(colors: [
                    Color(red: 0.86, green: 0.97, blue: 0.80), Color(red: 0.93, green: 0.98, blue: 0.76), Color(red: 0.80, green: 0.95, blue: 0.84),
                    Color(red: 0.70, green: 0.92, blue: 0.76), Color(red: 0.88, green: 0.97, blue: 0.70), Color(red: 0.72, green: 0.93, blue: 0.86),
                    Color(red: 0.60, green: 0.88, blue: 0.72), Color(red: 0.78, green: 0.94, blue: 0.74), Color(red: 0.66, green: 0.90, blue: 0.88)
                ])
            case .pinstripe:
                PinstripeView()
            case .polkaDots:
                PolkaDotsView()
            case .inkMinimal:
                MinimalStockView(base: Color(red: 0.07, green: 0.07, blue: 0.08), ink: .white, accent: Color(red: 0.98, green: 0.38, blue: 0.16))
            case .paperMinimal:
                MinimalStockView(base: Color(red: 0.96, green: 0.96, blue: 0.94), ink: .black, accent: Color(red: 0.98, green: 0.38, blue: 0.16))
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

// MARK: - 10. Deep Ocean
struct DeepOceanView: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.03, green: 0.12, blue: 0.30),
                    Color(red: 0.05, green: 0.34, blue: 0.54),
                    Color(red: 0.06, green: 0.50, blue: 0.60)
                ],
                startPoint: .top,
                endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [Color.white.opacity(0.18), Color.clear],
                center: .topTrailing,
                startRadius: 0,
                endRadius: 220
            )
        }
    }
}

// MARK: - 11-12. Soft gradients (Rose Quartz, Golden Hour): light fills, pair with dark text
struct SoftGradientView: View {
    let colors: [Color]

    var body: some View {
        LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

// MARK: - 13-14. Mesh (Dusk Mesh, Meadow Mesh): 3x3 grid, one slightly off-center control point
struct MeshStockView: View {
    let colors: [Color]

    var body: some View {
        MeshGradient(
            width: 3,
            height: 3,
            points: [
                [0, 0], [0.5, 0], [1, 0],
                [0, 0.5], [0.58, 0.42], [1, 0.5],
                [0, 1], [0.5, 1], [1, 1]
            ],
            colors: colors
        )
    }
}

// MARK: - 15. Pinstripe
struct PinstripeView: View {
    var body: some View {
        ZStack {
            Color(red: 0.10, green: 0.13, blue: 0.22)
            Canvas { context, size in
                let spacing: CGFloat = 12
                var x = -size.height
                while x < size.width {
                    var path = Path()
                    path.move(to: CGPoint(x: x, y: size.height))
                    path.addLine(to: CGPoint(x: x + size.height, y: 0))
                    context.stroke(path, with: .color(Color.white.opacity(0.07)), lineWidth: 1)
                    x += spacing
                }
            }
            LinearGradient(colors: [Color.white.opacity(0.08), Color.clear], startPoint: .top, endPoint: .bottom)
        }
    }
}

// MARK: - 16. Polka
struct PolkaDotsView: View {
    var body: some View {
        ZStack {
            Color(red: 0.99, green: 0.95, blue: 0.88)
            Canvas { context, size in
                let spacing: CGFloat = 26
                var row = 0
                var y: CGFloat = spacing / 2
                while y < size.height + spacing {
                    var x: CGFloat = row.isMultiple(of: 2) ? spacing / 2 : spacing
                    while x < size.width + spacing {
                        let rect = CGRect(x: x - 4, y: y - 4, width: 8, height: 8)
                        context.fill(Path(ellipseIn: rect), with: .color(Color(red: 0.96, green: 0.45, blue: 0.32).opacity(0.28)))
                        x += spacing
                    }
                    y += spacing * 0.8
                    row += 1
                }
            }
        }
    }
}

// MARK: - 17-18. Minimal (Ink, Paper): flat base, hairline rule and a short accent bar
struct MinimalStockView: View {
    let base: Color
    let ink: Color
    let accent: Color

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            base
            LinearGradient(colors: [ink.opacity(0.07), Color.clear], startPoint: .topLeading, endPoint: .center)
            VStack(spacing: 0) {
                Spacer()
                Rectangle().fill(ink.opacity(0.12)).frame(height: 0.5)
                Color.clear.frame(height: 14)
            }
            accent
                .frame(width: 28, height: 3)
                .clipShape(Capsule())
                .padding(.leading, 16)
                .padding(.bottom, 7)
        }
    }
}
