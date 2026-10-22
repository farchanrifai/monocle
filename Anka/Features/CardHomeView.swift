import Foundation
import SwiftUI
import UIKit

/// Zero-highlight button style for card stack to prevent touch-down white flashing.
struct CardDeckButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

// Shared coordinate anchors preserve the home scroll position and the return slot.
struct CardFrames: PreferenceKey {
    static var defaultValue: [String: Anchor<CGRect>] { [:] }
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

// A single directional recognizer owns dismissal. Upward pans and pans within
// scrolled history remain UIScrollView gestures, with native momentum/bounce.
struct CardDismissPan: UIGestureRecognizerRepresentable {
    var enabled: Bool
    var changed: (CGPoint) -> Void
    var ended: (CGPoint, Bool) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }
    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.delegate = context.coordinator
        pan.maximumNumberOfTouches = 1
        pan.isEnabled = enabled
        context.coordinator.enabled = enabled
        return pan
    }
    func updateUIGestureRecognizer(_ recognizer: UIPanGestureRecognizer, context: Context) {
        context.coordinator.enabled = enabled
        recognizer.isEnabled = enabled
    }
    func handleUIGestureRecognizerAction(_ pan: UIPanGestureRecognizer, context: Context) {
        switch pan.state {
        case .began, .changed: changed(pan.translation(in: pan.view))
        case .ended: ended(pan.velocity(in: pan.view), false)
        case .cancelled, .failed: ended(.zero, true)
        default: break
        }
    }
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var enabled = false
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard enabled, let pan = gestureRecognizer as? UIPanGestureRecognizer else {
                return false
            }
            let velocity = pan.velocity(in: pan.view)
            return velocity.y > 0 && velocity.y > abs(velocity.x)
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            otherGestureRecognizer is UIPanGestureRecognizer
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }
    }
}

// MARK: - Card View Modifiers
struct CardSpringModifier: ViewModifier {
    let isSelected: Bool
    let expanded: Bool
    let reduceMotion: Bool
    let releaseVelocity: CGFloat

    func body(content: Content) -> some View {
        content
            .transaction {
                if reduceMotion {
                    $0.animation = nil
                } else if isSelected && !expanded, $0.animation != nil {
                    let frequency = 2 * Double.pi / 0.47
                    $0.animation = .interpolatingSpring(
                        mass: 1,
                        stiffness: frequency * frequency,
                        damping: 2 * 0.74 * frequency,
                        initialVelocity: releaseVelocity
                    )
                }
            }
    }
}

struct CardAccessibilityModifier: ViewModifier {
    let card: Card
    let expenseCount: Int
    let isSelected: Bool
    let expanded: Bool
    let onOpen: () -> Void

    func body(content: Content) -> some View {
        content
            .accessibilityElement(children: isSelected ? .contain : .combine)
            .accessibilityLabel(isSelected ? card.name + " selected card" : "Open \(card.name), \(expenseCount) expenses")
            .accessibilityIdentifier("stack-book-\(card.id)")
            .accessibilityAddTraits(.isButton)
            .accessibilityHidden(expanded && !isSelected)
            .accessibilityAction {
                if !expanded { onOpen() }
            }
            .onTapGesture {
                if !expanded { onOpen() }
            }
    }
}

struct CardGesturesModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let card: Card
    let index: Int
    let isSelected: Bool
    let expanded: Bool
    let detailScroll: CGFloat
    let displayedCardsCount: Int
    let onFlip: () -> Void
    let onCustomize: () -> Void
    let onMoveToFront: () -> Void
    let onDragAmountChanged: (CGFloat) -> Void
    let onDragCardIDChanged: (UUID?) -> Void
    let onDragEnded: (DragGesture.Value) -> Void
    let onSwipeOffsetChanged: (CGFloat) -> Void
    let onSwipingCardIDChanged: (UUID?) -> Void

    func body(content: Content) -> some View {
        content
            .allowsHitTesting(!expanded || isSelected)
            .gesture(
                !expanded ?
                DragGesture(minimumDistance: 7)
                    .onChanged { value in
                        guard abs(value.translation.height) > abs(value.translation.width) else { return }
                        onDragCardIDChanged(card.id)
                        let amount = value.translation.height > 0
                            ? pow(value.translation.height, 0.92) * 0.95 : value.translation.height * 0.72
                        onDragAmountChanged(amount)
                    }
                    .onEnded { value in
                        onDragEnded(value)
                    }
                : nil
            )
            .simultaneousGesture(
                (index > 0 && !expanded) ?
                DragGesture(minimumDistance: 20)
                    .onChanged { value in
                        if value.translation.width > 12 && abs(value.translation.width) > abs(value.translation.height) * 1.3 {
                            onSwipeOffsetChanged(min(70, value.translation.width))
                            onSwipingCardIDChanged(card.id)
                        }
                    }
                    .onEnded { value in
                        if value.translation.width > 45 && abs(value.translation.width) > abs(value.translation.height) * 1.3 {
                            onMoveToFront()
                        }
                        withAnimation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.75)) {
                            onSwipeOffsetChanged(0)
                            onSwipingCardIDChanged(nil)
                        }
                    }
                : nil
            )
            .contextMenu {
                if !expanded {
                    if displayedCardsCount > 1 && index > 0 {
                        Button {
                            onMoveToFront()
                        } label: {
                            Label("Bring to Front", systemImage: "arrow.up.to.line")
                        }
                    }
                    Button {
                        onFlip()
                    } label: {
                        Label("Flip", systemImage: "arrow.triangle.2.circlepath")
                    }
                    Button {
                        onCustomize()
                    } label: {
                        Label("Customize card", systemImage: "paintbrush")
                    }
                }
            }
    }
}

// MARK: - Stack Layout
struct WalletStackLayout: Layout {
    var step: CGFloat
    var cardHeight: CGFloat
    var activeIndex: Int
    var displacement: CGFloat
    var animatableData: CGFloat {
        get { displacement }
        set { displacement = newValue }
    }

    static func fanningOffset(for index: Int, totalCount: Int, activeIndex: Int, displacement: CGFloat) -> CGFloat {
        guard displacement != 0, totalCount > 1 else { return 0 }
        
        if displacement > 0 {
            // Dragging / pulling DOWN -> Fan open (accordion expansion)
            if activeIndex < 0 {
                // General stack pull or overscroll pull:
                // Every card below expands progressively
                let stepExpansion = displacement * 0.28
                return CGFloat(index) * stepExpansion + (index == 0 ? displacement * 0.12 : 0)
            } else if index <= activeIndex {
                // Cards at or above the active card:
                // Fan out smoothly from near top (index 0) to activeIndex
                let k = CGFloat(activeIndex)
                let i = CGFloat(index)
                // Elastic factor so even index 0 has a subtle give (15%)
                let progress = (i + 0.15) / (k + 0.15)
                return displacement * progress
            } else {
                // Cards below the active card:
                // Move with active card plus additional cascading fanning
                let stepsBelow = CGFloat(index - activeIndex)
                let cascade = displacement * 0.15 * stepsBelow
                return displacement + cascade
            }
        } else {
            // Swiping / pushing UP -> Elastic compression / lifting
            if activeIndex < 0 {
                let compression = displacement * 0.20
                return CGFloat(index) * compression
            } else if index <= activeIndex {
                let k = max(1, CGFloat(activeIndex))
                let i = CGFloat(index)
                let progress = (i + 0.10) / (k + 0.10)
                return displacement * progress
            } else {
                let stepsBelow = CGFloat(index - activeIndex)
                let follow = max(0.25, 1.0 - stepsBelow * 0.22)
                return displacement * follow
            }
        }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxExtra: CGFloat
        if displacement > 0 && subviews.count > 0 {
            maxExtra = WalletStackLayout.fanningOffset(for: subviews.count - 1, totalCount: subviews.count, activeIndex: activeIndex, displacement: displacement)
        } else {
            maxExtra = 0
        }
        return CGSize(width: proposal.width ?? 362, height: cardHeight + CGFloat(max(0, subviews.count - 1)) * step + max(0, maxExtra))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (index, subview) in subviews.enumerated() {
            let offset = WalletStackLayout.fanningOffset(for: index, totalCount: subviews.count, activeIndex: activeIndex, displacement: displacement)
            subview.place(at: CGPoint(x: bounds.minX, y: bounds.minY + CGFloat(index) * step + offset), anchor: .topLeading, proposal: ProposedViewSize(width: bounds.width, height: cardHeight))
        }
    }
}

/// Main home screen presenting an Apple Wallet-style stacked card deck with durable multi-card persistence.
struct CardHomeView: View {
    @Bindable var model: AppModel
    var showsBottomBar: Bool = false

    private let settle = Animation.spring(response: 0.47, dampingFraction: 0.74)
    // Fitted to the supplied 60 fps recording, not a generic sheet spring.
    private let opening = Animation.spring(response: 0.48, dampingFraction: 0.66)

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @AccessibilityFocusState private var headingFocused: Bool

    @State private var expanded = false
    @State private var selectedID: UUID?
    @State private var managing = false
    @State private var showingBills = false
    @State private var draggedCardID: UUID?
    @State private var dragAmount: CGFloat = 0
    @State private var dismissAmount: CGFloat = 0
    @State private var dismissX: CGFloat = 0
    @State private var returnDistance: CGFloat = 0
    @State private var releaseVelocity: Double = 0
    @State private var detailScroll: CGFloat = 0
    @State private var scrollOverscroll: CGFloat = 0

    @State private var displayedCards: [Card] = []
    @State private var displayedFilterScope: StackFilterScope? = nil
    @State private var displayedStackID: UUID? = nil
    @State private var currentStackKey: String = ""
    @State private var targetStackKey: String = ""
    @State private var flippedCardID: UUID? = nil
    @State private var swipingCardID: UUID? = nil
    @State private var swipeOffset: CGFloat = 0.0
    @State private var selectedExpenseForDetail: Expense? = nil

    private var stackKey: String {
        "\(model.filterScope.rawValue)-\(model.activeStackID?.uuidString ?? "all")"
    }

    private var visible: [Card] { model.visibleCards }
    private var current: Card? { model.cards.first { $0.id == selectedID } }

    private var direction: CardVisualDirection { model.effectiveDirection(for: colorScheme) }
    private var paper: Color {
        switch direction {
        case .light:
            return MC.paper
        case .ledger:
            return Color(red: 0.96, green: 0.94, blue: 0.88)
        case .instrument, .signal:
            return .black
        }
    }
    private var ink: Color {
        switch direction {
        case .light, .ledger:
            return MC.ink
        case .instrument, .signal:
            return .white
        }
    }
    private var amountFont: Font {
        switch direction {
        case .light, .signal:
            return .system(size: 22, weight: .bold)
        case .ledger:
            return .system(size: 22, weight: .semibold, design: .serif)
        case .instrument:
            return .system(size: 22, weight: .bold, design: .monospaced)
        }
    }

    private func progressiveBlurHeaderBackground(safeAreaTop: CGFloat) -> some View {
        let toolbarHeight: CGFloat = 52
        // Shorten the full fade from 88 pt to 66 pt (25%), ending closer to the toolbar.
        let featherHeight: CGFloat = 22
        let totalHeight = safeAreaTop + toolbarHeight + featherHeight
        let fadeStart = safeAreaTop + 8
        let fadeLength = totalHeight - fadeStart

        // A smoothstep has zero slope at both ends: no hard shoulder beneath
        // the toolbar and no visible cutoff at the bottom of the material.
        let stops: [Gradient.Stop] = [.init(color: .black, location: 0)] + (0...16).map { step in
            let t = CGFloat(step) / 16
            let opacity = 1 - t * t * (3 - 2 * t)
            return .init(color: .black.opacity(Double(opacity)),
                         location: (fadeStart + fadeLength * t) / totalHeight)
        }
        let scrollFraction = min(max((detailScroll - 5) / 64, 0), 1)
        let scrollOpacity = scrollFraction * scrollFraction * (3 - 2 * scrollFraction)

        return Rectangle()
            .fill(.ultraThinMaterial)
            .overlay(paper.opacity(0.52))
            // Composite first, then fade once so tint and material share an edge.
            .mask {
                LinearGradient(stops: stops, startPoint: .top, endPoint: .bottom)
            }
            .frame(height: totalHeight)
            .opacity(expanded ? scrollOpacity : 1)
            .ignoresSafeArea(edges: .top)
            // Animate screen changes only; scroll updates stay attached to the finger.
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: expanded)
            .allowsHitTesting(false)
    }

    private func topBar(safeAreaTop: CGFloat) -> some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: safeAreaTop)
            header
        }
        .background(alignment: .top) {
            progressiveBlurHeaderBackground(safeAreaTop: safeAreaTop)
        }
        .ignoresSafeArea(edges: .top)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                paper.ignoresSafeArea()

                home(width: geometry.size.width, height: geometry.size.height)
                    .allowsHitTesting(selectedID == nil)
                    .accessibilityHidden(selectedID != nil)

                if let current {
                    detail(current, width: geometry.size.width)
                        .transition(.identity)
                }
            }
            .overlayPreferenceValue(CardFrames.self) { frames in
                GeometryReader { proxy in
                    cardPlane(frames: frames, geometry: proxy)
                }
            }
            .overlay(alignment: .top) {
                topBar(safeAreaTop: geometry.safeAreaInsets.top)
                    .zIndex(1000)
            }
            .gesture(CardDismissPan(enabled: selectedID != nil && expanded && detailScroll <= 1,
                                    changed: updateDismiss, ended: endDismiss))

        }
        .safeAreaInset(edge: .bottom) {
            if showsBottomBar {
                Button {
                    let targetID = selectedID ?? displayedCards.first?.id ?? model.activeCardID
                    model.openEntry(for: targetID)
                } label: {
                    Label("Add Expense", systemImage: "plus")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(18)
                        .background(ink, in: Capsule())
                        .foregroundStyle(paper)
                }
                .buttonStyle(PressFeedbackStyle())
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
                .accessibilityIdentifier("addExpenseButton")
            }
        }
        .sheet(isPresented: $managing) {
            manageStackSheet
        }
        .sheet(isPresented: $model.showStackCustomizer) {
            StackCustomizerView(model: model, initialMode: model.stackCustomizerMode) {
                model.showStackCustomizer = false
            }
        }
        .sheet(item: $model.customizerTarget) { target in
            switch target {
            case .existing(let card):
                CardCustomizerView(
                    model: model,
                    initialCard: card,
                    cards: visible.isEmpty ? model.unhiddenCards : visible,
                    isCreatingNewCard: false
                ) {
                    model.customizerTarget = nil
                }
            case .newCard:
                CardCustomizerView(
                    model: model,
                    initialCard: visible.first ?? model.unhiddenCards.first,
                    cards: visible.isEmpty ? model.unhiddenCards : visible,
                    isCreatingNewCard: true
                ) {
                    model.customizerTarget = nil
                }
            }
        }
        // Pushed on the root stack, so the system back button and the edge swipe work.
        .navigationDestination(isPresented: $showingBills) {
            BillsView(model: model).hidesBottomNavigation(model)
        }
        .sheet(isPresented: $model.showCSVInterchange) {
            NavigationStack {
                CSVInterchangeView(model: model, initialTab: model.csvInterchangeInitialTab)
            }
        }
        .navigationDestination(isPresented: $model.showAnalytics) {
            AnalyticsView(model: model, showsDismissButton: false, isPushed: true).hidesBottomNavigation(model)
        }
        .sheet(isPresented: $model.showStartSessionSheet) {
            startSessionSheet
        }
        .navigationDestination(item: $selectedExpenseForDetail) { expense in
            TransactionDetailView(
                initialExpense: expense,
                model: model,
                onDismiss: { selectedExpenseForDetail = nil }
            )
            .hidesBottomNavigation(model)
        }
        .onAppear {
            if displayedCards.isEmpty {
                displayedCards = model.visibleCards
            }
            if displayedFilterScope == nil {
                displayedFilterScope = model.filterScope
            }
            if displayedStackID == nil {
                displayedStackID = model.activeStackID
            }
            if currentStackKey.isEmpty {
                currentStackKey = stackKey
            }
            if targetStackKey.isEmpty {
                targetStackKey = stackKey
            }
            if let active = model.selectedCardID, displayedCards.contains(where: { $0.id == active }) {
                selectedID = active
                expanded = true
            }
        }
        .onChange(of: stackKey) { _, newKey in
            if targetStackKey != newKey {
                performStackTransition(to: newKey)
            }
        }
        .onChange(of: model.visibleCards) { _, newVisible in
            withAnimation(settle) {
                displayedCards = newVisible
            }
            if let target = model.selectedCardID, let card = newVisible.first(where: { $0.id == target }), !expanded {
                openCard(card)
            }
        }
        .onChange(of: model.selectedCardID) { _, newID in
            if let newID, let card = displayedCards.first(where: { $0.id == newID }) {
                if selectedID != newID || !expanded {
                    openCard(card)
                }
            } else if newID == nil && expanded {
                closeCard()
            }
        }
    }

    private var header: some View {
        HStack {
            Button {
                if expanded {
                    closeCard()
                }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("anka").font(.system(size: 24, weight: .semibold, design: .rounded)).tracking(-1.0)
                        .foregroundStyle(ink)
                    Text(".").font(.system(size: 26, weight: .bold)).foregroundStyle(MC.red)
                }
            }
            .buttonStyle(.plain)
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("anka")
            .accessibilityIdentifier("homeLogo")

            Spacer()
            optionsMenu
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
        .frame(height: 52)
    }

    private func home(width: CGFloat, height: CGFloat) -> some View {
        let cardWidth = width - 40
        let cardHeight = cardWidth * 0.63
        let step = cardWidth * 0.152
        let restingHeight = CGFloat(max(0, displayedCards.count - 1)) * step + cardHeight

        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if model.sessionManager.isSessionActive {
                    activeSessionPill
                }

                stackView(width: cardWidth, height: cardHeight, step: step)
                    .frame(height: restingHeight + stackExpansion(displayedCards), alignment: .top)

                if displayedCards.isEmpty {
                    ContentUnavailableView {
                        Label("Your stack is empty", systemImage: "rectangle.stack")
                    } description: {
                        Text("Add cards to this stack or switch stacks with the filter button at the top.")
                    } actions: {
                        Button("Manage Stacks & Cards") {
                            model.stackCustomizerMode = .manage
                            model.showStackCustomizer = true
                        }
                    }
                    .offset(y: expanded && !reduceMotion ? height : 0)
                    .opacity(expanded ? 0.0 : 1.0)
                    .blur(radius: expanded && !reduceMotion ? 10 : 0)
                }

                activitySection(cardID: nil)
                    .padding(.bottom, 96)
                    .offset(y: expanded && !reduceMotion ? height : 0)
                    .opacity(expanded ? 0.0 : 1.0)
                    .blur(radius: expanded && !reduceMotion ? 10 : 0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 68)
        }
        .scrollClipDisabled()
        .scrollIndicators(.hidden)
        .onScrollGeometryChange(for: CGFloat.self) { geo in
            geo.contentOffset.y + geo.contentInsets.top
        } action: { _, value in
            if value < 0 {
                scrollOverscroll = -value
            } else if scrollOverscroll > 0 {
                scrollOverscroll = 0
            }
        }
    }

    private func stackExpansion(_ group: [Card]) -> CGFloat {
        let isDraggedGroup = group.contains(where: { $0.id == draggedCardID })
        guard isDraggedGroup || (draggedCardID == nil && scrollOverscroll > 0) else { return 0 }
        let disp = isDraggedGroup ? dragAmount : (pow(scrollOverscroll, 0.88) * 0.45)
        let activeIdx = isDraggedGroup ? (group.firstIndex(where: { $0.id == draggedCardID }) ?? 0) : -1
        return max(0, WalletStackLayout.fanningOffset(for: group.count - 1, totalCount: group.count, activeIndex: activeIdx, displacement: disp))
    }

    private func stackView(width: CGFloat, height: CGFloat, step: CGFloat) -> some View {
        let isDragged = displayedCards.contains(where: { $0.id == draggedCardID })
        let activeIdx = isDragged ? (displayedCards.firstIndex(where: { $0.id == draggedCardID }) ?? displayedCards.count) : (draggedCardID == nil && scrollOverscroll > 0 ? -1 : displayedCards.count)
        let effectiveDisp = isDragged ? dragAmount : ((draggedCardID == nil && scrollOverscroll > 0) ? (pow(scrollOverscroll, 0.88) * 0.45) : 0)

        return WalletStackLayout(step: step, cardHeight: height, activeIndex: activeIdx, displacement: effectiveDisp) {
            ForEach(displayedCards) { card in
                Color.clear.frame(width: width, height: height)
                    .anchorPreference(key: CardFrames.self, value: .bounds) { [card.id.uuidString: $0] }
            }
        }
    }

    private func detail(_ card: Card, width: CGFloat) -> some View {
        let heroWidth = width - 32
        let heroHeight = heroWidth * 0.63
        let progress = min(max(dismissAmount / 280, 0), 1)

        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Color.clear
                    .frame(width: heroWidth, height: heroHeight)
                    .anchorPreference(key: CardFrames.self, value: .bounds) { ["detail": $0] }
                    .allowsHitTesting(false)

                activitySection(cardID: card.id)
                    .padding(.top, 16)
                    .padding(.bottom, 130)
                    .opacity(expanded ? 1 - progress : 0)
                    .blur(radius: reduceMotion ? 0 : (expanded ? progress * 12 : 12))
                    .offset(y: reduceMotion ? 0 : (expanded ? dismissAmount : 80))
                    .allowsHitTesting(expanded && dismissAmount == 0)
            }
            .padding(.horizontal, 16)
            .padding(.top, 64)
        }
        .scrollIndicators(.hidden)
        .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + $0.contentInsets.top } action: { _, value in
            detailScroll = value
        }
        .accessibilityHidden(!expanded)
    }

    // One persistent artwork view per card. Both screens supply its coordinate anchor.
    // Dismissal smoothly follows finger travel and returns with release velocity.
    private func cardPlane(frames: [String: Anchor<CGRect>], geometry: GeometryProxy) -> some View {
        ForEach(Array(displayedCards.enumerated()), id: \.element.id) { index, card in
            if let anchor = frames[card.id.uuidString] {
                let homeFrame = geometry[anchor]
                let isSelected = selectedID == card.id
                let selectedIndex = displayedCards.firstIndex { $0.id == selectedID } ?? displayedCards.count
                let below = index > selectedIndex
                let detailFrame = frames["detail"].map { geometry[$0] } ?? homeFrame
                let target = isSelected && expanded ? detailFrame : homeFrame

                cardPlaneItem(
                    index: index,
                    card: card,
                    target: target,
                    homeFrame: homeFrame,
                    detailFrame: detailFrame,
                    isSelected: isSelected,
                    below: below,
                    selectedIndex: selectedIndex,
                    geometryHeight: geometry.size.height
                )
            }
        }
    }

    @ViewBuilder
    private func cardPlaneItem(
        index: Int,
        card: Card,
        target: CGRect,
        homeFrame: CGRect,
        detailFrame: CGRect,
        isSelected: Bool,
        below: Bool,
        selectedIndex: Int,
        geometryHeight: CGFloat
    ) -> some View {
        let otherOffset: CGFloat = expanded && !isSelected && below && !reduceMotion
            ? geometryHeight - homeFrame.minY + CGFloat(index - selectedIndex) * 54 : 0
        let horizontalOffset: CGFloat = (swipingCardID == card.id) ? swipeOffset : 0

        let posX = target.midX + horizontalOffset + (isSelected && expanded && !reduceMotion ? dismissX : 0)
        let posY = target.midY + otherOffset + (isSelected && expanded && !reduceMotion ? dismissAmount : 0)

        cardInteractiveView(card: card, index: index, target: target, isSelected: isSelected)
            .shadow(
                color: isSelected && expanded
                    ? Color.black.opacity(colorScheme == .dark ? 0.38 : 0.16)
                    : Color.black.opacity(0.04),
                radius: isSelected && expanded ? 14 : 3,
                x: 0,
                y: isSelected && expanded ? 8 : 2
            )
            .blur(radius: expanded && !isSelected && !reduceMotion ? 12 : 0)
            .opacity(expanded && !isSelected ? 0 : 1)
            .position(x: posX, y: posY)
            .modifier(CardSpringModifier(
                isSelected: isSelected,
                expanded: expanded,
                reduceMotion: reduceMotion,
                releaseVelocity: releaseVelocity
            ))
            .onChange(of: homeFrame.midY - detailFrame.midY, initial: true) { _, distance in
                if isSelected {
                    returnDistance = distance
                }
            }
            .zIndex(Double(index))
    }

    @ViewBuilder
    private func cardInteractiveView(
        card: Card,
        index: Int,
        target: CGRect,
        isSelected: Bool
    ) -> some View {
        CardPresentationView(
            card: card,
            index: index,
            isCurrent: isSelected,
            isFlipped: flippedCardID == card.id,
            expanded: expanded,
            dismissAmount: dismissAmount,
            scrollOverscroll: scrollOverscroll,
            amountFont: amountFont,
            model: model,
            onFlip: { toggleFlip(for: card.id) },
            onOpenAnalytics: { model.showAnalytics = true },
            onCustomize: { openCustomizer(for: card) }
        )
        .frame(width: target.width, height: target.height)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .modifier(CardAccessibilityModifier(
                card: card,
                expenseCount: model.expenses(for: card.id).count,
                isSelected: isSelected,
                expanded: expanded,
                onOpen: { openCard(card) }
            ))
            .modifier(CardGesturesModifier(
                card: card,
                index: index,
                isSelected: isSelected,
                expanded: expanded,
                detailScroll: detailScroll,
                displayedCardsCount: displayedCards.count,
                onFlip: {
                    if selectedID != card.id { openCard(card) }
                    toggleFlip(for: card.id)
                },
                onCustomize: { openCustomizer(for: card) },
                onMoveToFront: {
                    let generator = UIImpactFeedbackGenerator(style: .medium)
                    generator.impactOccurred()
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                        model.moveCardToFront(card.id)
                    }
                },
                onDragAmountChanged: { val in dragAmount = val },
                onDragCardIDChanged: { id in draggedCardID = id },
                onDragEnded: { val in
                    if abs(val.translation.height) > abs(val.translation.width) &&
                        (val.translation.height < -55 || val.predictedEndTranslation.height < -110) {
                        openCard(card)
                    }
                    withAnimation(reduceMotion ? nil : settle, completionCriteria: .removed) {
                        dragAmount = 0
                    } completion: {
                        if dragAmount == 0 { draggedCardID = nil }
                    }
                },
                onSwipeOffsetChanged: { offset in swipeOffset = offset },
                onSwipingCardIDChanged: { id in swipingCardID = id }
            ))
    }

    private func updateDismiss(_ translation: CGPoint) {
        withAnimation(nil) {
            dismissAmount = max(0, translation.y)
            dismissX = translation.x * 0.12
        }
    }

    private func endDismiss(_ velocity: CGPoint, _ cancelled: Bool) {
        if !cancelled && dismissAmount > 10 && velocity.y > -120 &&
            (dismissAmount > 96 || dismissAmount + velocity.y * 0.18 > 150) {
            closeCard(velocity: velocity.y)
        } else {
            withAnimation(reduceMotion ? .easeOut(duration: 0.15) : settle) {
                dismissAmount = 0
                dismissX = 0
            }
        }
    }

    private func openCard(_ card: Card) {
        let haptic = UIImpactFeedbackGenerator(style: .medium)
        haptic.impactOccurred()
        dismissAmount = 0
        dismissX = 0
        detailScroll = 0
        releaseVelocity = 0
        guard model.selectCard(card.id) else { return }
        selectedID = card.id
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : opening) {
            expanded = true
        }
    }

    private func closeCard(velocity: CGFloat = 0) {
        guard selectedID != nil, expanded else { return }
        let haptic = UIImpactFeedbackGenerator(style: .light)
        haptic.impactOccurred()
        let travel = returnDistance - dismissAmount
        releaseVelocity = abs(travel) > 1 ? Double(min(max(velocity / travel, -8), 8)) : 0
        let closingID = selectedID
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : settle, completionCriteria: .removed) {
            expanded = false
            model.selectedCardID = nil
        } completion: {
            guard !expanded, selectedID == closingID else { return }
            selectedID = nil
            dismissAmount = 0
            dismissX = 0
            detailScroll = 0
            flippedCardID = nil
            releaseVelocity = 0
        }
    }

    private func performStackTransition(to targetKey: String) {
        targetStackKey = targetKey

        if reduceMotion {
            withAnimation(.easeInOut(duration: 0.14)) {
                displayedCards = model.visibleCards
                displayedFilterScope = model.filterScope
                displayedStackID = model.activeStackID
                currentStackKey = targetKey
            }
            return
        }

        withAnimation(settle) {
            displayedCards = model.visibleCards
            displayedFilterScope = model.filterScope
            displayedStackID = model.activeStackID
            currentStackKey = targetKey
        }
    }

// MARK: - Isolated 3D Card Presentation
struct CardPresentationView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let card: Card
    let index: Int
    let isCurrent: Bool
    let isFlipped: Bool
    let expanded: Bool
    let dismissAmount: CGFloat
    let scrollOverscroll: CGFloat
    let amountFont: Font
    let model: AppModel
    let onFlip: () -> Void
    let onOpenAnalytics: () -> Void
    let onCustomize: () -> Void

    @State private var dragTilt: CGSize = .zero

    private var effectiveTilt: (angle: Double, axisX: Double, axisY: Double, shiftX: CGFloat, shiftY: CGFloat) {
        guard isCurrent, expanded, !reduceMotion else {
            let shiftX = scrollOverscroll * 0.002
            let shiftY = scrollOverscroll * 0.003
            return (0, 1, 0, shiftX, shiftY)
        }

        let dismissDamp = max(0, 1.0 - Double(dismissAmount) / 70.0)
        guard dismissDamp > 0 else {
            return (0, 1, 0, 0, 0)
        }

        let maxAngle: Double = 12.0
        let tiltX = -maxAngle * tanh(Double(dragTilt.height) / 140.0) * dismissDamp
        let tiltY = maxAngle * tanh(Double(dragTilt.width) / 140.0) * dismissDamp

        let angle = sqrt(tiltX * tiltX + tiltY * tiltY)
        let axisX = angle > 0.001 ? (tiltX / angle) : 1.0
        let axisY = angle > 0.001 ? (tiltY / angle) : 0.0

        let shiftX = CGFloat((tiltY / maxAngle) * 0.32)
        let shiftY = CGFloat((-tiltX / maxAngle) * 0.32)

        return (angle, axisX, axisY, shiftX, shiftY)
    }

    var body: some View {
        let tilt = effectiveTilt

        ZStack {
            cardFrontView(tiltShiftX: tilt.shiftX, tiltShiftY: tilt.shiftY)
                .rotation3DEffect(
                    .degrees(isFlipped ? 180 : 0),
                    axis: (x: 0, y: 1, z: 0),
                    perspective: 0.7
                )
                .opacity(isFlipped ? 0 : 1)
                .accessibilityHidden(isFlipped)

            if isCurrent {
                CardBackTelemetryView(
                    model: model,
                    card: card,
                    index: index,
                    onFlipBack: onFlip,
                    onOpenAnalytics: onOpenAnalytics,
                    onCustomize: onCustomize
                )
                .rotation3DEffect(
                    .degrees(isFlipped ? 0 : -180),
                    axis: (x: 0, y: 1, z: 0),
                    perspective: 0.7
                )
                .opacity(isFlipped ? 1 : 0)
                .accessibilityHidden(!isFlipped)
            }
        }
        .rotation3DEffect(
            .degrees(tilt.angle),
            axis: (x: tilt.axisX, y: tilt.axisY, z: 0),
            perspective: 0.8
        )
        .simultaneousGesture(
            (isCurrent && expanded && !reduceMotion) ?
                DragGesture(minimumDistance: 3)
                    .onChanged { value in
                        dragTilt = value.translation
                    }
                    .onEnded { _ in
                        withAnimation(.spring(response: 0.38, dampingFraction: 0.74)) {
                            dragTilt = .zero
                        }
                    }
                : nil
        )
        .animation(.interactiveSpring(response: 0.22, dampingFraction: 0.85, blendDuration: 0.08), value: dragTilt)
        .onChange(of: expanded) { _, isExpanded in
            if !isExpanded {
                dragTilt = .zero
            }
        }
    }

    private func cardFrontView(tiltShiftX: CGFloat, tiltShiftY: CGFloat) -> some View {
        let cardExpenses = model.expenses(for: card.id)
        let total = model.spent(for: card.id)
        let customization = model.customization(for: card.id)
        let textStyle = CardPalette.resolvedTextColor(for: customization)

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Text(card.name)
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 8)

                HStack(spacing: 6) {
                    if isCurrent && expanded {
                        Button {
                            onFlip()
                        } label: {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(textStyle)
                                .padding(5)
                                .background(textStyle.opacity(0.12), in: Circle())
                        }
                        .buttonStyle(CardDeckButtonStyle())
                        .accessibilityLabel("Flip card")
                        .accessibilityIdentifier("cardFlipButton")
                    }

                    Text(String(format: "%02d", index + 1))
                        .font(.caption.monospaced())
                        .foregroundStyle(textStyle.opacity(0.8))
                }
            }
            .frame(minHeight: 28, alignment: .top)

            Spacer(minLength: 0)

            Text(Money.format(total, code: model.currency(of: card)))
                .font(amountFont)
                .monospacedDigit()
                .minimumScaleFactor(0.65)
            if let other = model.secondaryCurrency(of: card),
               let approx = model.approximate(total, from: model.currency(of: card), to: other) {
                Text("≈ \(Money.format(approx, code: other))")
                    .font(.caption.monospacedDigit())
                    .opacity(0.8)
            }
            Text("\(cardExpenses.count) EXPENSES")
                .font(.system(size: 11, weight: .medium).monospaced())
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .foregroundStyle(textStyle)
        .background(
            ZStack {
                cardBackground(for: customization, card: card)
                specularSheen(shiftX: tiltShiftX, shiftY: tiltShiftY)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.black.opacity(0.12), lineWidth: 0.5))
    }

    @ViewBuilder
    private func specularSheen(shiftX: CGFloat, shiftY: CGFloat) -> some View {
        if !reduceMotion {
            LinearGradient(
                colors: [
                    Color.white.opacity(0.24),
                    Color.white.opacity(0.06),
                    Color.clear
                ],
                startPoint: UnitPoint(x: max(0, min(1, 0.2 + shiftX)), y: max(0, min(1, 0.1 + shiftY))),
                endPoint: UnitPoint(x: max(0, min(1, 0.8 + shiftX)), y: max(0, min(1, 0.9 + shiftY)))
            )
            .blendMode(.screen)
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func cardBackground(for customization: CardCustomization, card: Card) -> some View {
        switch customization.style {
        case .palette(let index):
            CardPalette.color(for: index)
        case .customColor(let hex):
            CardPalette.color(fromHex: hex)
        case .stock(let design):
            StockDesignBackgroundView(design: design)
        case .customPhoto(let filename):
            if let image = CardArtworkStore.shared.loadArtwork(filename: filename) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                CardPalette.color(for: card.colorIndex)
            }
        }
    }
}

    private func activitySection(cardID: UUID?) -> some View {
        let activeScope = displayedFilterScope ?? model.filterScope
        let isAllCards = activeScope == .allCards
        let activeStack = model.stacks.first { $0.id == (displayedStackID ?? model.activeStackID) } ?? model.currentStack
        let activities = model.activities(selectedCardID: cardID, allCards: isAllCards)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                Text(cardID != nil ? "Latest Expenses" : (isAllCards ? "All Expenses" : "Recent Expenses"))
                    .font(.system(size: 15, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused($headingFocused)

                Spacer()

                if cardID == nil {
                    Menu {
                        filterMenuContent
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: isAllCards ? "rectangle.stack" : (activeStack?.icon ?? "square.stack.3d.up.fill"))
                                .font(.system(size: 10, weight: .bold))
                            Text(isAllCards ? "All cards · \(model.unhiddenCards.count)" : "\(activeStack?.name ?? "Stack") · \(activeStack?.cardIDs.count ?? 0)")
                                .font(.system(size: 11, weight: .semibold))
                                .accessibilityIdentifier("activityScopeBadge")
                            Image(systemName: "chevron.down")
                                .font(.system(size: 8, weight: .bold))
                        }
                        .foregroundStyle(isAllCards ? Color.secondary : MC.red)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(isAllCards ? Color.primary.opacity(0.06) : MC.red.opacity(0.12))
                        )
                        .contentShape(Capsule())
                    }
                    .accessibilityLabel(isAllCards ? "All cards" : "Stack: \(activeStack?.name ?? "Stack")")
                    .accessibilityHint("Choose a stack or all cards")
                    .accessibilityIdentifier("activityFilterButton")
                }
            }

            if activities.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: cardID != nil ? "tray" : "text.book.closed")
                        .font(.system(size: 26))
                        .foregroundStyle(ink.opacity(0.35))
                    Text(cardID != nil ? "No Expenses Yet" : "Nothing Added Yet")
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(ink)
                    Text(cardID != nil ? "Expenses you add to this card appear here." : "Tap the add button below to add your first expense.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(ink.opacity(0.6))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
                .padding(.horizontal, 20)
                .background(MC.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            } else {
                List {
                    ForEach(activities) { row in
                        activityRow(row, showCardLabel: cardID == nil, isPlatter: true)
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                            .listRowBackground(MC.surface)
                    }
                }
                .listStyle(.plain)
                .scrollDisabled(true)
                .scrollContentBackground(.hidden)
                .environment(\.defaultMinListRowHeight, activityRowHeight)
                .environment(\.defaultMinListHeaderHeight, 0)
                .listSectionSpacing(.custom(0))
                .frame(height: CGFloat(activities.count) * activityRowHeight)
                .background(MC.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
        }
    }

    private let activityRowHeight: CGFloat = 56

    private func activityRow(_ expense: Expense, showCardLabel: Bool, isPlatter: Bool = false) -> some View {
        Button {
            selectedExpenseForDetail = expense
        } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2.5) {
                    Text(model.title(expense))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(ink)
                        .lineLimit(1)
                    Text(showCardLabel && expense.cardID != nil ? "\(expense.day) · \(model.cards.first(where: { $0.id == expense.cardID })?.name ?? "")" : expense.day)
                        .font(.system(size: 11.5, weight: .regular))
                        .foregroundStyle(ink.opacity(0.55))
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 1) {
                    Text(expense.paidText)
                        .font(.system(size: 13.5, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(ink)
                    if let note = expense.reportingNote {
                        Text(note).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, isPlatter ? 16 : 0)
            .frame(height: isPlatter ? activityRowHeight : 46)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                model.edit(expense)
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .tint(Color.blue)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                model.delete(expense)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(showCardLabel && expense.cardID != nil
            ? "\(model.title(expense)), \(expense.day) · \(model.cards.first(where: { $0.id == expense.cardID })?.name ?? ""), \(Money.format(expense.amount))"
            : "\(model.title(expense)), \(expense.day), \(Money.format(expense.amount))")
        .accessibilityIdentifier("expense-\(expense.note)")
        .contextMenu {
            Button("Edit", systemImage: "pencil") {
                model.edit(expense)
            }
            Button("Repeat", systemImage: "repeat") {
                model.repeatExpense(expense)
            }
            Button("Delete", systemImage: "trash", role: .destructive) {
                model.delete(expense)
            }
        }
    }

    @ViewBuilder private var filterMenuContent: some View {
        Section("Stacks") {
            ForEach(model.stacks) { stack in
                Button {
                    model.setActiveStack(id: stack.id)
                } label: {
                    HStack {
                        Label(stack.name, systemImage: stack.icon)
                        if model.activeStackID == stack.id && model.filterScope == .activeStack {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        }
        Section {
            Button {
                model.filterScope = .allCards
            } label: {
                HStack {
                    Label("All Active Cards", systemImage: "rectangle.stack")
                    if model.filterScope == .allCards {
                        Image(systemName: "checkmark")
                    }
                }
            }
        }
        Section {
            Button {
                model.stackCustomizerMode = .create
                model.showStackCustomizer = true
            } label: {
                Label("New Stack…", systemImage: "plus")
            }
            Button {
                model.stackCustomizerMode = .manage
                model.showStackCustomizer = true
            } label: {
                Label("Manage Stacks & Cards…", systemImage: "slider.horizontal.3")
            }
        }
    }

    private var optionsMenu: some View {
        Menu {
            // Cards & Stacks
            Menu {
                Button {
                    openCustomizerForNewCard()
                } label: {
                    Label("New Card", systemImage: "plus.rectangle.on.rectangle")
                }
                .accessibilityIdentifier("menuNewBook")

                if let targetCard = current ?? visible.first ?? model.cards.first {
                    Button {
                        openCustomizer(for: targetCard)
                    } label: {
                        Label("Customize Card", systemImage: "paintbrush")
                    }
                    .accessibilityIdentifier("menuCustomizeCard")
                }

                Button {
                    model.stackCustomizerMode = .manage
                    model.showStackCustomizer = true
                } label: {
                    Label("Stacks & Card Visibility", systemImage: "square.stack.3d.up")
                }
                .accessibilityIdentifier("menuManageStacks")
            } label: {
                Label("Cards & Stacks", systemImage: "square.stack.3d.up")
            }

            // Tools & Insights
            Menu {
                Button {
                    showingBills = true
                } label: {
                    Label("Recurring Bills", systemImage: "calendar")
                }
                .accessibilityIdentifier("menuBills")

                Button {
                    if model.sessionManager.isSessionActive {
                        model.sessionManager.endSession()
                    } else {
                        model.showStartSessionSheet = true
                    }
                } label: {
                    Label(
                        model.sessionManager.isSessionActive ? "End Spending Session" : "Start Spending Session",
                        systemImage: model.sessionManager.isSessionActive ? "stop.circle" : "record.circle"
                    )
                }
                .accessibilityIdentifier("menuSpendingSession")
            } label: {
                Label("Tools & Insights", systemImage: "chart.bar.xaxis")
            }

            // Data & Backup
            Menu {
                Button {
                    model.csvInterchangeInitialTab = 0
                    model.showCSVInterchange = true
                } label: {
                    Label("Export CSV", systemImage: "square.and.arrow.up")
                }
                .accessibilityIdentifier("menuExportCSV")

                Button {
                    model.csvInterchangeInitialTab = 1
                    model.showCSVInterchange = true
                } label: {
                    Label("Import CSV", systemImage: "square.and.arrow.down")
                }
                .accessibilityIdentifier("menuImportCSV")
            } label: {
                Label("Data & Backup", systemImage: "tablecells")
            }
            .accessibilityIdentifier("menuCSVData")

            Divider()

            // Settings
            Button {
                model.showSettings = true
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
            .accessibilityIdentifier("homeSettings")
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(ink)
                .frame(width: 38, height: 38)
                .contentShape(Circle())
        }
        .buttonStyle(PressFeedbackStyle())
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel("Options")
        .accessibilityIdentifier("bookOptionsMenu")
    }

    private func toggleFlip(for cardID: UUID) {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.42, dampingFraction: 0.80)) {
            if flippedCardID == cardID {
                flippedCardID = nil
            } else {
                flippedCardID = cardID
            }
        }
    }

    private func openCustomizer(for card: Card) {
        model.customizerTarget = .existing(card)
    }

    private func openCustomizerForNewCard() {
        model.customizerTarget = .newCard
    }

    private var manageStackSheet: some View {
        NavigationStack {
            List {
                Section("Visible cards · drag to reorder") {
                    ForEach(model.orderedCards) { card in
                        Toggle(card.name, isOn: Binding(
                            get: { !model.hiddenCardIDs.contains(card.id) },
                            set: { isVisible in
                                model.setCardHidden(id: card.id, isHidden: !isVisible)
                            }
                        ))
                    }
                    .onMove { from, to in
                        model.reorderCards(fromOffsets: from, toOffset: to)
                    }
                }

                Section {
                    Button("Show every card") {
                        model.hiddenCardIDs = []
                        model.persistWorkspacePreferences()
                    }
                    Button("Create new card") {
                        managing = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            openCustomizerForNewCard()
                        }
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Manage stack")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { managing = false }
                }
            }
        }
    }

    @ViewBuilder
    private var activeSessionPill: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(MC.red)
                .frame(width: 8, height: 8)
                .overlay(
                    Circle()
                        .stroke(MC.red.opacity(0.4), lineWidth: 3)
                        .scaleEffect(1.4)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(model.sessionManager.sessionName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(Money.format(model.sessionManager.sessionSpent))
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .foregroundStyle(MC.red)
            }

            Spacer()

            if let startTime = model.sessionManager.sessionStartTime {
                Text(startTime, style: .timer)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }

            Button {
                model.sessionManager.endSession()
            } label: {
                Text("End")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.primary.opacity(0.06), in: Capsule())
            }
            .buttonStyle(PressFeedbackStyle())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(MC.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(MC.line, lineWidth: 0.5))
        .accessibilityIdentifier("activeSessionPill")
    }

    private var startSessionSheet: some View {
        NavigationStack {
            Form {
                Section("Session Info") {
                    TextField("Session Name (e.g. Shopping Trip)", text: $model.sessionSheetName)
                    TextField("Budget Limit in IDR (optional)", text: $model.sessionSheetBudget)
                        .keyboardType(.numberPad)
                }

                Section("Quick Presets") {
                    ForEach(["Shopping Trip", "Weekend Market", "Night Out", "Coffee Run", "Holiday Trip"], id: \.self) { preset in
                        Button {
                            model.sessionSheetName = preset
                        } label: {
                            HStack {
                                Text(preset).foregroundStyle(.primary)
                                Spacer()
                                if model.sessionSheetName == preset {
                                    Image(systemName: "checkmark").foregroundStyle(MC.red)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("New Spending Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        model.showStartSessionSheet = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") {
                        let activeCard = model.cards.first(where: { $0.id == model.activeCardID }) ?? model.cards.first
                        let cardName = activeCard?.name ?? "Daily"
                        var limit: Int64? = nil
                        if let parsed = try? Money.parse(model.sessionSheetBudget) {
                            limit = parsed
                        }
                        model.sessionManager.startSession(
                            name: model.sessionSheetName,
                            cardName: cardName,
                            cardID: activeCard?.id,
                            budgetLimit: limit
                        )
                        if let error = model.sessionManager.activityError { model.error = error }
                        model.sessionSheetName = ""
                        model.sessionSheetBudget = ""
                        model.showStartSessionSheet = false
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(MC.red)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
