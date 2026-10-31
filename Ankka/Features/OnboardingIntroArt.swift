import SwiftUI

// Drawings for OnboardingIntro, in the design's 402×874 pt canvas. The props are clay renders in Assets › Onboarding.

// MARK: - Palette

struct IntroPalette {
    let lit, bg, deep, hi, lt, base, mid, sh, dp, shd, ink: Color

    private init(_ v: [UInt32]) {
        let c = v.map { Color(red: Double($0 >> 16 & 0xFF) / 255, green: Double($0 >> 8 & 0xFF) / 255, blue: Double($0 & 0xFF) / 255) }
        (lit, bg, deep, hi, lt, base, mid, sh, dp, shd, ink) = (c[0], c[1], c[2], c[3], c[4], c[5], c[6], c[7], c[8], c[9], c[10])
    }

    /// lit, bg, deep, hi, light, base, mid, shade, deep tone, shadow, ink: the design's six step palettes.
    /// Step 7 is the cream that fills Next on the last step and paints Get started.
    static func step(_ n: Int, dark: Bool) -> IntroPalette {
        switch (n, dark) {
        case (1, false): IntroPalette([0xFD8C6F, 0xFF6F4F, 0xEB5842, 0xFFD4C7, 0xFEA48C, 0xFF7F62, 0xEB553C, 0xC7372B, 0x930C18, 0x4B020B, 0x320100])
        case (1, true): IntroPalette([0x701D05, 0x5D1101, 0x410300, 0xE2714E, 0xA0381B, 0x761B05, 0x5F0D01, 0x440101, 0x2C0002, 0x070000, 0xFFE5DD])
        case (2, false): IntroPalette([0xFFCE76, 0xFFBA2E, 0xEEA50F, 0xFFF6E4, 0xFFE1AC, 0xFFC561, 0xEAA40F, 0xC78711, 0x98620B, 0x603901, 0x2B1A00])
        case (2, true): IntroPalette([0x5F3802, 0x4E2D02, 0x361B00, 0xCE8B32, 0x8B5606, 0x633A03, 0x4F2C02, 0x381C01, 0x260F00, 0x050100, 0xFBE9CA])
        case (3, false): IntroPalette([0xB1D173, 0x9FC45E, 0x87B24D, 0xEBF9CE, 0xC1DF87, 0xA7CC66, 0x87B147, 0x669432, 0x3D6C1A, 0x1B3D0C, 0x142300])
        case (3, true): IntroPalette([0x244E19, 0x1B3F0B, 0x112A01, 0x70AE69, 0x3D7231, 0x275115, 0x1B4001, 0x152B00, 0x0E1A00, 0x010200, 0xE5F1D0])
        case (4, false): IntroPalette([0x84CBFD, 0x71BCF4, 0x61A8E2, 0xE4F4FF, 0xA3D8FE, 0x79C4FC, 0x5CA7E2, 0x4788C1, 0x2E6093, 0x183354, 0x032036])
        case (4, true): IntroPalette([0x114361, 0x063552, 0x012139, 0x5D9FC9, 0x28658C, 0x114567, 0x023455, 0x00223D, 0x00132A, 0x000207, 0xD9EFFF])
        case (5, false): IntroPalette([0xC4ADFB, 0xB59EF2, 0x9F8CE1, 0xEFE7FF, 0xD1BFFE, 0xBDA6FB, 0x9F8AE0, 0x7E6FBF, 0x554D91, 0x2A2752, 0x1F1838])
        case (5, true): IntroPalette([0x443463, 0x352854, 0x21163E, 0xA088CC, 0x66528E, 0x463669, 0x352757, 0x221742, 0x120B2F, 0x02000D, 0xEDE7FF])
        case (6, false): IntroPalette([0xAD3424, 0xA3170F, 0x8A000E, 0xE79B88, 0xD0503C, 0xB1281E, 0x90080E, 0x6D0410, 0x4A010B, 0x140001, 0xFFF0EB])
        case (6, true): IntroPalette([0x5C0801, 0x480201, 0x2A0001, 0xCD5F48, 0x8B2516, 0x620402, 0x490003, 0x2C0002, 0x150001, 0x070000, 0xFFE4DF])
        case (_, false): IntroPalette([0xAD3424, 0xA3170F, 0x8A000E, 0xFFFFFF, 0xFFFFFF, 0xFFF0EB, 0xFFD3C7, 0xFFD3C7, 0xFFD3C7, 0x140001, 0xA3170F])
        case (_, true): IntroPalette([0x5C0801, 0x480201, 0x2A0001, 0xFFF6F3, 0xFFF6F3, 0xFFE4DF, 0xF2BFB3, 0xF2BFB3, 0xF2BFB3, 0x070000, 0x480201])
        }
    }
}

private extension View {
    func box(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> some View {
        frame(width: w, height: h).position(x: x + w / 2, y: y + h / 2)
    }
}

private func clamp01(_ v: Double) -> Double { min(max(v, 0), 1) }

// MARK: - Pages

/// One step's backdrop: a lit radial ground, a soft glow behind the hero, and tone-on-tone props.
struct IntroPage: View {
    let step: Int
    let pal: IntroPalette
    let props: [PropState]
    let t: Double
    let gain: Double
    let drift: CGPoint
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            RadialGradient(stops: [.init(color: pal.lit, location: 0), .init(color: pal.bg, location: 0.5), .init(color: pal.deep, location: 1)],
                           center: UnitPoint(x: 0.28, y: 0.14), startRadius: 0, endRadius: 780)
                .padding(-140)
            Ellipse()
                .fill(RadialGradient(colors: [pal.hi, pal.hi.opacity(0)], center: .center, startRadius: 0, endRadius: 265))
                .frame(width: 522, height: 540)
                .opacity(scheme == .dark ? 0.2 : 0.34)
                .position(x: -60 + 261 + 6 * drift.x * gain, y: 40 + 270 + 4 * drift.y * gain)
            ForEach(Array(layout.enumerated()), id: \.offset) { i, slot in
                let p = i < props.count ? props[i] : PropState()
                let amp = 3.0 + Double(i % 4), period = 5.3 + 0.7 * Double(i), swing = 1.0 + Double(i % 3)
                slot.draw(pal)
                    .frame(width: slot.frame.width, height: slot.frame.height)
                    .rotationEffect(.degrees(slot.rotation + swing * sin(2 * .pi * t / (1.3 * period)) * gain))
                    .scaleEffect(0.62 + 0.38 * p.pop)
                    .rotationEffect(.degrees(10 * (1 - p.pop)))
                    .offset(x: 16 * slot.depth * drift.x * gain,
                            y: 26 * (1 - p.pop) + amp * sin(2 * .pi * t / period + Double(i)) * gain + 11 * slot.depth * drift.y * gain)
                    .opacity(p.fade)
                    .position(x: slot.frame.midX, y: slot.frame.midY)
            }
        }
        .frame(width: 402, height: 874)
        .accessibilityHidden(true)
    }

    private var layout: [PropSlot] {
        switch step {
        case 1: [
            PropSlot("prop-clay-8", CGRect(x: 0, y: 112, width: 132, height: 163), -12, 0.8),
            PropSlot("prop-coin-tilt", CGRect(x: 300, y: 118, width: 86, height: 66), 16, 0.5),
            PropSlot("prop-coin-stack", CGRect(x: 316, y: 398, width: 78, height: 80), -6, 0.6),
            PropSlot("prop-clay-2", CGRect(x: 14, y: 402, width: 84, height: 104), 10, 0.9),
            PropSlot("prop-coin-face", CGRect(x: 232, y: 94, width: 32, height: 32), -18, 0.25, blur: 0.6),
        ]
        case 2: [
            PropSlot("prop-boarding-pass", CGRect(x: -22, y: 90, width: 200, height: 99), -10, 0.7),
            PropSlot("prop-sunglasses", CGRect(x: 14, y: 452, width: 150, height: 75), -9, 0.85),
            PropSlot("prop-coin-tilt-marigold", CGRect(x: 318, y: 112, width: 64, height: 49), -14, 0.4),
        ]
        case 3: [
            PropSlot("prop-kopi-cup", CGRect(x: 14, y: 104, width: 92, height: 130), -8, 0.8),
            PropSlot("prop-receipt-curl", CGRect(x: 322, y: 420, width: 68, height: 92), 10, 0.6),
            PropSlot("prop-coffee-beans", CGRect(x: 110, y: 190, width: 58, height: 43), 0, 0.35),
        ]
        case 4: [
            PropSlot("prop-cloud", CGRect(x: 250, y: 124, width: 124, height: 71), 0, 0.5),
            PropSlot("prop-cloud-small", CGRect(x: -18, y: 130, width: 84, height: 48), 0, 0.3),
        ]
        case 5: [
            PropSlot("prop-clay-percent", CGRect(x: 8, y: 104, width: 76, height: 94), -10, 0.8),
            PropSlot("prop-coin-tilt-lilac", CGRect(x: 318, y: 112, width: 64, height: 49), -14, 0.4),
        ]
        default: [
            PropSlot("prop-padlock", CGRect(x: 12, y: 110, width: 72, height: 89), -10, 0.8),
            PropSlot("prop-key", CGRect(x: 284, y: 472, width: 106, height: 55), -22, 0.6),
        ]
        }
    }
}

/// A clay prop render (Assets › Onboarding, light and dark) and where it sits on the canvas.
/// The renders come from a Blender script that maps lighting onto each step's palette, so props stay tone-on-tone.
private struct PropSlot {
    let image: String
    let frame: CGRect
    let rotation: Double
    let depth: Double
    var blur = 0.0

    init(_ image: String, _ frame: CGRect, _ rotation: Double, _ depth: Double, blur: Double = 0) {
        self.image = image; self.frame = frame; self.rotation = rotation; self.depth = depth; self.blur = blur
    }

    func draw(_ pal: IntroPalette) -> some View {
        Image(image).resizable().scaledToFit()
            .shadow(color: pal.shd.opacity(0.3), radius: 5, x: 3, y: 7)
            .blur(radius: blur)
    }
}

// MARK: - Hero card

struct IntroCard: View {
    enum Kind: CaseIterable { case tokyo, bali, daily }

    let kind: Kind
    let motion: IntroMotion
    let shadow: Color
    var back = false

    static let wordmarkTargets: [Double] = [11, 13, 15, 17, 19]
    /// Odometer resting indices (blank first, then 0–9 per turn), as in the design.
    static let dailyAfterKopi: [Double] = [3, 5, 5, 27, 16, 21, 21]
    static let chipTargets: [Double] = [3, 9, 11, 11, 21]
    static let yenTargets: [Double] = [2, 3, 11, 21]
    static let rupiahTargets: [Double] = [2, 3, 19, 11, 21, 21]
    static let budgetTargets: [Double] = [2, 13]
    private static let wordmarkLetters = ["a", "n", "k", "k", "a"]
    private static let cream = Color(red: 1, green: 0.97, blue: 0.94)

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        ZStack(alignment: .topLeading) {
            shape.fill(LinearGradient(stops: [.init(color: kind.face[0], location: 0), .init(color: kind.face[1], location: 0.55), .init(color: kind.face[2], location: 1)],
                                      startPoint: UnitPoint(x: 0.32, y: 0), endPoint: UnitPoint(x: 0.68, y: 1)))
            LinearGradient(stops: [.init(color: .white.opacity(0), location: 0.28), .init(color: .white.opacity(0.26), location: 0.43),
                                   .init(color: .white.opacity(0.06), location: 0.5), .init(color: .white.opacity(0), location: 0.56),
                                   .init(color: .white.opacity(0.1), location: 0.62), .init(color: .white.opacity(0), location: 0.68)],
                           startPoint: .leading, endPoint: .trailing)
                .rotationEffect(.degrees(14)).scaleEffect(1.6)
            if back {
                Text("ankka").font(.system(size: 48, weight: .heavy)).tracking(-1.9).opacity(0.22)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                face
            }
        }
        .foregroundStyle(Self.cream)
        .frame(width: 288, height: 182)
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(LinearGradient(stops: [.init(color: .white.opacity(0.45), location: 0), .init(color: .white.opacity(0.14), location: 0.2),
                                                      .init(color: .white.opacity(0.08), location: 0.8), .init(color: .black.opacity(0.22), location: 1)],
                                              startPoint: .top, endPoint: .bottom), lineWidth: 1)
        }
        .background {
            shape.fill(LinearGradient(stops: [.init(color: kind.lip[0], location: 0), .init(color: kind.lip[1], location: 0.22), .init(color: kind.lip[2], location: 0.5),
                                              .init(color: kind.lip[1], location: 0.78), .init(color: kind.lip[0], location: 1)], startPoint: .leading, endPoint: .trailing))
                .offset(y: 4)
                .shadow(color: shadow.opacity(0.62), radius: 14, y: 16)
                .shadow(color: shadow.opacity(0.5), radius: 30, y: 38)
        }
    }

    @ViewBuilder private var face: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(kind.name).font(.system(size: 15, weight: .semibold)).tracking(-0.15).opacity(motion.names)
            Spacer()
            Text(kind.index).font(.system(size: 11, weight: .semibold, design: .monospaced)).tracking(0.9)
        }
        .padding(.leading, 18).padding(.trailing, 17).padding(.top, 15)
        if kind == .daily {
            HStack(spacing: -1.9) {
                ForEach(0..<5, id: \.self) { i in
                    OdoWheel(glyphs: Self.wordmarkGlyphs(i), index: motion.wordmark[i], cell: 60, sizing: Self.wordmarkLetters[i])
                }
            }
            .font(.system(size: 54, weight: .heavy))
            .padding(.leading, 15).padding(.top, 58)
            budgetFace.opacity(motion.budgetOpacity)
        }
        OdoNumber(text: kind.total, indices: motion.totals[kind] ?? [], cell: 32)
            .font(.system(size: 26, weight: .heavy)).monospacedDigit().tracking(-0.26)
            .opacity(motion.totalOpacity[kind] ?? 0)
            .padding(.leading, 17).padding(.top, 41)
        if kind == .tokyo {
            OdoNumber(text: "¥1,200", indices: motion.yen, cell: 32)
                .font(.system(size: 26, weight: .heavy)).monospacedDigit().tracking(-0.26)
                .opacity(motion.yenOpacity)
                .padding(.leading, 17).padding(.top, 41)
            OdoNumber(text: "≈ Rp 128,000", indices: motion.rupiah, cell: 32)
                .font(.system(size: 26, weight: .heavy)).monospacedDigit().tracking(-0.26)
                .opacity(motion.rupiahOpacity)
                .padding(.leading, 17).padding(.top, 41)
            caption(Text("¥1,200 · PAID TODAY")).opacity(motion.paidOpacity)
        }
        if kind == .daily {
            caption(HStack(spacing: 0) {
                Text("3")
                OdoWheel(glyphs: ["8", "9"], index: motion.dailyCount, cell: 12)
                Text(" EXPENSES · OCT")
            })
            .opacity(motion.captionOpacity[kind] ?? 0)
        } else {
            caption(Text(kind.caption)).opacity(motion.captionOpacity[kind] ?? 0)
        }
        Text("ankka").font(.system(size: 17, weight: .heavy)).tracking(-0.6)
            .opacity(motion.mark)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding(.trailing, 16).padding(.bottom, 11)
    }

    private func caption(_ content: some View) -> some View {
        content.font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(0.9)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .padding(.leading, 18).padding(.bottom, 15)
    }

    /// Daily's face on step 5: what's left this month and a ring at 70% of the budget.
    private var budgetFace: some View {
        ZStack(alignment: .topLeading) {
            OdoNumber(text: "Rp 1.2 jt", indices: motion.budget, cell: 36)
                .font(.system(size: 30, weight: .heavy)).monospacedDigit().tracking(-0.3)
                .padding(.leading, 17).padding(.top, 40)
            Text("left this month").font(.system(size: 13, weight: .semibold))
                .padding(.leading, 18).padding(.top, 82)
            ZStack {
                Circle().stroke(Self.cream.opacity(0.22), lineWidth: 10)
                Circle().trim(from: 0, to: motion.budgetRing)
                    .stroke(Self.cream, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("70%").font(.system(size: 14, weight: .bold, design: .monospaced))
            }
            .frame(width: 78, height: 78)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 23).padding(.top, 55)
            caption(Text("RP 4 JT BUDGET · BILLS IN"))
        }
    }

    /// Digits 0–9 cycling up to the letter, then a blank the wheel rolls on to when the wordmark leaves.
    private static func wordmarkGlyphs(_ i: Int) -> [String] {
        (0..<Int(wordmarkTargets[i])).map { String($0 % 10) } + [wordmarkLetters[i], ""]
    }
}

extension IntroCard.Kind {
    var name: String { switch self { case .daily: "Daily"; case .tokyo: "Tokyo trip"; case .bali: "Bali" } }
    var index: String { switch self { case .daily: "01"; case .tokyo: "02"; case .bali: "03" } }
    var total: String { switch self { case .daily: "Rp 2,418,500"; case .tokyo: "¥48,200"; case .bali: "Rp 6,420,000" } }
    var caption: String { switch self { case .daily: "38 EXPENSES · OCT"; case .tokyo: "12 EXPENSES · JPY"; case .bali: "21 EXPENSES · IDR" } }
    /// Idle float phase.
    var phase: Double { switch self { case .tokyo: 0.8; case .bali: 1.9; case .daily: 0 } }

    var totalTargets: [Double] {
        switch self {
        case .daily: [3, 5, 2, 19, 16, 21, 21]
        case .tokyo: [5, 9, 13, 11, 21]
        case .bali: [7, 5, 3, 11, 11, 21, 21]
        }
    }

    var face: [Color] {
        switch self {
        case .daily: [Color(red: 0.831, green: 0.161, blue: 0.122), Color(red: 0.769, green: 0.133, blue: 0.098), Color(red: 0.620, green: 0.082, blue: 0.055)]
        case .tokyo: [Color(red: 0.227, green: 0.267, blue: 0.604), Color(red: 0.157, green: 0.188, blue: 0.459), Color(red: 0.094, green: 0.114, blue: 0.306)]
        case .bali: [Color(red: 0.043, green: 0.478, blue: 0.451), Color(red: 0.035, green: 0.400, blue: 0.376), Color(red: 0.020, green: 0.282, blue: 0.271)]
        }
    }

    var lip: [Color] {
        switch self {
        case .daily: [Color(red: 0.396, green: 0.043, blue: 0.027), Color(red: 0.541, green: 0.071, blue: 0.043), Color(red: 0.639, green: 0.090, blue: 0.059)]
        case .tokyo: [Color(red: 0.055, green: 0.071, blue: 0.212), Color(red: 0.102, green: 0.125, blue: 0.345), Color(red: 0.137, green: 0.169, blue: 0.424)]
        case .bali: [Color(red: 0.012, green: 0.184, blue: 0.173), Color(red: 0.020, green: 0.314, blue: 0.294), Color(red: 0.027, green: 0.369, blue: 0.345)]
        }
    }
}

/// Tips a card about its horizontal axis and shows its back while it faces away (Tokyo's flip on steps 4 and 5).
struct CardFlip: ViewModifier, Animatable {
    var rx: Double
    let kind: IntroCard.Kind
    let motion: IntroMotion
    let shadow: Color

    nonisolated var animatableData: Double {
        get { rx }
        set { rx = newValue }
    }

    func body(content: Content) -> some View {
        let away = cos(rx * .pi / 180) < 0
        content
            .opacity(away ? 0 : 1)
            .overlay { if away { IntroCard(kind: kind, motion: motion, shadow: shadow, back: true).scaleEffect(y: -1) } }
            .rotation3DEffect(.degrees(rx), axis: (1, 0, 0), perspective: 0.26)
    }
}

/// One card's floor shadow. Animatable so it fades and spreads in step with the card's own spring.
struct FloorShadow: View, Animatable {
    var cardY: Double
    var cardX: Double
    var floorY: Double
    let tone: Color

    nonisolated var animatableData: AnimatablePair<AnimatablePair<Double, Double>, Double> {
        get { AnimatablePair(AnimatablePair(cardY, cardX), floorY) }
        set { cardY = newValue.first.first; cardX = newValue.first.second; floorY = newValue.second }
    }

    var body: some View {
        // Height above where the card rests: the floor sits 140 pt below a resting card's centre.
        let height = min(max(0, (floorY - 140) - (322 + cardY)), 460)
        let k = 1 - height / 460
        Ellipse()
            .fill(EllipticalGradient(stops: [.init(color: tone.opacity(0.4), location: 0), .init(color: tone.opacity(0.15), location: 0.55),
                                             .init(color: tone.opacity(0), location: 1)]))
            .frame(width: 270, height: 46)
            .scaleEffect(1 + 0.6 * height / 460)
            .opacity(0.9 * k * k)
            .position(x: 201 + cardX, y: floorY)
            .frame(width: 402, height: 874)
    }
}

// MARK: - Odometer

/// One rolling glyph column, clipped to a single cell and faded at the top and bottom edges.
struct OdoWheel: View {
    let glyphs: [String]
    let index: Double
    let cell: CGFloat
    var sizing: String? = nil

    var body: some View {
        Text(sizing ?? glyphs.last(where: { !$0.isEmpty }) ?? "0")
            .hidden()
            .frame(height: cell)
            .overlay(alignment: .top) {
                VStack(spacing: 0) {
                    ForEach(glyphs.indices, id: \.self) { i in Text(glyphs[i]).frame(height: cell) }
                }
                .fixedSize()
                .offset(y: -index * cell)
            }
            .mask {
                LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.13),
                                       .init(color: .black, location: 0.87), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom)
                    .padding(.horizontal, -20)
            }
    }
}

/// A number whose digits are odometer wheels: index 0 is blank, then 0–9 for up to three turns.
struct OdoNumber: View {
    let text: String
    let indices: [Double]
    let cell: CGFloat
    private static let glyphs = [""] + (0..<30).map { String($0 % 10) }

    var body: some View {
        let chars = Array(text)
        HStack(spacing: 0) {
            ForEach(chars.indices, id: \.self) { i in
                if chars[i].isNumber {
                    let j = chars[..<i].filter(\.isNumber).count
                    OdoWheel(glyphs: Self.glyphs, index: j < indices.count ? indices[j] : 0, cell: cell, sizing: String(chars[i]))
                } else {
                    Text(String(chars[i])).frame(height: cell)
                }
            }
        }
    }
}

// MARK: - Text

struct IntroText: View {
    let step: Int
    let ink: Color
    let lines: [LineState]

    private var copy: (String, String, String) {
        switch step {
        case 1: ("Meet", "Ankka.", "Log every expense in seconds and see where it goes.")
        case 2: ("A card per", "purpose.", "Daily spending, a Tokyo trip, Bali. Each card keeps its own total.")
        case 3: ("Kopi 28rb.", "Done.", "Type it like you’d text a friend, in English or Bahasa.")
        case 4: ("Spend", "in yen.", "Log any currency. Ankka shows it in rupiah too.")
        case 5: ("Know", "what’s left.", "Budgets and upcoming bills, right on your card.")
        default: ("Yours,", "privately.", "No bank login. No account. Your records stay on your iPhone.")
        }
    }

    var body: some View {
        let (one, two, body) = copy
        VStack(alignment: .leading, spacing: 0) {
            Text(one).frame(height: 58).modifier(LineMotion(state: lines[0]))
            Text(two).frame(height: 58).modifier(LineMotion(state: lines[1]))
            Text(body)
                .font(.system(size: 19, weight: .medium)).tracking(-0.23).lineSpacing(2)
                .frame(maxWidth: 340, alignment: .leading)
                .padding(.top, 16)
                .modifier(LineMotion(state: lines[2]))
        }
        .font(.system(size: 60, weight: .heavy)).tracking(-2.7)
        .foregroundStyle(ink)
        .padding(.leading, 24).padding(.top, 556)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
    }
}

private struct LineMotion: ViewModifier {
    let state: LineState
    func body(content: Content) -> some View {
        content.offset(y: state.y).blur(radius: state.blur).opacity(state.opacity)
    }
}

// MARK: - Step objects

/// The objects that act out steps 3–5: the kopi message, the yen coins and plane, the calendar and bills.
struct StepObjects: View {
    let motion: IntroMotion
    let t: Double
    let pal: (Int) -> IntroPalette

    private static let coinSpots = [CGPoint(x: 284, y: 346), CGPoint(x: 314, y: 364), CGPoint(x: 250, y: 362)]
    private static let billSpots = [CGPoint(x: 99.9, y: 507), CGPoint(x: 201, y: 507), CGPoint(x: 302.1, y: 507)]
    private static let billIcons = ["bolt.fill", "drop.fill", "wifi"]

    var body: some View {
        let m = motion
        ZStack {
            KopiMessage(morph: m.morph, arc: m.chipArc, scale: m.bubble.s * m.chip.s, lift: m.bubble.y, typed: m.typed, wheels: m.chipWheels, t: t, pal: pal(3))
                .opacity(m.bubble.opacity * m.chip.opacity)

            // Yen coins ride on the Tokyo card.
            ForEach(m.coins.indices, id: \.self) { i in
                let c = m.coins[i], spot = Self.coinSpots[i]
                Image("prop-coin-yen").resizable().scaledToFit()
                    .shadow(color: pal(4).shd.opacity(0.3), radius: 4, x: 2, y: 5)
                    .frame(width: 46, height: 46)
                    .rotationEffect(.degrees(c.r))
                    .position(x: spot.x + m.tokyo.x, y: spot.y + c.y + m.tokyo.y - 12)
                    .opacity(c.opacity)
            }
            PlaneRoute(progress: m.plane, pal: pal(4), routeOpacity: m.routeOpacity)
                .overlay { PlaneOnRoute(progress: m.plane, pal: pal(4)).opacity(m.planeOpacity) }

            WeekStrip(ink: pal(5).ink)
                .box(24, 448, 354, 84)
                .offset(y: m.calendar.y)
                .opacity(m.calendar.opacity)
            ForEach(m.bills.indices, id: \.self) { i in
                let b = m.bills[i], spot = Self.billSpots[i], p = pal(5)
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(LinearGradient(stops: [.init(color: p.hi, location: 0), .init(color: p.base, location: 0.6), .init(color: p.mid, location: 1)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .shadow(color: p.shd.opacity(0.5), radius: 6, y: 6)
                    Image(systemName: Self.billIcons[i]).font(.system(size: 15, weight: .bold)).foregroundStyle(p.dp)
                }
                .frame(width: 34, height: 34)
                .scaleEffect(b.s)
                .rotationEffect(.degrees(b.r))
                .position(x: spot.x + b.x, y: spot.y + b.y)
                .opacity(b.opacity)
            }
        }
        .frame(width: 402, height: 874)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Step 3's message: a dark bubble types "kopi 28rb", morphs into an expense chip, and arcs onto the Daily card.
private struct KopiMessage: View, Animatable {
    var morph: Double
    var arc: Double
    let scale: Double
    let lift: Double
    let typed: Int
    let wheels: [Double]
    let t: Double
    let pal: IntroPalette

    nonisolated var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(morph, arc) }
        set { morph = newValue.first; arc = newValue.second }
    }

    private static let ink = Color(red: 0.078, green: 0.137, blue: 0)
    private static let paper = Color(red: 0.92, green: 0.976, blue: 0.808)

    var body: some View {
        let m = clamp01(morph), p = clamp01(arc)
        let w = 192 + 44 * m, h = 52 + 4 * m, radius = 22 + 6 * m
        let u = 1 - p
        let x = u * u * 262 + 2 * u * p * 176 + p * p * 160
        let y = u * u * 146 + 2 * u * p * 60 + p * p * 330
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let text = String("kopi 28rb".prefix(typed))
        let caretOn = m < 0.05 && (typed < 9 || Int(t / 0.53) % 2 == 0)
        ZStack(alignment: .leading) {
            shape.fill(Self.ink)
                .shadow(color: pal.shd.opacity(0.55), radius: 13, y: 14)
            Path { q in
                q.move(to: CGPoint(x: 0, y: 0)); q.addLine(to: CGPoint(x: 8, y: 0))
                q.addCurve(to: CGPoint(x: 20, y: 18), control1: CGPoint(x: 8, y: 8), control2: CGPoint(x: 12, y: 14))
                q.addCurve(to: CGPoint(x: 0, y: 12), control1: CGPoint(x: 12, y: 20), control2: CGPoint(x: 4, y: 17))
                q.closeSubpath()
            }
            .fill(Self.ink)
            .frame(width: 20, height: 20)
            .position(x: w - 4, y: h - 9)
            .opacity(clamp01(1 - m * 3))
            HStack(spacing: 3) {
                Text(text).font(.system(size: 21, weight: .semibold)).tracking(-0.2)
                RoundedRectangle(cornerRadius: 2).frame(width: 2.5, height: 24).opacity(caretOn ? 1 : 0)
            }
            .foregroundStyle(Self.paper)
            .padding(.leading, 20)
            .opacity(clamp01(1 - m * 2.2))
            chip
                .frame(width: 236, height: h, alignment: .leading)
                .opacity(clamp01((m - 0.45) / 0.45))
        }
        .frame(width: w, height: h, alignment: .leading)
        .clipShape(shape)
        .scaleEffect((1 - 0.48 * p) * scale)
        .rotationEffect(.degrees(p > 0.001 ? -8 + 12 * p : 0))
        .position(x: x, y: y + lift)
    }

    private var chip: some View {
        HStack(spacing: 10) {
            Image("prop-kopi-chip").resizable().scaledToFit()
                .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 1) {
                Text("Kopi").font(.system(size: 15, weight: .bold))
                Text("FOOD & DRINK").font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(0.7)
            }
            Spacer(minLength: 0)
            OdoNumber(text: "Rp 28,000", indices: wheels, cell: 22)
                .font(.system(size: 16, weight: .heavy)).monospacedDigit()
        }
        .foregroundStyle(Self.paper)
        .padding(.leading, 8).padding(.trailing, 16)
    }
}

/// The plane's route: a cubic from off-screen left to above the Tokyo card.
private enum Route {
    static let points = [CGPoint(x: -20, y: 196), CGPoint(x: 40, y: 120), CGPoint(x: 160, y: 96), CGPoint(x: 262, y: 106)]

    static func point(_ t: Double) -> CGPoint {
        let u = 1 - t, p = points
        let a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t
        return CGPoint(x: a * p[0].x + b * p[1].x + c * p[2].x + d * p[3].x, y: a * p[0].y + b * p[1].y + c * p[2].y + d * p[3].y)
    }

    static func tangent(_ t: Double) -> CGPoint {
        let u = 1 - t, p = points
        return CGPoint(x: 3 * u * u * (p[1].x - p[0].x) + 6 * u * t * (p[2].x - p[1].x) + 3 * t * t * (p[3].x - p[2].x),
                       y: 3 * u * u * (p[1].y - p[0].y) + 6 * u * t * (p[2].y - p[1].y) + 3 * t * t * (p[3].y - p[2].y))
    }

    /// Arc length reached at each of 200 parameter steps, so the dots end exactly under the plane.
    static let lengths: [Double] = {
        var out = [0.0], prev = point(0)
        for i in 1...200 {
            let p = point(Double(i) / 200)
            out.append(out[i - 1] + hypot(p.x - prev.x, p.y - prev.y))
            prev = p
        }
        return out
    }()

    static func fraction(_ t: Double) -> Double {
        let i = t * 200, lo = min(Int(i), 199)
        let length = lengths[lo] + (lengths[lo + 1] - lengths[lo]) * (i - Double(lo))
        return length / lengths[200]
    }

    static let path: Path = {
        var p = Path()
        p.move(to: points[0])
        p.addCurve(to: points[3], control1: points[1], control2: points[2])
        return p
    }()
}

private struct PlaneRoute: View, Animatable {
    var progress: Double
    let pal: IntroPalette
    let routeOpacity: Double
    nonisolated var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        Route.path.trimmedPath(from: 0, to: Route.fraction(clamp01(progress)))
            .stroke(pal.ink.opacity(0.55), style: StrokeStyle(lineWidth: 2.6, lineCap: .round, dash: [0.1, 9]))
            .opacity(routeOpacity)
            .frame(width: 402, height: 874)
    }
}

private struct PlaneOnRoute: View, Animatable {
    var progress: Double
    let pal: IntroPalette
    nonisolated var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        let p = clamp01(progress)
        let at = Route.point(p), tn = Route.tangent(min(max(p, 0.002), 0.998))
        Image("prop-paper-plane").resizable().scaledToFit()
            .frame(width: 46, height: 34)
            .shadow(color: pal.shd.opacity(0.25), radius: 3, y: 4)
            .rotationEffect(.radians(atan2(tn.y, tn.x)))
            .position(at)
            .frame(width: 402, height: 874)
    }
}

/// Step 5's week strip, Monday 4 to Sunday 10.
private struct WeekStrip: View {
    let ink: Color
    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(zip(["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"], 4...10)), id: \.0) { day, date in
                VStack(spacing: 0) {
                    Text(day).font(.system(size: 9.5, weight: .semibold, design: .monospaced)).tracking(0.8)
                    Text("\(date)").font(.system(size: 16, weight: .bold)).frame(height: 22)
                    Spacer(minLength: 0)
                }
                .padding(.top, 9)
                .frame(maxWidth: .infinity)
            }
        }
        .foregroundStyle(ink)
        .background(.white.opacity(0.3), in: .rect(cornerRadius: 22, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(.white.opacity(0.55), lineWidth: 1) }
    }
}

// MARK: - Vault (step 6)

struct VaultBack: View {
    let motion: IntroMotion
    var body: some View {
        ZStack {
        Ellipse()
            .fill(RadialGradient(colors: [Color(red: 0.08, green: 0, blue: 0.004).opacity(0.5), .clear], center: .center, startRadius: 0, endRadius: 140))
            .scaleEffect(x: 1, y: 40 / 280)
            .box(61, 432 - 120, 280, 280)
            .opacity(motion.vaultBack.opacity)
        RoundedRectangle(cornerRadius: 34, style: .continuous)
            .fill(LinearGradient(colors: [Color(red: 0.12, green: 0, blue: 0.016).opacity(0.32), Color(red: 0.12, green: 0, blue: 0.016).opacity(0.16)],
                                 startPoint: .top, endPoint: .bottom))
            .overlay {
                RoundedRectangle(cornerRadius: 34, style: .continuous).strokeBorder(.black.opacity(0.18), lineWidth: 8).blur(radius: 10).offset(y: 3)
                    .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
            }
            .overlay { RoundedRectangle(cornerRadius: 34, style: .continuous).strokeBorder(.white.opacity(0.12), lineWidth: 1) }
            .scaleEffect(motion.vaultBack.s)
            // Seen through the frosted glass, like the cards.
            .blur(radius: 3 * motion.vaultFront.opacity)
            .box(41, 214, 320, 232)
            .opacity(motion.vaultBack.opacity)
        }
            .frame(width: 402, height: 874)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

struct VaultFront: View {
    let motion: IntroMotion
    private static let red = Color(red: 0.639, green: 0.090, blue: 0.059)
    private static let cream = Color(red: 1, green: 0.941, blue: 0.922)

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 34, style: .continuous)
        ZStack {
            shape
                .fill(LinearGradient(stops: [.init(color: .white.opacity(0.3), location: 0), .init(color: .white.opacity(0.07), location: 0.46),
                                             .init(color: .white.opacity(0.16), location: 1)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay { Color.clear.overlay { GlintBand(progress: motion.glint) }.clipShape(shape) }
                .overlay { shape.strokeBorder(.white.opacity(0.3), lineWidth: 1) }
                .overlay { shape.stroke(.white.opacity(0.7), lineWidth: 1).mask(LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: .init(x: 0.5, y: 0.08))) }
                .shadow(color: .black.opacity(0.25), radius: 25, y: 34)
                .offset(y: motion.vaultFront.y)
                .box(41, 214, 320, 232)
                .opacity(motion.vaultFront.opacity)
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [Self.cream, Color(red: 0.97, green: 0.87, blue: 0.84)], startPoint: .top, endPoint: .bottom))
                    .overlay { Circle().strokeBorder(.white.opacity(0.8), lineWidth: 1).mask(LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: .center)) }
                    .shadow(color: Color(red: 0.31, green: 0, blue: 0.02).opacity(0.35), radius: 6, y: 5)
                Circle().fill(Self.red).frame(width: 11, height: 11).offset(y: -3)
                Path { p in
                    p.move(to: CGPoint(x: 20.6, y: 22.5)); p.addLine(to: CGPoint(x: 19, y: 32))
                    p.addLine(to: CGPoint(x: 27, y: 32)); p.addLine(to: CGPoint(x: 25.4, y: 22.5)); p.closeSubpath()
                }
                .fill(Self.red)
                .frame(width: 46, height: 46)
            }
            .frame(width: 46, height: 46)
            .scaleEffect(max(motion.lock, 0))
            .opacity(clamp01(motion.lock * 3))
            .position(x: 201, y: 214)
        }
        .frame(width: 402, height: 874)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct GlintBand: View, Animatable {
    var progress: Double
    nonisolated var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        let p = clamp01(progress)
        LinearGradient(colors: [.white.opacity(0), .white.opacity(0.55), .white.opacity(0)], startPoint: .leading, endPoint: .trailing)
            .frame(width: 109, height: 420)
            .rotationEffect(.degrees(10))
            .blur(radius: 4)
            .offset(x: -180 + 560 * p - 160)
            .opacity(sin(.pi * p))
    }
}

// MARK: - Ripple

/// The flood's edge: a closed Catmull-Rom curve through 28 points whose wobble fades as it grows.
struct RippleShape: Shape {
    var radius: Double
    let t: Double
    let centre: CGPoint

    nonisolated var animatableData: Double {
        get { radius }
        set { radius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let progress = clamp01((radius - 30) / 900)
        let amount = 0.06 * pow(1 - progress, 1.3) + 0.01
        let points: [CGPoint] = (0..<28).map { i in
            let a = Double(i) / 28 * 2 * .pi
            let w = 0.6 * sin(3 * a + 2.1 * t + 0.4) + 0.4 * sin(5 * a - 3.2 * t + 1.7) + 0.25 * sin(8 * a + 4.4 * t + 0.9)
            let r = radius * (1 + amount * w)
            return CGPoint(x: centre.x + r * cos(a), y: centre.y + r * sin(a))
        }
        var path = Path()
        path.move(to: points[0])
        for i in points.indices {
            let p0 = points[(i + 27) % 28], p1 = points[i], p2 = points[(i + 1) % 28], p3 = points[(i + 2) % 28]
            path.addCurve(to: p2,
                          control1: CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6),
                          control2: CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6))
        }
        path.closeSubpath()
        return path
    }
}

/// Rim, inner glow and two echo rings that ride the flood's edge, fading out as it reaches the screen's edges.
struct RippleEffects: View {
    let ripple: RippleShape
    let pal: IntroPalette

    var body: some View {
        let progress = clamp01((ripple.radius - 30) / 900)
        let fx = progress < 0.8 ? 1 : max(0, (1 - progress) / 0.2)
        let r = ripple.radius, c = ripple.centre
        ZStack {
            ripple.stroke(pal.lt.opacity(0.5), lineWidth: 18).blur(radius: 4).mask(ripple)
            ripple.stroke(pal.hi.opacity(0.8), lineWidth: 2.2)
            Circle().stroke(pal.lt.opacity(0.5 * (1 - progress)), lineWidth: 2)
                .frame(width: 2 * (r + 24 + 14 * progress), height: 2 * (r + 24 + 14 * progress)).position(c)
            Circle().stroke(pal.lt.opacity(0.32 * (1 - progress)), lineWidth: 1.3)
                .frame(width: 2 * (r + 58 + 26 * progress), height: 2 * (r + 58 + 26 * progress)).position(c)
        }
        .opacity(fx)
        .allowsHitTesting(false)
    }
}

// MARK: - Next and Get started

/// A 62 pt glass button holding the next step's colour as liquid, inside a six-segment autoplay ring.
struct NextButton: View {
    let motion: IntroMotion
    let now: Date
    let ring: Color
    let liquid: IntroPalette
    let action: () -> Void

    private static let segment = 36.841 / 245.044, pitch = 40.841 / 245.044, start = 2 / 245.044

    var body: some View {
        Button(action: action) {
        ZStack {
            ForEach(0..<6, id: \.self) { i in
                let from = Self.start + Self.pitch * Double(i)
                Circle().trim(from: from, to: from + Self.segment)
                    .stroke(ring.opacity(0.24), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                Circle().trim(from: from, to: from + Self.segment * clamp01(motion.ringValue(i, at: now)))
                    .stroke(ring, style: StrokeStyle(lineWidth: 3, lineCap: .round))
            }
            .frame(width: 78, height: 78)
            .rotationEffect(.degrees(-90))

                ZStack {
                    Circle().fill(.white.opacity(0.1))
                    LinearGradient(colors: [liquid.lt, liquid.base], startPoint: .top, endPoint: .bottom)
                        .frame(height: 62 * motion.liquid)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .clipShape(Circle())
                    Circle().strokeBorder(LinearGradient(colors: [.white.opacity(0.55), .black.opacity(0.06)], startPoint: .top, endPoint: .bottom), lineWidth: 1)
                    Image(systemName: "arrow.right").font(.system(size: 21, weight: .bold)).foregroundStyle(liquid.ink)
                }
                .frame(width: 62, height: 62)
                .glassEffect(.regular, in: .circle)
                .shadow(color: liquid.shd.opacity(0.4), radius: 8, y: 6)
                .scaleEffect(motion.press)
        }
        .frame(width: 88, height: 88)
        .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

/// The last step's call to action: a cream capsule whose leading edge stretches out from the Next button.
struct GetStarted: View, Animatable {
    var width: Double
    let cream: IntroPalette
    let action: () -> Void

    nonisolated var animatableData: Double {
        get { width }
        set { width = newValue }
    }

    var body: some View {
        let w = clamp01(width)
        Button(action: action) {
            HStack(spacing: 10) {
                Text("Get started").font(.system(size: 17, weight: .bold)).tracking(-0.17)
                Image(systemName: "arrow.right").font(.system(size: 17, weight: .bold))
            }
            .opacity(clamp01((w - 0.55) / 0.45))
            .foregroundStyle(cream.ink)
            .frame(width: 354, height: 56)
            .background(cream.base, in: .capsule)
            .mask(alignment: .trailing) { Capsule().frame(width: 62 + 292 * w) }
        }
        .buttonStyle(.plain)
        .opacity(w > 0.001 ? 1 : 0)
    }
}
