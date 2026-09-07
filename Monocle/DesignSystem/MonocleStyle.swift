import SwiftUI

enum MC {
    static let red = Color(red: 0.83, green: 0.16, blue: 0.12)
    static let ink = Color(red: 0.10, green: 0.105, blue: 0.10)
    static let paper = Color(uiColor: .systemGroupedBackground)
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
    static let line = Color.primary.opacity(0.10)
    static func label(_ size: CGFloat = 10) -> Font { .system(size: size, weight: .medium, design: .monospaced) }
}

struct Eyebrow: View {
    let text: String
    var body: some View {
        Text(text.uppercased()).font(.caption2.monospaced()).tracking(1.5).foregroundStyle(.secondary)
    }
}

struct RecordButton: View {
    let title: String
    var symbol = "arrow.up.right"
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack { Text(title).font(.headline); Spacer(); Image(systemName: symbol).font(.headline) }
                .foregroundStyle(.white).padding(.horizontal, 22).frame(minHeight: 56)
                .background(MC.red, in: RoundedRectangle(cornerRadius: 18))
        }.buttonStyle(.plain)
    }
}

struct CategoryMark: View {
    let symbol: String
    var body: some View {
        Image(systemName: symbol).font(.system(size: 18, weight: .regular))
            .frame(width: 42, height: 42).background(MC.surface, in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(MC.line, lineWidth: 0.5)).accessibilityHidden(true)
    }
}
