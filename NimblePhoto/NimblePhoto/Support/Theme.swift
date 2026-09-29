import SwiftUI

/// Nimble family palette (Nimble Icons style guide v2, §2). All values are
/// sRGB and match the pixels in the shipped app icon.
extension Color {
    /// `#009AD6` — the in-app accent.
    static let nimbleBlue = Color(.sRGB, red: 0 / 255, green: 154 / 255, blue: 214 / 255)
    /// `#006CA5` — the icon gradient's dark end; used for emphasis on accent tints.
    static let nimbleDeepBlue = Color(.sRGB, red: 0 / 255, green: 108 / 255, blue: 165 / 255)
    /// `#FAF8F4` — the icon's foreground mark; text/glyphs on an accent fill.
    static let nimbleCream = Color(.sRGB, red: 250 / 255, green: 248 / 255, blue: 244 / 255)
}

extension ShapeStyle where Self == Color {
    static var nimbleBlue: Color { .nimbleBlue }
    static var nimbleDeepBlue: Color { .nimbleDeepBlue }
    static var nimbleCream: Color { .nimbleCream }
}
