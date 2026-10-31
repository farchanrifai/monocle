import SwiftUI

/// The first-launch intro: one Ankka card carried through six full-bleed colour steps, a liquid ripple between them.
/// Built from the Claude Design canvas "Ankka Onboarding" (round 2): every time, spring and colour comes from its motion
/// spec. Coordinates are the design's 402×874 pt canvas, scaled to fit the screen. Drawings live in OnboardingIntroArt.
struct OnboardingIntro: View {
    let onFinish: () -> Void
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var m = IntroMotion()

    static let canvas = CGSize(width: 402, height: 874)
    static let nextCentre = CGPoint(x: 346, y: 784)

    var body: some View {
        GeometryReader { geo in
            let scale = min(geo.size.width / Self.canvas.width, geo.size.height / Self.canvas.height)
            TimelineView(.animation(paused: reduceMotion)) { timeline in
                stage(t: timeline.date.timeIntervalSinceReferenceDate)
                    .frame(width: Self.canvas.width, height: Self.canvas.height)
                    .scaleEffect(scale)
                    .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        .ignoresSafeArea()
        .background(pal(m.page).deep.ignoresSafeArea())
        .statusBarHidden()
        .sensoryFeedback(.impact(weight: .heavy), trigger: m.heavy)
        .sensoryFeedback(.impact(weight: .medium), trigger: m.medium)
        .sensoryFeedback(.impact(weight: .light), trigger: m.light)
        .sensoryFeedback(.impact(flexibility: .rigid), trigger: m.rigid)
        .sensoryFeedback(.success, trigger: m.success)
        .sensoryFeedback(.selection, trigger: m.tick)
        .task { m.start(reduce: reduceMotion) }
        .onDisappear { m.stop() }
    }

    private func pal(_ step: Int) -> IntroPalette { IntroPalette.step(step, dark: scheme == .dark) }

    @ViewBuilder private func stage(t: Double) -> some View {
        let drift = CGPoint(x: 0.42 * sin(2 * .pi * t / 7.3), y: 0.30 * sin(2 * .pi * t / 9.1 + 1.3))
        ZStack {
            // Outgoing page wobbles from the Next button; the incoming one floods in through the ripple.
            IntroPage(step: m.page, pal: pal(m.page), props: m.props[m.page] ?? [], t: t, gain: m.idle, drift: drift)
                .scaleEffect(x: m.jellyX, y: m.jellyY, anchor: anchor(Self.nextCentre))
            if let next = m.incoming {
                let ripple = RippleShape(radius: m.ripple, t: t - m.rippleStart, centre: Self.nextCentre)
                IntroPage(step: next, pal: pal(next), props: m.props[next] ?? [], t: t, gain: m.idle, drift: drift)
                    .scaleEffect(m.incomingScale, anchor: anchor(Self.nextCentre))
                    .mask { if reduceMotion { Rectangle().opacity(m.crossfade) } else { ripple } }
                if !reduceMotion { RippleEffects(ripple: ripple, pal: pal(next)) }
            }
            VaultBack(motion: m)
            hero(t: t, drift: drift)
            StepObjects(motion: m, t: t, pal: pal)
            VaultFront(motion: m)
            ForEach(m.textSteps, id: \.self) { step in
                IntroText(step: step, ink: pal(step).ink, lines: m.lines[step] ?? IntroMotion.hiddenLines)
            }
            Color.clear.contentShape(Rectangle()).onTapGesture { m.togglePause() }
                .accessibilityHidden(true)
            controls(now: Date(timeIntervalSinceReferenceDate: t))
        }
    }

    private func anchor(_ p: CGPoint) -> UnitPoint { UnitPoint(x: p.x / Self.canvas.width, y: p.y / Self.canvas.height) }

    // MARK: Hero

    private func hero(t: Double, drift: CGPoint) -> some View {
        let shadow = pal(m.shadowStep).shd
        return ZStack {
            ForEach(IntroCard.Kind.allCases, id: \.self) { kind in
                let pose = m.pose(kind)
                let floatY = 3.2 * sin(2 * .pi * t / 5.2 + kind.phase) * m.idle
                let floatZ = 0.55 * sin(2 * .pi * t / 6.1 + 1.7 * kind.phase) * m.idle
                IntroCard(kind: kind, motion: m, shadow: shadow)
                    .scaleEffect(x: kind == .daily ? m.squashX : 1, y: kind == .daily ? m.squashY : 1, anchor: .bottom)
                    .scaleEffect(pose.s)
                    .rotationEffect(.degrees(pose.rz + floatZ))
                    .rotation3DEffect(.degrees(pose.ry + 7 * drift.x * m.idle), axis: (0, 1, 0), perspective: 0.26)
                    .modifier(CardFlip(rx: pose.rx - 5 * drift.y * m.idle, kind: kind, motion: m, shadow: shadow))
                    .position(x: 201 + pose.x + 9 * drift.x * m.idle, y: 322 + pose.y + floatY + 7 * drift.y * m.idle)
                    .zIndex(kind == .tokyo && m.tokyoFront ? 3 : kind == .daily ? 2 : kind == .bali ? 1 : 0)
            }
        }
        .scaleEffect(m.liftScale, anchor: UnitPoint(x: 0.5, y: 322 / Self.canvas.height))
        .offset(y: m.liftY)
        .opacity(m.heroOpacity)
        // Inside the vault the cards sit behind frosted glass.
        .blur(radius: 3 * m.vaultFront.opacity)
        .saturation(1 + 0.15 * m.vaultFront.opacity)
        .accessibilityHidden(true)
    }

    // MARK: Controls

    private func controls(now: Date) -> some View {
        let ink = pal(m.inkStep).ink
        return ZStack {
            Button("Skip") { m.skip() }
                .font(.system(size: 16, weight: .semibold))
                .padding(.horizontal, 18)
                .frame(height: 44)
                .glassEffect(.regular.interactive(), in: .capsule)
                .fixedSize()
                .frame(width: 200, alignment: .trailing)
                .position(x: 402 - 16 - 100, y: 66 + 22)
                .opacity(m.skipOpacity)
                .allowsHitTesting(m.skipOpacity > 0.5)
                .accessibilityIdentifier("onboardingSkip")

            NextButton(motion: m, now: now, ring: ink, liquid: pal(m.liquidStep)) { m.next() }
                .position(Self.nextCentre)
                .opacity(m.nextOpacity)
                .allowsHitTesting(m.nextOpacity > 0.5)
                .accessibilityLabel("Next")
                .accessibilityIdentifier("onboardingContinue")

            GetStarted(width: m.cta, cream: pal(7)) { onFinish() }
                .position(x: 201, y: 756 + 28)
                .opacity(m.ctaOpacity)
                .allowsHitTesting(m.cta > 0.5)
                .accessibilityIdentifier("onboardingGetStarted")
        }
        .foregroundStyle(ink)
        .opacity(m.chrome)
    }
}

// MARK: - Springs

enum IntroSpring {
    static func s(_ response: Double, _ damping: Double) -> Animation { .spring(response: response, dampingFraction: damping) }
    static let drop = s(0.62, 0.74), drift = s(0.90, 0.80), slap = s(0.55, 0.42), twist = s(0.70, 0.62)
    static let squashIn = s(0.16, 0.70), squashOut = s(0.50, 0.42), fan = s(0.55, 0.68)
    static let odo = s(0.90, 0.86), total = s(0.95, 0.88), rollOut = s(0.42, 0.92), counter = s(0.50, 0.80)
    static let pop = s(0.60, 0.62), fade = s(0.40, 1.00), rise = s(0.55, 0.80), exit = s(0.32, 1.00)
    static let ripple = s(0.80, 1.00), jellyIn = s(0.18, 0.70), jellyOut = s(0.50, 0.32), settle = s(0.55, 0.55)
    static let lift = s(0.38, 0.70), land = s(0.55, 0.80), hand = s(0.62, 0.72), restack = s(0.60, 0.80)
    static let ring = s(0.50, 0.90), pour = s(0.26, 1.00), fill = s(0.60, 0.75), chrome = s(0.50, 1.00)
    static let press = s(0.14, 0.80), release = s(0.42, 0.45), ink = s(0.12, 1.00), tint = s(0.45, 1.00)
    static let idle = s(1.20, 1.00), cross = s(0.45, 1.00), xfOut = s(0.22, 1.00), xfIn = s(0.30, 1.00)
    static let morph = s(0.50, 0.78), arc = s(0.50, 0.86), absorb = s(0.22, 1.00), hop = s(0.45, 0.75)
    static let flip = s(0.90, 0.82), coin = s(0.50, 0.55), fly = s(1.60, 1.00), ringfill = s(1.10, 0.90)
    static let snap = s(0.42, 0.58), vault = s(0.62, 0.80), glass = s(0.55, 0.85), lock = s(0.40, 0.55)
    static let glint = s(1.00, 1.00), cta = s(0.60, 0.82)
}

// MARK: - Motion state

struct CardPose { var x = 0.0, y = 0.0, rx = 10.0, ry = -7.0, rz = 0.0, s = 1.0 }
struct PropState { var pop = 0.0, fade = 0.0 }
struct LineState { var y = 32.0, opacity = 0.0, blur = 8.0 }
/// A flying object: position offset, scale, rotation, opacity.
struct Flyer { var x = 0.0, y = 0.0, s = 1.0, r = 0.0, opacity = 0.0 }

private enum Poses {
    typealias Trio = (tokyo: CardPose, bali: CardPose, daily: CardPose)
    static let s1: Trio = (CardPose(x: -36, y: -46, rz: -12, s: 0.94), CardPose(x: 34, y: -32, rz: 7, s: 0.94), CardPose(rz: -4))
    static let hand: Trio = (CardPose(x: -68, y: -78, rx: 6, ry: 2, rz: -9, s: 0.80), CardPose(x: -4, y: -14, rx: 6, ry: 0, rz: -2, s: 0.80),
                            CardPose(x: 62, y: 56, rx: 6, ry: -2, rz: 7, s: 0.86))
    static let s2: Trio = (CardPose(x: -38, y: -48, rz: -11, s: 0.94), CardPose(x: 34, y: -32, rz: 7, s: 0.94), CardPose(rz: -3))
    static let s3: Trio = (CardPose(x: -38, y: -8, rz: -11, s: 0.94), CardPose(x: 34, y: 8, rz: 7, s: 0.94), CardPose(y: 40, rz: -3))
    static let s4: Trio = (CardPose(x: 0, y: 12, rx: 370, ry: -6, rz: -2), CardPose(x: 36, y: -24, rz: 7, s: 0.94), CardPose(x: -40, y: -34, rz: -10, s: 0.94))
    static let s5: Trio = (CardPose(x: -38, y: -78, rz: -11, s: 0.94), CardPose(x: 34, y: -62, rz: 7, s: 0.94), CardPose(y: -30, rz: -3))
    static let front = CardPose(x: 0, y: 16, rx: 6, ry: 0, rz: 0, s: 0.86)
    static let left = CardPose(x: -22, y: -14, rx: 6, ry: 0, rz: -4, s: 0.80)
    static let right = CardPose(x: 22, y: -6, rx: 6, ry: 0, rz: 4, s: 0.80)
}

@MainActor @Observable
final class IntroMotion {
    static let hiddenLines = [LineState](repeating: LineState(), count: 3)
    static let dwell = [0, 5.2, 5.6, 6.6, 6.8, 6.4, 6.4]
    static let propCounts = [0, 5, 3, 3, 2, 2, 2]
    static let lastStep = 6

    // Pages and the flood
    var page = 1
    var incoming: Int?
    var ripple = 30.0
    var rippleStart = 0.0
    var crossfade = 0.0
    var jellyX = 1.0
    var jellyY = 1.0
    var incomingScale = 1.0

    // Hero
    var daily = CardPose()
    var tokyo = CardPose()
    var bali = CardPose()
    var tokyoFront = false
    var squashX = 1.0
    var squashY = 1.0
    var liftY = 0.0
    var liftScale = 1.0
    var heroOpacity = 1.0

    // Card faces
    var wordmark = [Double](repeating: 0, count: 5)
    var totals: [IntroCard.Kind: [Double]] = [:]
    var totalOpacity: [IntroCard.Kind: Double] = [:]
    var captionOpacity: [IntroCard.Kind: Double] = [:]
    var names = 0.0
    var mark = 0.0
    var dailyCount = 0.0
    var yen = [Double](repeating: 0, count: 4)
    var yenOpacity = 0.0
    var rupiah = [Double](repeating: 0, count: 6)
    var rupiahOpacity = 0.0
    var paidOpacity = 0.0
    var budget = [0.0, 0.0]
    var budgetOpacity = 0.0
    var budgetRing = 0.0

    // Pages' props and text
    var props: [Int: [PropState]] = [:]
    var lines: [Int: [LineState]] = [:]
    var textSteps = [1]

    // Step 3: chat bubble → expense chip
    var bubble = Flyer(s: 0.6)
    var typed = 0
    var morph = 0.0
    var chipArc = 0.0
    var chipWheels = [Double](repeating: 0, count: 5)
    var chip = Flyer(opacity: 1)

    // Step 4: yen coins and the paper plane
    var coins = [Flyer](repeating: Flyer(y: -380), count: 3)
    var plane = 0.0
    var planeOpacity = 0.0
    var routeOpacity = 1.0

    // Step 5: calendar and bills
    var calendar = Flyer(y: 18)
    var bills = [Flyer](repeating: Flyer(x: 240, y: -120, s: 1.3, r: 20), count: 3)

    // Step 6: the vault and Get started
    var vaultBack = Flyer(s: 0.92)
    var vaultFront = Flyer(y: 26)
    var lock = 0.0
    var glint = 0.0
    var cta = 0.0
    var ctaOpacity = 1.0

    // Controls
    var chrome = 0.0
    var idle = 0.0
    var liquid = 0.0
    var liquidStep = 2
    var press = 1.0
    var inkStep = 1
    var shadowStep = 1
    var skipOpacity = 1.0
    var nextOpacity = 1.0
    var ring = [Double](repeating: 0, count: 6)
    var paused = false

    // Haptic triggers
    var heavy = 0
    var medium = 0
    var light = 0
    var rigid = 0
    var success = 0
    var tick = 0

    private var tasks: [Task<Void, Never>] = []
    private var autoplay: Task<Void, Never>?
    private var dwellStart: Date?
    private var dwellBanked = 0.0
    private var locked = true
    private var pendingNext = false
    private var reduce = false

    func pose(_ kind: IntroCard.Kind) -> CardPose {
        switch kind { case .daily: daily; case .tokyo: tokyo; case .bali: bali }
    }

    private func setPoses(_ set: Poses.Trio) { tokyo = set.tokyo; bali = set.bali; daily = set.daily }

    /// Runs `change` with `animation` after `ms` milliseconds.
    private func at(_ ms: Double, _ animation: Animation?, _ change: @escaping @MainActor () -> Void) {
        tasks.append(Task { @MainActor in
            if ms > 0 { try? await Task.sleep(for: .seconds(ms / 1000)) }
            guard !Task.isCancelled else { return }
            if let animation { withAnimation(animation) { change() } } else { change() }
        })
    }

    func stop() {
        tasks.forEach { $0.cancel() }
        tasks = []
        autoplay?.cancel()
    }

    // MARK: Step 1, "Meet Ankka."

    func start(reduce: Bool) {
        self.reduce = reduce
        for step in 1...6 { props[step] = Array(repeating: PropState(), count: Self.propCounts[step]) }
        lines[1] = Self.hiddenLines
        for kind in IntroCard.Kind.allCases {
            totals[kind] = Array(repeating: 0, count: kind.totalTargets.count)
            totalOpacity[kind] = 0
            captionOpacity[kind] = 0
        }

        if reduce {
            setPoses(Poses.s1)
            faces(1)
            props[1] = Array(repeating: PropState(pop: 1, fade: 1), count: 5)
            heroOpacity = 0
            withAnimation(IntroSpring.cross) {
                heroOpacity = 1
                lines[1] = Array(repeating: LineState(y: 0, opacity: 1, blur: 0), count: 3)
                chrome = 1
                liquid = 1
            }
            at(420, nil) { self.locked = false }
            startDwell()
            return
        }

        // The card falls tipped back, slaps flat on contact, squashes and rocks; the back cards fall hidden behind it.
        daily = CardPose(y: -660, rx: 40, ry: 14, rz: -16, s: 0.96)
        tokyo = CardPose(y: -660, rx: 40, ry: 14, rz: -19.5, s: 0.94 * 0.96)
        bali = CardPose(y: -660, rx: 40, ry: 14, rz: -19.6, s: 0.94 * 0.96)
        at(0, IntroSpring.drop) { self.daily.y = 0; self.tokyo.y = 0; self.bali.y = 0 }
        at(0, IntroSpring.drift) {
            self.daily.rx = 30; self.tokyo.rx = 30; self.bali.rx = 30
            self.daily.rz = -8; self.tokyo.rz = -11.5; self.bali.rz = -11.6
        }
        at(0, IntroSpring.twist) {
            self.daily.ry = -7; self.tokyo.ry = -7; self.bali.ry = -7
            self.daily.s = 1; self.tokyo.s = 0.94; self.bali.s = 0.94
        }
        at(300, IntroSpring.slap) { self.daily.rx = 10; self.tokyo.rx = 10; self.bali.rx = 10 }
        at(330, IntroSpring.twist) { self.daily.rz = -4; self.tokyo.rz = -3.5; self.bali.rz = -3.6 }
        at(330, IntroSpring.squashIn) { self.squashY = 0.955; self.squashX = 1.03 }
        at(353, nil) { self.heavy += 1 }
        at(420, IntroSpring.squashOut) { self.squashY = 1; self.squashX = 1 }
        at(420, nil) { self.locked = false }

        // Wordmark wheels roll up to a·n·k·k·a; each lands with a tick.
        for i in 0..<5 {
            at(420 + 60 * Double(i), IntroSpring.odo) { self.wordmark[i] = IntroCard.wordmarkTargets[i] }
            at(1151 + 60 * Double(i), nil) { self.tick += 1 }
        }
        // Back cards fan out behind Daily and the names appear.
        at(760, IntroSpring.fan) { self.tokyo.x = -36; self.tokyo.y = -46; self.tokyo.rz = -12 }
        at(830, IntroSpring.fan) { self.bali.x = 34; self.bali.y = -32; self.bali.rz = 7 }
        at(760, IntroSpring.fade) { self.names = 1 }

        popProps(step: 1, from: 520, gap: 50)
        riseText(step: 1, from: 600)
        at(1150, IntroSpring.chrome) { self.chrome = 1 }
        at(1150, IntroSpring.fill) { self.liquid = 1 }
        at(1400, IntroSpring.idle) { self.idle = 1 }
        startDwell()
    }

    private func popProps(step: Int, from start: Double, gap: Double) {
        for i in (props[step] ?? []).indices {
            at(start + gap * Double(i), IntroSpring.pop) { self.props[step]?[i].pop = 1 }
            at(start + gap * Double(i), IntroSpring.fade) { self.props[step]?[i].fade = 1 }
        }
    }

    /// Headline lines 60 ms apart, the body 80 ms after the second line.
    private func riseText(step: Int, from start: Double) {
        lines[step] = Self.hiddenLines
        for (i, delay) in [0.0, 60, 140].enumerated() {
            at(start + delay, IntroSpring.rise) { self.lines[step]?[i].y = 0 }
            at(start + delay, IntroSpring.fade) { self.lines[step]?[i].opacity = 1; self.lines[step]?[i].blur = 0 }
        }
    }

    // MARK: Card faces

    /// Every card face as it reads at the end of step `n`. Settles faces whose step was cut short by a tap or Skip.
    private func faces(_ n: Int) {
        wordmark = IntroCard.wordmarkTargets.map { n == 1 ? $0 : $0 + 1 }
        names = 1
        mark = n >= 2 ? 1 : 0
        for kind in IntroCard.Kind.allCases {
            totals[kind] = n >= 2 ? (kind == .daily && n >= 3 ? IntroCard.dailyAfterKopi : kind.totalTargets) : totals[kind]
        }
        totalOpacity[.daily] = n >= 2 && n < 5 ? 1 : 0
        captionOpacity[.daily] = n >= 2 && n < 5 ? 1 : 0
        totalOpacity[.tokyo] = n >= 2 && n < 4 ? 1 : 0
        captionOpacity[.tokyo] = n >= 2 && n < 4 ? 1 : 0
        totalOpacity[.bali] = n >= 2 ? 1 : 0
        captionOpacity[.bali] = n >= 2 ? 1 : 0
        dailyCount = n >= 3 ? 1 : 0
        if n >= 4 {
            yen = IntroCard.yenTargets.map { $0 + 1 }
            yenOpacity = 0
            rupiah = IntroCard.rupiahTargets
            rupiahOpacity = 1
            paidOpacity = 1
        }
        if n >= 5 {
            budget = IntroCard.budgetTargets
            budgetOpacity = 1
            budgetRing = 0.7
        }
    }

    // MARK: Autoplay

    private func startDwell() {
        dwellBanked = 0
        dwellStart = paused ? nil : .now
        scheduleAdvance()
    }

    private func scheduleAdvance() {
        autoplay?.cancel()
        guard !paused, page < Self.lastStep else { return }
        let remaining = max(0, Self.dwell[page] - dwellBanked)
        autoplay = Task { @MainActor in
            try? await Task.sleep(for: .seconds(remaining))
            guard !Task.isCancelled else { return }
            self.go(to: self.page + 1)
        }
    }

    func togglePause() {
        guard page < Self.lastStep, incoming == nil else { return }
        paused.toggle()
        if paused {
            if let start = dwellStart { dwellBanked += Date.now.timeIntervalSince(start) }
            dwellStart = nil
            autoplay?.cancel()
        } else {
            dwellStart = .now
            scheduleAdvance()
        }
    }

    // MARK: Step changes

    /// The current step's ring segment fills over its dwell; segments already passed hold their spring-animated value.
    func ringValue(_ i: Int, at now: Date) -> Double {
        guard i == page - 1, incoming == nil, page < Self.lastStep else { return ring[i] }
        let elapsed = dwellBanked + (dwellStart.map { now.timeIntervalSince($0) } ?? 0)
        return min(1, elapsed / Self.dwell[page])
    }

    /// Every tap presses the button. A tap while the flood is still running is kept and plays once the step lands.
    func next() {
        withAnimation(IntroSpring.press) { press = 0.88 }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(90))
            withAnimation(IntroSpring.release) { self.press = 1 }
        }
        guard page < Self.lastStep else { return }
        if incoming != nil { pendingNext = true; return }
        go(to: page + 1)
    }

    /// Skip from any step runs the change into step 6.
    func skip() {
        guard page < Self.lastStep else { return }
        go(to: Self.lastStep, force: true)
    }

    private func go(to to: Int, force: Bool = false) {
        guard force || !locked, incoming == nil, to > page, to <= Self.lastStep else { return }
        autoplay?.cancel()
        tasks.forEach { $0.cancel() }
        tasks = []
        locked = true
        paused = false
        let from = page
        ring[from - 1] = ringValue(from - 1, at: .now)
        for i in (from - 1)..<(to - 1) { withAnimation(IntroSpring.ring) { ring[i] = 1 } }
        medium += 1
        // Faces whose beat was cut short roll on to their end values, so a face is never half-changed.
        withAnimation(IntroSpring.total) { faces(from) }
        withAnimation(IntroSpring.squashOut) { squashX = 1; squashY = 1 }
        withAnimation(IntroSpring.chrome) { chrome = 1 }
        withAnimation(IntroSpring.idle) { idle = 1 }
        leaveObjects(from)

        if reduce { crossfade(from: from, to: to); return }

        // The flood: the ripple grows from the Next button, the old page jellies, the new one settles from 2.5% large.
        incoming = to
        ripple = 30
        rippleStart = Date.now.timeIntervalSinceReferenceDate
        incomingScale = 1.025
        withAnimation(IntroSpring.ripple) { ripple = 980 }
        withAnimation(IntroSpring.settle) { incomingScale = 1 }
        withAnimation(IntroSpring.jellyIn) { jellyX = 1.022; jellyY = 0.976 }
        at(90, IntroSpring.jellyOut) { self.jellyX = 1; self.jellyY = 1 }
        at(946, nil) { self.arrive(at: to) }
        at(700, nil) { self.locked = false }

        // Next's liquid pours out, takes the following step's colour while empty, then refills.
        withAnimation(IntroSpring.pour) { liquid = 0 }
        at(260, nil) { self.liquidStep = to + 1 }
        at(420, IntroSpring.fill) { self.liquid = 1 }
        at(115, IntroSpring.ink) { self.inkStep = to }
        withAnimation(IntroSpring.tint) { shadowStep = to }

        // Text: the old lines leave upward, the new ones rise in.
        for (i, delay) in [0.0, 30, 0].enumerated() {
            at(delay, IntroSpring.exit) { self.lines[from]?[i] = LineState(y: -28, opacity: 0, blur: 6) }
        }
        textSteps = [from, to]
        riseText(step: to, from: 160)
        popProps(step: to, from: to == 6 ? 760 : 650, gap: 60)

        // Hero: the wave picks the stack up and sets it down.
        withAnimation(IntroSpring.lift) { liftScale = 1.045; liftY = -14 }
        at(480, IntroSpring.land) { self.liftScale = 1; self.liftY = 0 }

        switch to {
        case 2: beatHand()
        case 3: beatKopi()
        case 4: beatYen()
        case 5: beatBudget()
        default: beatVault()
        }
    }

    private func arrive(at step: Int) {
        page = step
        incoming = nil
        crossfade = 0
        textSteps = [step]
        startDwell()
        if pendingNext {
            pendingNext = false
            locked = false
            go(to: page + 1)
        }
    }

    /// The leaving step's objects fade out at the tap.
    private func leaveObjects(_ step: Int) {
        withAnimation(IntroSpring.xfOut) {
            switch step {
            case 3: bubble.opacity = 0; chip.opacity = 0
            case 4: for i in coins.indices { coins[i].opacity = 0 }; planeOpacity = 0; routeOpacity = 0
            case 5: calendar.opacity = 0; for i in bills.indices { bills[i].opacity = 0 }
            default: break
            }
        }
    }

    // MARK: Step 2, "A card per purpose."

    private func beatHand() {
        at(60, IntroSpring.hand) { self.setPoses(Poses.hand) }
        for i in 0..<5 {
            at(100 + 35 * Double(i), IntroSpring.rollOut) { self.wordmark[i] = IntroCard.wordmarkTargets[i] + 1 }
        }
        for (kind, start) in [(IntroCard.Kind.tokyo, 260.0), (.bali, 340), (.daily, 420)] {
            at(start, IntroSpring.fade) { self.totalOpacity[kind] = 1 }
            for (i, target) in kind.totalTargets.enumerated() {
                at(start + 25 * Double(i), IntroSpring.total) { self.totals[kind]?[i] = target }
            }
        }
        for i in 0..<7 { at(1262 + 25 * Double(i), nil) { self.tick += 1 } }
        at(520, IntroSpring.fade) { for kind in IntroCard.Kind.allCases { self.captionOpacity[kind] = 1 } }
        at(640, IntroSpring.fade) { self.mark = 1 }
        at(1700, IntroSpring.restack) { self.setPoses(Poses.s2) }
    }

    // MARK: Step 3, "Kopi 28rb. Done."

    private func beatKopi() {
        at(60, IntroSpring.hand) { self.setPoses(Poses.s3) }
        bubble = Flyer(y: 16, s: 0.6)
        typed = 0
        morph = 0
        chipArc = 0
        chip = Flyer(opacity: 1)
        chipWheels = Array(repeating: 0, count: 5)
        at(780, IntroSpring.fade) { self.bubble.opacity = 1 }
        at(780, IntroSpring.pop) { self.bubble.s = 1; self.bubble.y = 0 }
        for i in 1...9 { at(900 + 85 * Double(i), nil) { self.typed = i } }
        at(1980, IntroSpring.morph) { self.morph = 1 }
        at(1980, IntroSpring.squashIn) { self.bubble.s = 1.06 }
        at(2070, IntroSpring.release) { self.bubble.s = 1 }
        for (i, target) in IntroCard.chipTargets.enumerated() {
            at(2080 + 30 * Double(i), IntroSpring.total) { self.chipWheels[i] = target }
        }
        at(2880, IntroSpring.arc) { self.chipArc = 1 }
        // The chip lands on Daily: it's absorbed, the card squashes and the total rolls up by Rp 28,000.
        at(3205, IntroSpring.absorb) { self.chip.opacity = 0; self.chip.s = 0.4 }
        at(3205, nil) { self.light += 1 }
        at(3205, IntroSpring.squashIn) { self.squashX = 1.015; self.squashY = 0.97 }
        at(3295, IntroSpring.squashOut) { self.squashX = 1; self.squashY = 1 }
        at(3245, IntroSpring.total) { self.totals[.daily]?[2] = IntroCard.dailyAfterKopi[2] }
        at(3275, IntroSpring.total) { self.totals[.daily]?[3] = IntroCard.dailyAfterKopi[3] }
        at(3325, IntroSpring.counter) { self.dailyCount = 1 }
        for i in 0..<2 { at(3840 + 25 * Double(i), nil) { self.tick += 1 } }
    }

    // MARK: Step 4, "Spend in yen."

    private func beatYen() {
        let pose = Poses.s4
        at(60, IntroSpring.hand) {
            self.tokyo.x = pose.tokyo.x; self.tokyo.rz = pose.tokyo.rz; self.tokyo.ry = pose.tokyo.ry
            self.daily = pose.daily; self.bali = pose.bali
        }
        // Tokyo hops, flips a full turn to the front and lands.
        at(60, IntroSpring.hop) { self.tokyo.y = -110; self.tokyo.s = 1.06 }
        at(420, IntroSpring.land) { self.tokyo.y = pose.tokyo.y; self.tokyo.s = pose.tokyo.s }
        at(60, IntroSpring.flip) { self.tokyo.rx = 370 }
        at(185, nil) { self.tokyoFront = true }
        at(500, IntroSpring.fade) { self.totalOpacity[.tokyo] = 0 }
        at(950, IntroSpring.fade) { self.yenOpacity = 1 }
        for (i, target) in IntroCard.yenTargets.enumerated() {
            at(950 + 30 * Double(i), IntroSpring.total) { self.yen[i] = target }
        }
        // Three yen coins drop onto the card.
        for i in coins.indices {
            coins[i] = Flyer(y: -380, r: -50 + 25 * Double(i))
            let start = 900 + 110 * Double(i)
            at(start, IntroSpring.absorb) { self.coins[i].opacity = 1 }
            at(start, IntroSpring.coin) { self.coins[i].y = 0 }
            at(start, IntroSpring.twist) { self.coins[i].r = 0 }
            at(1110 + 110 * Double(i), nil) { self.light += 1 }
        }
        plane = 0
        planeOpacity = 0
        routeOpacity = 1
        at(1250, IntroSpring.fade) { self.planeOpacity = 1 }
        at(1250, IntroSpring.fly) { self.plane = 1 }
        // ¥1,200 rolls away and ≈ Rp 128,000 rolls in.
        at(2500, IntroSpring.fade) { self.yenOpacity = 0 }
        for (i, target) in IntroCard.yenTargets.enumerated() {
            at(2500 + 25 * Double(i), IntroSpring.rollOut) { self.yen[i] = target + 1 }
        }
        at(2560, IntroSpring.fade) { self.rupiahOpacity = 1 }
        for (i, target) in IntroCard.rupiahTargets.enumerated() {
            at(2560 + 25 * Double(i), IntroSpring.total) { self.rupiah[i] = target }
        }
        for i in 0..<6 { at(3295 + 25 * Double(i), nil) { self.tick += 1 } }
        at(2600, IntroSpring.fade) { self.captionOpacity[.tokyo] = 0 }
        at(2650, IntroSpring.fade) { self.paidOpacity = 1 }
    }

    // MARK: Step 5, "Know what's left."

    private func beatBudget() {
        let pose = Poses.s5
        if tokyoFront {
            // Tokyo flips back behind the stack, swapping order while it's edge-on.
            at(60, IntroSpring.flip) { self.tokyo.rx = 10 }
            at(200, nil) { self.tokyoFront = false }
            at(60, IntroSpring.hand) { self.tokyo.x = pose.tokyo.x; self.tokyo.s = pose.tokyo.s; self.tokyo.rz = pose.tokyo.rz; self.tokyo.ry = pose.tokyo.ry }
            at(60, IntroSpring.hop) { self.tokyo.y = pose.tokyo.y - 60 }
            at(420, IntroSpring.land) { self.tokyo.y = pose.tokyo.y }
        } else {
            at(60, IntroSpring.hand) { self.tokyo = pose.tokyo }
        }
        at(60, IntroSpring.hand) { self.daily = pose.daily; self.bali = pose.bali }
        at(450, IntroSpring.fade) { self.totalOpacity[.daily] = 0; self.captionOpacity[.daily] = 0 }
        at(600, IntroSpring.fade) { self.budgetOpacity = 1 }
        for (i, target) in IntroCard.budgetTargets.enumerated() {
            at(600 + 40 * Double(i), IntroSpring.total) { self.budget[i] = target }
        }
        at(700, IntroSpring.ringfill) { self.budgetRing = 0.7 }
        calendar = Flyer(y: 18)
        at(900, IntroSpring.fade) { self.calendar.opacity = 1 }
        at(900, IntroSpring.rise) { self.calendar.y = 0 }
        // Three bill chips snap onto the week strip.
        for i in bills.indices {
            bills[i] = Flyer(x: 240, y: -120, s: 1.3, r: 20)
            let start = 1250 + 200 * Double(i)
            at(start, IntroSpring.absorb) { self.bills[i].opacity = 1 }
            at(start, IntroSpring.snap) { self.bills[i].x = 0; self.bills[i].y = 0; self.bills[i].s = 1; self.bills[i].r = 0 }
            at(1430 + 200 * Double(i), nil) { self.rigid += 1 }
        }
    }

    // MARK: Step 6, "Yours, privately."

    private func vaultPoses() -> Poses.Trio {
        var set: Poses.Trio = tokyoFront ? (Poses.front, Poses.right, Poses.left) : (Poses.left, Poses.right, Poses.front)
        if tokyo.rx > 180 { set.tokyo.rx += 360 } // keeps its flip, no extra turn
        return set
    }

    private func beatVault() {
        let set = vaultPoses()
        at(380, IntroSpring.vault) { self.setPoses(set) }
        at(460, IntroSpring.fade) { self.vaultBack.opacity = 1 }
        at(460, IntroSpring.pop) { self.vaultBack.s = 1 }
        at(1000, IntroSpring.fade) { self.vaultFront.opacity = 1 }
        at(1000, IntroSpring.glass) { self.vaultFront.y = 0 }
        at(1350, IntroSpring.lock) { self.lock = 1 }
        at(1510, nil) { self.success += 1 }
        at(1500, IntroSpring.glint) { self.glint = 1 }
        at(300, IntroSpring.fade) { self.skipOpacity = 0 }
        at(1200, IntroSpring.xfOut) { self.nextOpacity = 0 }
        at(1200, IntroSpring.cta) { self.cta = 1 }
    }

    // MARK: Reduce Motion

    /// The page crossfades; the hero fades out, takes the step's end state at 200 ms and fades back in.
    private func crossfade(from: Int, to: Int) {
        incoming = to
        crossfade = 0
        withAnimation(IntroSpring.cross) { crossfade = 1 }
        lines[to] = Array(repeating: LineState(y: 0, opacity: 0, blur: 0), count: 3)
        textSteps = [from, to]
        withAnimation(IntroSpring.fade) {
            lines[from] = Array(repeating: LineState(y: 0, opacity: 0, blur: 0), count: 3)
            lines[to] = Array(repeating: LineState(y: 0, opacity: 1, blur: 0), count: 3)
        }
        props[to] = Array(repeating: PropState(pop: 1, fade: 1), count: Self.propCounts[to])
        withAnimation(IntroSpring.xfOut) { heroOpacity = 0 }
        at(200, nil) { self.endState(to) }
        at(200, IntroSpring.xfIn) { self.heroOpacity = 1 }
        withAnimation(IntroSpring.cross) { inkStep = to; shadowStep = to; liquidStep = to + 1 }
        at(700, nil) { self.arrive(at: to); self.locked = false }
    }

    private func endState(_ step: Int) {
        faces(step)
        switch step {
        case 2: setPoses(Poses.hand)
        case 3:
            setPoses(Poses.s3)
            bubble = Flyer(opacity: 1)
            typed = 9
        case 4:
            setPoses(Poses.s4)
            tokyoFront = true
            for i in coins.indices { coins[i] = Flyer(opacity: 1) }
            plane = 1; planeOpacity = 1; routeOpacity = 1
        case 5:
            tokyoFront = false
            setPoses(Poses.s5)
            calendar = Flyer(opacity: 1)
            for i in bills.indices { bills[i] = Flyer(opacity: 1) }
        default:
            setPoses(vaultPoses())
            vaultBack = Flyer(opacity: 1)
            vaultFront = Flyer(opacity: 1)
            lock = 1
            skipOpacity = 0
            nextOpacity = 0
            cta = 1
            ctaOpacity = 0
            withAnimation(IntroSpring.fade) { ctaOpacity = 1 }
        }
    }
}
