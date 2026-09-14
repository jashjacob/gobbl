import SwiftUI

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: alpha)
    }
}

/// The notch is always black, so the palette is dark-only.
enum Palette {
    /// Gobbl lime.
    static let accent = Color(hex: 0xA6F25C)
    static let text = Color(hex: 0xEDEEF0)
    static let textSecondary = Color(hex: 0x9A9FA8)
    static let textTertiary = Color(hex: 0x62666F)
    static let well = Color.white.opacity(0.06)
    static let wellHover = Color.white.opacity(0.12)
    static let border = Color.white.opacity(0.1)
    static let gold = Color(hex: 0xF5C542)
}

extension Font {
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

extension Animation {
    static let gob = Animation.spring(response: 0.36, dampingFraction: 0.78)
}
