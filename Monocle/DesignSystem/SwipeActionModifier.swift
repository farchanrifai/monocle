import SwiftUI
import UIKit

struct SwipeActionModifier: ViewModifier {
    let onTap: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var offset: CGFloat = 0
    @State private var prevOffset: CGFloat = 0
    @State private var hasTriggeredHaptic = false
    @State private var isDragging = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let actionWidth: CGFloat = 72
    private let fullSwipeThreshold: CGFloat = 110

    func body(content: Content) -> some View {
        ZStack(alignment: .center) {
            // Action Buttons Layer
            HStack(spacing: 0) {
                // Leading: Edit Button
                if offset > 0 {
                    Button {
                        triggerEdit()
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "pencil")
                                .font(.system(size: 17, weight: .semibold))
                            Text("Edit")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundStyle(.white)
                        .frame(width: max(0, offset))
                        .frame(maxHeight: .infinity)
                        .background(Color(red: 0.15, green: 0.52, blue: 0.95))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Edit expense")
                }

                Spacer(minLength: 0)

                // Trailing: Delete Button
                if offset < 0 {
                    Button {
                        triggerDelete()
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "trash.fill")
                                .font(.system(size: 17, weight: .semibold))
                            Text("Delete")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundStyle(.white)
                        .frame(width: max(0, -offset))
                        .frame(maxHeight: .infinity)
                        .background(Color(red: 0.92, green: 0.22, blue: 0.20))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Delete expense")
                }
            }

            // Main Row Content Layer
            content
                .background(MC.surface)
                .offset(x: offset)
                .contentShape(Rectangle())
                .highPriorityGesture(
                    DragGesture(minimumDistance: 12, coordinateSpace: .local)
                        .onChanged { value in
                            isDragging = true
                            let horizontal = value.translation.width
                            let vertical = value.translation.height
                            guard abs(horizontal) > abs(vertical) || abs(offset) > 0 else { return }

                            let raw = prevOffset + horizontal
                            if raw > 0 {
                                if raw > actionWidth {
                                    offset = actionWidth + (raw - actionWidth) * 0.45
                                } else {
                                    offset = raw
                                }
                            } else {
                                if raw < -actionWidth {
                                    offset = -actionWidth + (raw + actionWidth) * 0.45
                                } else {
                                    offset = raw
                                }
                            }

                            if abs(offset) >= fullSwipeThreshold && !hasTriggeredHaptic {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                hasTriggeredHaptic = true
                            } else if abs(offset) < fullSwipeThreshold {
                                hasTriggeredHaptic = false
                            }
                        }
                        .onEnded { value in
                            let horizontal = value.translation.width
                            let total = prevOffset + horizontal

                            if total > fullSwipeThreshold {
                                triggerEdit()
                            } else if total < -fullSwipeThreshold {
                                triggerDelete()
                            } else if total > actionWidth * 0.55 {
                                withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.78)) {
                                    offset = actionWidth
                                    prevOffset = actionWidth
                                }
                            } else if total < -actionWidth * 0.55 {
                                withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.78)) {
                                    offset = -actionWidth
                                    prevOffset = -actionWidth
                                }
                            } else {
                                resetOffset()
                            }
                            hasTriggeredHaptic = false
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                isDragging = false
                            }
                        }
                )
                .onTapGesture {
                    guard !isDragging else { return }
                    if offset != 0 {
                        resetOffset()
                    } else {
                        onTap()
                    }
                }
        }
        .clipped()
        .accessibilityAction(named: "Edit") { onEdit() }
        .accessibilityAction(named: "Delete") { onDelete() }
    }

    private func resetOffset() {
        withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8)) {
            offset = 0
            prevOffset = 0
        }
    }

    private func triggerEdit() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        resetOffset()
        onEdit()
    }

    private func triggerDelete() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        resetOffset()
        onDelete()
    }
}

extension View {
    func transactionSwipeActions(onTap: @escaping () -> Void, onEdit: @escaping () -> Void, onDelete: @escaping () -> Void) -> some View {
        self.modifier(SwipeActionModifier(onTap: onTap, onEdit: onEdit, onDelete: onDelete))
    }
}
