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
    let book: BookProfile
    let expenseCount: Int
    let isSelected: Bool
    let expanded: Bool
    let onOpen: () -> Void

    func body(content: Content) -> some View {
        content
            .accessibilityElement(children: isSelected ? .contain : .combine)
            .accessibilityLabel(isSelected ? book.name + " selected card" : "Open \(book.name), \(expenseCount) transactions")
            .accessibilityIdentifier("stack-book-\(book.id)")
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
    let book: BookProfile
    let index: Int
    let isSelected: Bool
    let expanded: Bool
    let detailScroll: CGFloat
    let displayedBooksCount: Int
    let onDismissChanged: (CGPoint) -> Void
    let onDismissEnded: (CGPoint, Bool) -> Void
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
            .gesture(CardDismissPan(
                enabled: isSelected && expanded && detailScroll <= 1,
                changed: onDismissChanged,
                ended: onDismissEnded
            ))
            .gesture(
                !expanded ?
                DragGesture(minimumDistance: 7)
                    .onChanged { value in
                        guard abs(value.translation.height) > abs(value.translation.width) else { return }
                        onDragCardIDChanged(book.id)
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
                            onSwipingCardIDChanged(book.id)
                        }
                    }
                    .onEnded { value in
                        if value.translation.width > 45 {
                            onMoveToFront()
                        }
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                            onSwipeOffsetChanged(0)
                            onSwipingCardIDChanged(nil)
                        }
                    }
                : nil
            )
            .contextMenu {
                if !expanded {
                    if displayedBooksCount > 1 && index > 0 {
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

/// Main home screen presenting an Apple Wallet-style stacked card deck with durable multi-book persistence.
struct BookHomeView: View {
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
    @State private var showingBudgets = false
    @State private var showingBills = false
    @State private var draggedCardID: UUID?
    @State private var dragAmount: CGFloat = 0
    @State private var dismissAmount: CGFloat = 0
    @State private var dismissX: CGFloat = 0
    @State private var returnDistance: CGFloat = 0
    @State private var releaseVelocity: Double = 0
    @State private var detailScroll: CGFloat = 0
    @State private var scrollOverscroll: CGFloat = 0

    @State private var displayedBooks: [BookProfile] = []
    @State private var displayedFilterScope: StackFilterScope? = nil
    @State private var displayedStackID: UUID? = nil
    @State private var currentStackKey: String = ""
    @State private var targetStackKey: String = ""
    @State private var flippedCardID: UUID? = nil
    @State private var dragTilt: CGSize = .zero
    @State private var swipingCardID: UUID? = nil
    @State private var swipeOffset: CGFloat = 0.0

    private var stackKey: String {
        "\(model.filterScope.rawValue)-\(model.activeStackID?.uuidString ?? "all")"
    }

    private var visible: [BookProfile] { model.visibleBooks }
    private var current: BookProfile? { model.books.first { $0.id == selectedID } }

    private var direction: BookVisualDirection { model.effectiveDirection(for: colorScheme) }
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
            return .title.bold()
        case .ledger:
            return .system(.title, design: .serif, weight: .semibold)
        case .instrument:
            return .system(.title, design: .monospaced, weight: .bold)
        }
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
                header
                    .background(
                        paper
                            .opacity(selectedID == nil ? 0.96 : (detailScroll > 15 ? 0.96 : 0.0))
                            .ignoresSafeArea(edges: .top)
                    )
                    .zIndex(1000)
            }
            .gesture(CardDismissPan(enabled: selectedID != nil && expanded && detailScroll <= 1,
                                    changed: updateDismiss, ended: endDismiss))
            .onChange(of: selectedID) { _, id in
                guard id != nil else { return }
                withAnimation(reduceMotion ? .easeOut(duration: 0.15) : opening) {
                    expanded = true
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if showsBottomBar {
                Button {
                    let targetID = selectedID ?? displayedBooks.first?.id ?? model.activeBookID
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
            case .existing(let book):
                CardCustomizerView(
                    model: model,
                    initialBook: book,
                    books: visible.isEmpty ? model.unhiddenBooks : visible,
                    isCreatingNewBook: false
                ) {
                    model.customizerTarget = nil
                }
            case .newBook:
                CardCustomizerView(
                    model: model,
                    initialBook: visible.first ?? model.unhiddenBooks.first,
                    books: visible.isEmpty ? model.unhiddenBooks : visible,
                    isCreatingNewBook: true
                ) {
                    model.customizerTarget = nil
                }
            }
        }
        .sheet(isPresented: $showingBudgets) {
            NavigationStack {
                BudgetsView(model: model)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showingBudgets = false }
                        }
                    }
            }
        }
        .sheet(isPresented: $showingBills) {
            NavigationStack {
                BillsView(model: model)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showingBills = false }
                        }
                    }
            }
        }
        .sheet(isPresented: $model.showCSVInterchange) {
            CSVInterchangeView(model: model, initialTab: model.csvInterchangeInitialTab)
        }
        .sheet(isPresented: $model.showAnalytics) {
            AnalyticsView(model: model)
        }
        .onAppear {
            if displayedBooks.isEmpty {
                displayedBooks = model.visibleBooks
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
            if let active = model.selectedBookID, let book = displayedBooks.first(where: { $0.id == active }) {
                selectedID = active
                expanded = true
            }
        }
        .onChange(of: stackKey) { _, newKey in
            if targetStackKey != newKey {
                performStackTransition(to: newKey)
            }
        }
        .onChange(of: model.visibleBooks) { _, newVisible in
            withAnimation(settle) {
                displayedBooks = newVisible
            }
        }
        .onChange(of: model.selectedBookID) { _, newID in
            if selectedID != newID {
                if let newID, let book = displayedBooks.first(where: { $0.id == newID }) {
                    openCard(book)
                } else if newID == nil && expanded {
                    closeCard()
                }
            }
        }
    }

    private var header: some View {
        HStack {
            if expanded, let current {
                HStack(spacing: 8) {
                    Button {
                        closeCard()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.headline.weight(.semibold))
                            .frame(width: 44, height: 44)
                            .foregroundStyle(ink)
                    }
                    .accessibilityLabel("All book cards")
                    .accessibilityIdentifier("closeBookDetail")

                    Text(current.name)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(ink)
                        .lineLimit(1)
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("monocle").font(.system(size: 28, weight: .semibold, design: .rounded)).tracking(-1.2)
                        .foregroundStyle(ink)
                    Text(".").font(.system(size: 30, weight: .bold)).foregroundStyle(MC.red)
                }
                .fixedSize(horizontal: true, vertical: false)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("monocle")
                .accessibilityIdentifier("homeLogo")
            }
            Spacer()
            Button { model.showSettings = true } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.title3)
                    .frame(width: 44, height: 44)
                    .foregroundStyle(ink)
            }
            .accessibilityLabel("Settings")
            .accessibilityIdentifier("homeSettings")
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
        let restingHeight = CGFloat(max(0, displayedBooks.count - 1)) * step + cardHeight

        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                stackView(width: cardWidth, height: cardHeight, step: step)
                    .frame(height: restingHeight + stackExpansion(displayedBooks), alignment: .top)

                if displayedBooks.isEmpty {
                    ContentUnavailableView {
                        Label("Your stack is empty", systemImage: "rectangle.stack")
                    } description: {
                        Text("Add cards to this stack or switch stacks with the filter button.")
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

                activitySection(bookID: nil)
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

    private func stackExpansion(_ group: [BookProfile]) -> CGFloat {
        let isDraggedGroup = group.contains(where: { $0.id == draggedCardID })
        guard isDraggedGroup || (draggedCardID == nil && scrollOverscroll > 0) else { return 0 }
        let disp = isDraggedGroup ? dragAmount : (pow(scrollOverscroll, 0.88) * 0.45)
        let activeIdx = isDraggedGroup ? (group.firstIndex(where: { $0.id == draggedCardID }) ?? 0) : -1
        return max(0, WalletStackLayout.fanningOffset(for: group.count - 1, totalCount: group.count, activeIndex: activeIdx, displacement: disp))
    }

    private func stackView(width: CGFloat, height: CGFloat, step: CGFloat) -> some View {
        let isDragged = displayedBooks.contains(where: { $0.id == draggedCardID })
        let activeIdx = isDragged ? (displayedBooks.firstIndex(where: { $0.id == draggedCardID }) ?? displayedBooks.count) : (draggedCardID == nil && scrollOverscroll > 0 ? -1 : displayedBooks.count)
        let effectiveDisp = isDragged ? dragAmount : ((draggedCardID == nil && scrollOverscroll > 0) ? (pow(scrollOverscroll, 0.88) * 0.45) : 0)

        return WalletStackLayout(step: step, cardHeight: height, activeIndex: activeIdx, displacement: effectiveDisp) {
            ForEach(displayedBooks) { book in
                Color.clear.frame(width: width, height: height)
                    .anchorPreference(key: CardFrames.self, value: .bounds) { [book.id.uuidString: $0] }
            }
        }
    }

    private func detail(_ book: BookProfile, width: CGFloat) -> some View {
        let heroWidth = width - 32
        let heroHeight = heroWidth * 0.63
        let progress = min(max(dismissAmount / 280, 0), 1)

        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Color.clear
                    .frame(width: heroWidth, height: heroHeight)
                    .anchorPreference(key: CardFrames.self, value: .bounds) { ["detail": $0] }
                    .allowsHitTesting(false)

                activitySection(bookID: book.id)
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
        ForEach(Array(displayedBooks.enumerated()), id: \.element.id) { index, book in
            if let anchor = frames[book.id.uuidString] {
                let homeFrame = geometry[anchor]
                let isSelected = selectedID == book.id
                let selectedIndex = displayedBooks.firstIndex { $0.id == selectedID } ?? displayedBooks.count
                let below = index > selectedIndex
                let detailFrame = frames["detail"].map { geometry[$0] } ?? homeFrame
                let target = isSelected && expanded ? detailFrame : homeFrame

                cardPlaneItem(
                    index: index,
                    book: book,
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
        book: BookProfile,
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
        let horizontalOffset: CGFloat = (swipingCardID == book.id) ? swipeOffset : 0

        let posX = target.midX + horizontalOffset + (isSelected && expanded && !reduceMotion ? dismissX : 0)
        let posY = target.midY + otherOffset + (isSelected && expanded && !reduceMotion ? dismissAmount : 0)

        cardInteractiveView(book: book, index: index, target: target, isSelected: isSelected)
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
        book: BookProfile,
        index: Int,
        target: CGRect,
        isSelected: Bool
    ) -> some View {
        cardView(book, index: index, isCurrent: isSelected)
            .frame(width: target.width, height: target.height)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .modifier(CardAccessibilityModifier(
                book: book,
                expenseCount: model.expenses(for: book.id).count,
                isSelected: isSelected,
                expanded: expanded,
                onOpen: { openCard(book) }
            ))
            .modifier(CardGesturesModifier(
                book: book,
                index: index,
                isSelected: isSelected,
                expanded: expanded,
                detailScroll: detailScroll,
                displayedBooksCount: displayedBooks.count,
                onDismissChanged: updateDismiss,
                onDismissEnded: endDismiss,
                onFlip: {
                    if selectedID != book.id { openCard(book) }
                    toggleFlip(for: book.id)
                },
                onCustomize: { openCustomizer(for: book) },
                onMoveToFront: {
                    let generator = UIImpactFeedbackGenerator(style: .medium)
                    generator.impactOccurred()
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                        model.moveBookToFront(book.id)
                    }
                },
                onDragAmountChanged: { val in dragAmount = val },
                onDragCardIDChanged: { id in draggedCardID = id },
                onDragEnded: { val in
                    if val.translation.height < -55 || val.predictedEndTranslation.height < -110 {
                        openCard(book)
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

    private func openCard(_ book: BookProfile) {
        let haptic = UIImpactFeedbackGenerator(style: .medium)
        haptic.impactOccurred()
        dismissAmount = 0
        dismissX = 0
        detailScroll = 0
        releaseVelocity = 0
        selectedID = book.id
        model.selectedBookID = book.id
        model.selectBook(book.id)
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : opening) {
            expanded = true
        }
    }

    private func closeCard(velocity: CGFloat = 0) {
        guard selectedID != nil else { return }
        let haptic = UIImpactFeedbackGenerator(style: .light)
        haptic.impactOccurred()
        let travel = returnDistance - dismissAmount
        releaseVelocity = abs(travel) > 1 ? Double(min(max(velocity / travel, -8), 8)) : 0
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : settle) {
            expanded = false
            model.selectedBookID = nil
        } completion: {
            guard !expanded else { return }
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
                displayedBooks = model.visibleBooks
                displayedFilterScope = model.filterScope
                displayedStackID = model.activeStackID
                currentStackKey = targetKey
            }
            return
        }

        withAnimation(settle) {
            displayedBooks = model.visibleBooks
            displayedFilterScope = model.filterScope
            displayedStackID = model.activeStackID
            currentStackKey = targetKey
        }
    }

    private func cardView(_ book: BookProfile, index: Int, isCurrent: Bool) -> some View {
        let isFlipped = (flippedCardID == book.id)

        let tiltX = (isCurrent && !reduceMotion && dismissAmount == 0) ? min(max(-dragTilt.height / 14, -12), 12) : 0
        let tiltY = (isCurrent && !reduceMotion && dismissAmount == 0) ? min(max(dragTilt.width / 14, -12), 12) : 0

        return ZStack {
            cardFrontView(book, index: index, isCurrent: isCurrent)
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
                    book: book,
                    index: index,
                    onFlipBack: {
                        toggleFlip(for: book.id)
                    },
                    onOpenAnalytics: {
                        model.showAnalytics = true
                    },
                    onCustomize: {
                        openCustomizer(for: book)
                    }
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
            .degrees(tiltX),
            axis: (x: 1, y: 0, z: 0),
            perspective: 0.8
        )
        .rotation3DEffect(
            .degrees(tiltY),
            axis: (x: 0, y: 1, z: 0),
            perspective: 0.8
        )
        .simultaneousGesture(
            (isCurrent && dismissAmount == 0) ?
                DragGesture(minimumDistance: 8)
                    .onChanged { value in
                        if abs(value.translation.width) > abs(value.translation.height) * 1.3 {
                            dragTilt = value.translation
                        }
                    }
                    .onEnded { _ in
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.72)) {
                            dragTilt = .zero
                        }
                    }
                : nil
        )
    }

    private func cardFrontView(_ book: BookProfile, index: Int, isCurrent: Bool) -> some View {
        let bookExpenses = model.expenses(for: book.id)
        let total = model.spent(for: book.id)
        let customization = model.customization(for: book.id)
        let textStyle = CardPalette.resolvedTextColor(for: customization)

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Text(book.name)
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 8)

                HStack(spacing: 6) {
                    if isCurrent && expanded {
                        Button {
                            toggleFlip(for: book.id)
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

            Text(Money.format(total))
                .font(amountFont)
                .monospacedDigit()
                .minimumScaleFactor(0.65)
            Text("\(bookExpenses.count) TRANSACTIONS")
                .font(.system(size: 11, weight: .medium).monospaced())
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .foregroundStyle(textStyle)
        .background(
            ZStack {
                cardBackground(for: customization, book: book)
                specularSheen(isCurrent: isCurrent)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.black.opacity(0.12), lineWidth: 0.5))
    }

    @ViewBuilder
    private func specularSheen(isCurrent: Bool) -> some View {
        if !reduceMotion {
            let shiftX = isCurrent ? (dragTilt.width / 350) : (scrollOverscroll * 0.002)
            let shiftY = isCurrent ? (dragTilt.height / 350) : (scrollOverscroll * 0.003)

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
    private func cardBackground(for customization: BookCardCustomization, book: BookProfile) -> some View {
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
                CardPalette.color(for: book.colorIndex)
            }
        }
    }

    private func activitySection(bookID: UUID?) -> some View {
        let activeScope = displayedFilterScope ?? model.filterScope
        let isAllCards = activeScope == .allCards
        let activeStack = model.stacks.first { $0.id == (displayedStackID ?? model.activeStackID) } ?? model.currentStack
        let activities = model.activities(selectedBookID: bookID, allBooks: isAllCards)
        let selectedBook = model.books.first { $0.id == bookID }
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(bookID != nil ? "Latest Transactions" : (isAllCards ? "All Transactions" : "Recent Activities"))
                    .font(bookID != nil ? .system(size: 17, weight: .semibold) : .system(size: 18, weight: .bold))
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused($headingFocused)

                if bookID == nil {
                    HStack(spacing: 4) {
                        Image(systemName: isAllCards ? "rectangle.stack" : (activeStack?.icon ?? "square.stack.3d.up.fill"))
                            .font(.caption2.weight(.bold))
                        Text(isAllCards ? "All cards · \(model.unhiddenBooks.count)" : "\(activeStack?.name ?? "Stack") · \(activeStack?.cardIDs.count ?? 0)")
                            .font(.caption2.weight(.semibold))
                    }
                    .foregroundStyle(isAllCards ? Color.secondary : MC.red)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(isAllCards ? Color.primary.opacity(0.06) : MC.red.opacity(0.12))
                    )
                    .accessibilityIdentifier("activityScopeBadge")
                    Spacer()
                }
            }

            if activities.isEmpty {
                if bookID != nil {
                    VStack(spacing: 10) {
                        Image(systemName: "tray")
                            .font(.system(size: 28))
                            .foregroundStyle(ink.opacity(0.35))
                        Text("No Transactions Yet")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(ink)
                        Text("Transactions recorded for this card will appear here.")
                            .font(.system(size: 13))
                            .foregroundStyle(ink.opacity(0.6))
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 36)
                    .padding(.horizontal, 20)
                    .background(MC.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                } else {
                    ContentUnavailableView(
                        "Nothing recorded yet",
                        systemImage: "text.book.closed",
                        description: Text("Tap Add Expense below to record your first transaction.")
                    )
                    .padding(.vertical, 24)
                }
            } else {
                if bookID != nil {
                    VStack(spacing: 0) {
                        ForEach(activities) { row in
                            activityRow(row, showBookLabel: false, isPlatter: true)
                        }
                    }
                    .background(MC.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(activities) { row in
                            activityRow(row, showBookLabel: true, isPlatter: false)
                        }
                    }
                }
            }
        }
    }

    private func activityRow(_ expense: Expense, showBookLabel: Bool, isPlatter: Bool = false) -> some View {
        Button {
            model.edit(expense)
        } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.title(expense))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(ink)
                        .lineLimit(1)
                    Text(showBookLabel && expense.bookID != nil ? "\(expense.day) · \(model.books.first(where: { $0.id == expense.bookID })?.name ?? "")" : expense.day)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(ink.opacity(0.55))
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Text(Money.format(expense.amount))
                    .font(.system(size: 14.5, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(ink)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, isPlatter ? 16 : 0)
            .padding(.vertical, isPlatter ? 11 : 10)
            .frame(minHeight: isPlatter ? 60 : 50)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressFeedbackStyle())
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

    private var optionsMenu: some View {
        Menu {
            Picker("Visual direction", selection: $model.visualDirection) {
                ForEach(BookVisualDirection.allCases) { dir in
                    Text(dir.rawValue).tag(dir)
                }
            }

            Button {
                openCustomizerForNewBook()
            } label: {
                Label("Create new book", systemImage: "plus.rectangle.on.rectangle")
            }

            if let targetBook = current ?? visible.first ?? model.books.first {
                Button {
                    openCustomizer(for: targetBook)
                } label: {
                    Label("Customize card", systemImage: "paintbrush")
                }
            }

            Button {
                model.stackCustomizerMode = .manage
                model.showStackCustomizer = true
            } label: {
                Label("Stacks & Card Visibility", systemImage: "square.stack.3d.up")
            }

            Button {
                managing = true
            } label: {
                Label("Manage stack order", systemImage: "slider.horizontal.3")
            }

            Button {
                showingBudgets = true
            } label: {
                Label("Budgets", systemImage: "chart.bar.xaxis")
            }
            .accessibilityIdentifier("menuBudgets")

            Button {
                model.showAnalytics = true
            } label: {
                Label("Analytics & Trends", systemImage: "chart.line.uptrend.xyaxis")
            }
            .accessibilityIdentifier("menuAnalytics")

            Button {
                showingBills = true
            } label: {
                Label("Bills", systemImage: "calendar")
            }
            .accessibilityIdentifier("menuBills")

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
                Label("CSV Data", systemImage: "tablecells")
            }
            .accessibilityIdentifier("menuCSVData")

            if selectedID != nil {
                Button("Return to stack") { closeCard() }
            }

            Section("Active cards") {
                ForEach(model.unhiddenBooks) { book in
                    Button(book.name) {
                        if selectedID != book.id {
                            if selectedID != nil {
                                closeCard()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    openCard(book)
                                }
                            } else {
                                openCard(book)
                            }
                        }
                    }
                }
            }

            let archived = model.books.filter { model.alwaysHiddenBookIDs.contains($0.id) }
            if !archived.isEmpty {
                Section("Archived cards") {
                    ForEach(archived) { book in
                        Button(book.name) {
                            if selectedID != book.id {
                                if selectedID != nil {
                                    closeCard()
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                        openCard(book)
                                    }
                                } else {
                                    openCard(book)
                                }
                            }
                        }
                    }
                }
            }

            Section {
                Button {
                    model.showSettings = true
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title2)
                .frame(width: 44, height: 44)
                .foregroundStyle(ink)
        }
        .accessibilityLabel("Book options")
        .accessibilityIdentifier("bookOptionsMenu")
    }

    private func toggleFlip(for bookID: UUID) {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.42, dampingFraction: 0.80)) {
            if flippedCardID == bookID {
                flippedCardID = nil
            } else {
                flippedCardID = bookID
            }
        }
    }

    private func openCustomizer(for book: BookProfile) {
        model.customizerTarget = .existing(book)
    }

    private func openCustomizerForNewBook() {
        model.customizerTarget = .newBook
    }

    private var manageStackSheet: some View {
        NavigationStack {
            List {
                Section("Visible cards · drag to reorder") {
                    ForEach(model.orderedBooks) { book in
                        Toggle(book.name, isOn: Binding(
                            get: { !model.hiddenBookIDs.contains(book.id) },
                            set: { isVisible in
                                model.setBookHidden(id: book.id, isHidden: !isVisible)
                            }
                        ))
                    }
                    .onMove { from, to in
                        model.reorderBooks(fromOffsets: from, toOffset: to)
                    }
                }

                Section {
                    Button("Show every book") {
                        model.hiddenBookIDs = []
                        model.persistWorkspacePreferences()
                    }
                    Button("Create new book") {
                        managing = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            openCustomizerForNewBook()
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
}
