import SwiftUI

public enum CardTextTone: String, Codable, Sendable, CaseIterable {
    case auto
    case light
    case dark

    public var title: String {
        switch self {
        case .auto: return "Auto"
        case .light: return "Light text"
        case .dark: return "Dark text"
        }
    }
}

public enum StockCardDesign: String, Codable, Sendable, CaseIterable, Identifiable {
    case sunsetHeat
    case auroraBorealis
    case midnightCosmo
    case acidCyber
    case titaniumMetal
    case appleAura
    case topographic
    case neoGrid
    case warmParchment

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .sunsetHeat: return "Sunset Heat"
        case .auroraBorealis: return "Aurora"
        case .midnightCosmo: return "Cosmos"
        case .acidCyber: return "Acid Cyber"
        case .titaniumMetal: return "Titanium"
        case .appleAura: return "Aura Mesh"
        case .topographic: return "Topography"
        case .neoGrid: return "Neo Grid"
        case .warmParchment: return "Parchment"
        }
    }

    public var defaultTextTone: CardTextTone {
        switch self {
        case .sunsetHeat, .auroraBorealis, .midnightCosmo, .topographic, .neoGrid:
            return .light
        case .acidCyber, .titaniumMetal, .appleAura, .warmParchment:
            return .dark
        }
    }
}

public enum CardBackgroundStyle: Codable, Equatable, Hashable, Sendable {
    case palette(index: Int)
    case customColor(hex: String)
    case stock(StockCardDesign)
    case customPhoto(filename: String)

    private enum CodingKeys: String, CodingKey {
        case type, index, hex, stockDesign, filename
    }

    private enum StyleType: String, Codable {
        case palette, customColor, stock, customPhoto
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(StyleType.self, forKey: .type)
        switch type {
        case .palette:
            let index = try container.decodeIfPresent(Int.self, forKey: .index) ?? 0
            self = .palette(index: index)
        case .customColor:
            let hex = try container.decode(String.self, forKey: .hex)
            self = .customColor(hex: hex)
        case .stock:
            let design = try container.decode(StockCardDesign.self, forKey: .stockDesign)
            self = .stock(design)
        case .customPhoto:
            let filename = try container.decode(String.self, forKey: .filename)
            self = .customPhoto(filename: filename)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .palette(let index):
            try container.encode(StyleType.palette, forKey: .type)
            try container.encode(index, forKey: .index)
        case .customColor(let hex):
            try container.encode(StyleType.customColor, forKey: .type)
            try container.encode(hex, forKey: .hex)
        case .stock(let design):
            try container.encode(StyleType.stock, forKey: .type)
            try container.encode(design, forKey: .stockDesign)
        case .customPhoto(let filename):
            try container.encode(StyleType.customPhoto, forKey: .type)
            try container.encode(filename, forKey: .filename)
        }
    }
}

public struct BookCardCustomization: Codable, Equatable, Hashable, Sendable {
    public var style: CardBackgroundStyle
    public var textTone: CardTextTone

    public init(style: CardBackgroundStyle = .palette(index: 0), textTone: CardTextTone = .auto) {
        self.style = style
        self.textTone = textTone
    }

    public static func defaultFor(colorIndex: Int) -> Self {
        Self(style: .palette(index: colorIndex), textTone: .auto)
    }
}

// MARK: - Color Palette & Helpers

public struct CardPaletteColor: Identifiable, Sendable {
    public var id: Int
    public var name: String
    public var color: Color
    public var hex: String
}

public enum CardPalette {
    public static let standard: [CardPaletteColor] = [
        CardPaletteColor(id: 0, name: "Monocle Orange", color: Color(red: 0.98, green: 0.38, blue: 0.16), hex: "#FA6129"),
        CardPaletteColor(id: 1, name: "Sky Blue",       color: Color(red: 0.42, green: 0.62, blue: 0.96), hex: "#6B9EF5"),
        CardPaletteColor(id: 2, name: "Acid Lime",      color: Color(red: 0.84, green: 0.94, blue: 0.38), hex: "#D6F061"),
        CardPaletteColor(id: 3, name: "Lavender",       color: Color(red: 0.93, green: 0.68, blue: 0.88), hex: "#EDAEE0"),
        CardPaletteColor(id: 4, name: "Goldenrod",      color: Color(red: 0.98, green: 0.80, blue: 0.28), hex: "#FACD47"),
        CardPaletteColor(id: 5, name: "Seafoam",        color: Color(red: 0.40, green: 0.85, blue: 0.75), hex: "#66D9BF"),
        CardPaletteColor(id: 6, name: "Rose",           color: Color(red: 0.85, green: 0.45, blue: 0.55), hex: "#D9738C"),
        CardPaletteColor(id: 7, name: "Periwinkle",     color: Color(red: 0.55, green: 0.60, blue: 0.90), hex: "#8D99E6"),
        CardPaletteColor(id: 8, name: "Obsidian",       color: Color(red: 0.13, green: 0.13, blue: 0.14), hex: "#212124"),
        CardPaletteColor(id: 9, name: "Emerald",        color: Color(red: 0.15, green: 0.68, blue: 0.48), hex: "#26AD7A"),
        CardPaletteColor(id: 10, name: "Crimson",       color: Color(red: 0.88, green: 0.22, blue: 0.25), hex: "#E13840"),
        CardPaletteColor(id: 11, name: "Deep Navy",     color: Color(red: 0.12, green: 0.22, blue: 0.40), hex: "#1F3866")
    ]

    public static func color(for index: Int) -> Color {
        let palette = standard
        let safeIndex = abs(index) % palette.count
        return palette[safeIndex].color
    }

    public static func color(fromHex hex: String) -> Color {
        let clean = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: clean).scanHexInt64(&int)
        let r, g, b: Double
        switch clean.count {
        case 6:
            r = Double((int >> 16) & 0xFF) / 255
            g = Double((int >> 8) & 0xFF) / 255
            b = Double(int & 0xFF) / 255
        default:
            r = 0.5; g = 0.5; b = 0.5
        }
        return Color(red: r, green: g, blue: b)
    }

    public static func hexString(from color: Color) -> String {
        let uiColor = UIColor(color)
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        let ri = Int(round(r * 255))
        let gi = Int(round(g * 255))
        let bi = Int(round(b * 255))
        return String(format: "#%02X%02X%02X", ri, gi, bi)
    }

    public static func isDark(hex: String) -> Bool {
        let clean = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: clean).scanHexInt64(&int)
        guard clean.count == 6 else { return false }
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8) & 0xFF) / 255
        let b = Double(int & 0xFF) / 255
        // Standard relative luminance
        let luminance = 0.299 * r + 0.587 * g + 0.114 * b
        return luminance < 0.55
    }

    public static func resolvedTextColor(for customization: BookCardCustomization) -> Color {
        switch customization.textTone {
        case .light:
            return .white
        case .dark:
            return .black
        case .auto:
            switch customization.style {
            case .palette(let index):
                let safeIndex = abs(index) % standard.count
                let hex = standard[safeIndex].hex
                return isDark(hex: hex) ? .white : .black
            case .customColor(let hex):
                return isDark(hex: hex) ? .white : .black
            case .stock(let design):
                return design.defaultTextTone == .light ? .white : .black
            case .customPhoto:
                return .white
            }
        }
    }
}
