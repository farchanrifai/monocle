import SwiftUI
import UIKit

struct ChatInputBar: View {
    @Binding var text: String
    @Binding var focused: Bool
    var isBusy: Bool
    var names: [Character: [String]] = [:]
    var onSend: () -> Void

    private var canSend: Bool { !isBusy && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(alignment: .bottom, spacing: 8) {
                MentionTextView(prompt: "Add an expense or ask… (@ card, # category)", text: $text, focused: $focused, names: names)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .frame(minHeight: 44) // one line matches the Send button
                    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 22))
                Button {
                    onSend()
                    // A field that still has marked text (the word being autocorrected) ignores the cleared binding and brings the
                    // old message back on the next keystroke, so the text view is emptied directly. The keyboard stays up.
                    (UIResponder.current as? UITextView)?.text = ""
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(canSend ? Color.white : Color.secondary)
                        .frame(width: 44, height: 44)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                // Liquid Glass: red-tinted and interactive when it can send, plain inert glass when it can't.
                .glassEffect(canSend ? .regular.tint(MC.red.opacity(0.85)).interactive() : .regular, in: .circle)
                .disabled(!canSend)
                .accessibilityLabel("Send")
                .accessibilityIdentifier("chatSend")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

/// The composer: a UITextView, so @ and # mentions are coloured in the field's own text (one layout, nothing drawn over it)
/// with a rounded chip behind each. Grows to five lines, then scrolls.
struct MentionTextView: UIViewRepresentable {
    let prompt: String
    @Binding var text: String
    @Binding var focused: Bool
    let names: [Character: [String]]
    var maxLines = 5

    func makeUIView(context: Context) -> MentionUITextView {
        let view = MentionUITextView()
        view.delegate = context.coordinator
        view.font = .preferredFont(forTextStyle: .body)
        view.adjustsFontForContentSizeCategory = true
        view.backgroundColor = .clear
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.isScrollEnabled = false
        view.accessibilityIdentifier = "chatInput"
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return view
    }

    func updateUIView(_ view: MentionUITextView, context: Context) {
        context.coordinator.parent = self
        if view.text != text {
            // Also clears marked text (a word mid-autocorrect), which would otherwise bring the old text back.
            view.text = text
            view.restyle(names: names)
        }
        view.placeholder.text = prompt
        view.placeholder.isHidden = !text.isEmpty
        // Focus follows the binding both ways; the delegate reports the keyboard's own changes.
        if focused, !view.isFirstResponder, view.window != nil { DispatchQueue.main.async { view.becomeFirstResponder() } }
        if !focused, view.isFirstResponder { DispatchQueue.main.async { view.resignFirstResponder() } }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView view: MentionUITextView, context: Context) -> CGSize? {
        // An unbounded width (SwiftUI measuring) says nothing about the box: answering it would turn scrolling off.
        guard let width = proposal.width, width > 0, width.isFinite else { return nil }
        let line = Self.height(of: NSAttributedString(string: " ", attributes: [.font: view.font as Any]), width: width)
        let fitted = Self.height(of: view.attributedText ?? NSAttributedString(), width: width)
        let limit = line * CGFloat(maxLines)
        view.isScrollEnabled = fitted > limit
        return CGSize(width: width, height: max(line, min(fitted, limit)))
    }

    /// Laid out the way the view does (TextKit 1, no padding) rather than asked of the view: a scrolling text view
    /// reports its own height back. Lines are taller than the font's lineHeight, so the limit is measured the same way.
    private static func height(of text: NSAttributedString, width: CGFloat) -> CGFloat {
        let storage = NSTextStorage(attributedString: text)
        let manager = NSLayoutManager(), container = NSTextContainer(size: CGSize(width: width, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        storage.addLayoutManager(manager)
        manager.addTextContainer(container)
        manager.ensureLayout(for: container)
        return ceil(manager.usedRect(for: container).height)
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: MentionTextView
        init(parent: MentionTextView) { self.parent = parent }

        func textViewDidChange(_ view: UITextView) {
            parent.text = view.text
            (view as? MentionUITextView)?.restyle(names: parent.names)
            // Past five lines the box scrolls; keep the line being typed in view once the new height has landed.
            DispatchQueue.main.async { if view.isScrollEnabled { view.scrollRangeToVisible(view.selectedRange) } }
        }
        func textViewDidBeginEditing(_ view: UITextView) { if !parent.focused { parent.focused = true } }
        func textViewDidEndEditing(_ view: UITextView) { if parent.focused { parent.focused = false } }
    }
}

final class MentionUITextView: UITextView {
    let placeholder = UILabel()
    /// Behind the text: sublayers of a scroll view move with its content, so the chips scroll with their words.
    private let chips = CAShapeLayer()
    private var chipRanges: [NSRange] = []

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        commonInit()
    }
    /// TextKit 1 from the start: its layout manager gives the chips' rects.
    convenience init() {
        let storage = NSTextStorage(), manager = NSLayoutManager(), container = NSTextContainer(size: .zero)
        container.widthTracksTextView = true
        storage.addLayoutManager(manager)
        manager.addTextContainer(container)
        self.init(frame: .zero, textContainer: container)
    }
    required init?(coder: NSCoder) { super.init(coder: coder); commonInit() }

    private func commonInit() {
        chips.fillColor = UIColor(MC.red.opacity(0.75)).cgColor
        layer.insertSublayer(chips, at: 0)
        placeholder.textColor = .placeholderText
        placeholder.font = .preferredFont(forTextStyle: .body)
        placeholder.adjustsFontForContentSizeCategory = true
        placeholder.isAccessibilityElement = false
        addSubview(placeholder)
    }

    /// Colours the mentions in place, keeping the selection; skipped while a word is being composed (marked text).
    func restyle(names: [Character: [String]]) {
        guard markedTextRange == nil else { return }
        let text = self.text ?? ""
        chipRanges = ChatMentionList.mentionRanges(text, names: names, typing: true).map { NSRange($0, in: text) }
        let selection = selectedRange
        let storage = textStorage
        storage.beginEditing()
        let all = NSRange(location: 0, length: storage.length)
        storage.setAttributes([.font: font ?? .preferredFont(forTextStyle: .body), .foregroundColor: UIColor.label], range: all)
        for range in chipRanges where NSMaxRange(range) <= storage.length { storage.addAttribute(.foregroundColor, value: UIColor.white, range: range) }
        storage.endEditing()
        typingAttributes = [.font: font ?? .preferredFont(forTextStyle: .body), .foregroundColor: UIColor.label]
        selectedRange = selection
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        placeholder.frame = CGRect(x: textContainerInset.left, y: textContainerInset.top, width: bounds.width, height: placeholder.intrinsicContentSize.height)
        let path = UIBezierPath()
        let none = NSRange(location: NSNotFound, length: 0)
        for range in chipRanges where NSMaxRange(range) <= textStorage.length {
            let glyphs = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            layoutManager.enumerateEnclosingRects(forGlyphRange: glyphs, withinSelectedGlyphRange: none, in: textContainer) { rect, _ in
                let chip = rect.offsetBy(dx: self.textContainerInset.left, dy: self.textContainerInset.top).insetBy(dx: -2, dy: -1)
                path.append(UIBezierPath(roundedRect: chip, cornerRadius: 7))
            }
        }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        chips.path = path.cgPath
        CATransaction.commit()
    }

    override func traitCollectionDidChange(_ previous: UITraitCollection?) {
        super.traitCollectionDidChange(previous)
        chips.fillColor = UIColor(MC.red.opacity(0.75)).cgColor
    }
}

private extension UIResponder {
    private static weak var found: UIResponder?
    /// The first responder, found by sending an action down the responder chain.
    static var current: UIResponder? {
        found = nil
        UIApplication.shared.sendAction(#selector(capture), to: nil, from: nil, for: nil)
        return found
    }
    @objc private func capture() { Self.found = self }
}
