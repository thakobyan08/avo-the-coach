import SwiftUI

/// Avo's design tokens: the character palette and the card colours.
enum Theme {
    static let skin = Color(hex: 0x5B8C32)
    static let flesh = Color(hex: 0xD7E89A)
    static let belly = Color(hex: 0xE4EEA6)
    static let outline = Color(hex: 0x2A3317)
    static let accent = Color(hex: 0xE4573D)
    static let accentText = Color(hex: 0xC2412A)
    static let leaf = Color(hex: 0x7DB04A)
    static let blush = Color(hex: 0xF58A7A)
    static let tile = Color(hex: 0xEAF4D6)
    static let ink = Color(hex: 0x22201C)
    static let mutedText = Color(hex: 0x6B665C)
    static let cardButtonLight = Color(hex: 0xEFECE6)
    /// From the Flow design.
    static let cardBorder = Color(hex: 0xE7E3DA)
    static let bodyText = Color(hex: 0x4A463F)
    static let dotEmpty = Color(hex: 0xE2DDD3)

    /// Fredoka in the design; SF Pro Rounded in the app.
    static func display(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .rounded)
    }

    /// DM Sans in the design; SF Pro in the app.
    static func body(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
