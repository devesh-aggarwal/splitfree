import SwiftUI

/// The app's colour vocabulary.
///
/// Everything is defined in code as a dynamic `UIColor` so light and dark are
/// authored together and can never drift apart. Two signal colours carry almost
/// all the meaning in the product: **positive** (money coming back to you) and
/// **negative** (money you owe). They are deliberately the only saturated colours
/// in a balance context, so a glance at any screen answers "am I up or down?".
enum Palette {

    // MARK: - Brand

    /// Deep spearmint. Used for primary actions and selected state.
    static let accent = dynamic(
        light: #colorLiteral(red: 0.043, green: 0.596, blue: 0.463, alpha: 1),
        dark: #colorLiteral(red: 0.239, green: 0.851, blue: 0.671, alpha: 1)
    )

    /// A softened accent for large fills where full saturation would shout.
    static let accentSoft = dynamic(
        light: #colorLiteral(red: 0.898, green: 0.969, blue: 0.945, alpha: 1),
        dark: #colorLiteral(red: 0.075, green: 0.196, blue: 0.161, alpha: 1)
    )

    static let accentGradient = LinearGradient(
        colors: [
            Color(uiColor: #colorLiteral(red: 0.075, green: 0.702, blue: 0.541, alpha: 1)),
            Color(uiColor: #colorLiteral(red: 0.031, green: 0.545, blue: 0.494, alpha: 1)),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    // MARK: - Balance signals

    /// You are owed money.
    static let positive = dynamic(
        light: #colorLiteral(red: 0.043, green: 0.588, blue: 0.412, alpha: 1),
        dark: #colorLiteral(red: 0.271, green: 0.855, blue: 0.616, alpha: 1)
    )

    static let positiveSoft = dynamic(
        light: #colorLiteral(red: 0.902, green: 0.969, blue: 0.933, alpha: 1),
        dark: #colorLiteral(red: 0.078, green: 0.204, blue: 0.145, alpha: 1)
    )

    /// You owe money.
    static let negative = dynamic(
        light: #colorLiteral(red: 0.851, green: 0.278, blue: 0.259, alpha: 1),
        dark: #colorLiteral(red: 1.0, green: 0.478, blue: 0.435, alpha: 1)
    )

    static let negativeSoft = dynamic(
        light: #colorLiteral(red: 0.996, green: 0.929, blue: 0.925, alpha: 1),
        dark: #colorLiteral(red: 0.235, green: 0.114, blue: 0.106, alpha: 1)
    )

    /// Settled up — intentionally quiet.
    static let neutral = dynamic(
        light: #colorLiteral(red: 0.435, green: 0.463, blue: 0.494, alpha: 1),
        dark: #colorLiteral(red: 0.612, green: 0.639, blue: 0.667, alpha: 1)
    )

    // MARK: - Surfaces

    /// The page behind everything.
    static let background = dynamic(
        light: #colorLiteral(red: 0.973, green: 0.976, blue: 0.980, alpha: 1),
        dark: #colorLiteral(red: 0.043, green: 0.051, blue: 0.063, alpha: 1)
    )

    /// Cards and grouped rows.
    static let surface = dynamic(
        light: #colorLiteral(red: 1.0, green: 1.0, blue: 1.0, alpha: 1),
        dark: #colorLiteral(red: 0.086, green: 0.098, blue: 0.118, alpha: 1)
    )

    /// A card sitting on top of another card.
    static let surfaceRaised = dynamic(
        light: #colorLiteral(red: 1.0, green: 1.0, blue: 1.0, alpha: 1),
        dark: #colorLiteral(red: 0.129, green: 0.145, blue: 0.169, alpha: 1)
    )

    /// Chips, wells, and inset fields.
    static let surfaceSunken = dynamic(
        light: #colorLiteral(red: 0.945, green: 0.953, blue: 0.961, alpha: 1),
        dark: #colorLiteral(red: 0.129, green: 0.145, blue: 0.169, alpha: 1)
    )

    static let separator = dynamic(
        light: #colorLiteral(red: 0.898, green: 0.910, blue: 0.925, alpha: 1),
        dark: #colorLiteral(red: 0.180, green: 0.196, blue: 0.220, alpha: 1)
    )

    static let primaryText = dynamic(
        light: #colorLiteral(red: 0.055, green: 0.075, blue: 0.106, alpha: 1),
        dark: #colorLiteral(red: 0.965, green: 0.973, blue: 0.980, alpha: 1)
    )

    static let secondaryText = dynamic(
        light: #colorLiteral(red: 0.400, green: 0.435, blue: 0.478, alpha: 1),
        dark: #colorLiteral(red: 0.596, green: 0.635, blue: 0.686, alpha: 1)
    )

    static let tertiaryText = dynamic(
        light: #colorLiteral(red: 0.576, green: 0.612, blue: 0.655, alpha: 1),
        dark: #colorLiteral(red: 0.435, green: 0.475, blue: 0.529, alpha: 1)
    )

    // MARK: - Category hues

    static let categoryOrange = dynamic(light: #colorLiteral(red: 0.918, green: 0.518, blue: 0.180, alpha: 1), dark: #colorLiteral(red: 0.980, green: 0.663, blue: 0.365, alpha: 1))
    static let categoryBlue = dynamic(light: #colorLiteral(red: 0.176, green: 0.494, blue: 0.886, alpha: 1), dark: #colorLiteral(red: 0.427, green: 0.667, blue: 0.980, alpha: 1))
    static let categoryPurple = dynamic(light: #colorLiteral(red: 0.494, green: 0.353, blue: 0.882, alpha: 1), dark: #colorLiteral(red: 0.678, green: 0.573, blue: 0.980, alpha: 1))
    static let categoryPink = dynamic(light: #colorLiteral(red: 0.851, green: 0.310, blue: 0.596, alpha: 1), dark: #colorLiteral(red: 0.976, green: 0.502, blue: 0.729, alpha: 1))
    static let categoryTeal = dynamic(light: #colorLiteral(red: 0.043, green: 0.573, blue: 0.588, alpha: 1), dark: #colorLiteral(red: 0.267, green: 0.788, blue: 0.804, alpha: 1))
    static let categoryIndigo = dynamic(light: #colorLiteral(red: 0.298, green: 0.353, blue: 0.788, alpha: 1), dark: #colorLiteral(red: 0.545, green: 0.588, blue: 0.949, alpha: 1))
    static let categoryGray = dynamic(light: #colorLiteral(red: 0.435, green: 0.475, blue: 0.529, alpha: 1), dark: #colorLiteral(red: 0.612, green: 0.647, blue: 0.694, alpha: 1))

    // MARK: - Identity colours

    /// Avatar backgrounds. Chosen for even perceived brightness so no one's
    /// initials are harder to read than anyone else's.
    static let avatarColors: [Color] = [
        Color(uiColor: #colorLiteral(red: 0.176, green: 0.494, blue: 0.886, alpha: 1)),
        Color(uiColor: #colorLiteral(red: 0.043, green: 0.588, blue: 0.412, alpha: 1)),
        Color(uiColor: #colorLiteral(red: 0.851, green: 0.310, blue: 0.596, alpha: 1)),
        Color(uiColor: #colorLiteral(red: 0.918, green: 0.518, blue: 0.180, alpha: 1)),
        Color(uiColor: #colorLiteral(red: 0.494, green: 0.353, blue: 0.882, alpha: 1)),
        Color(uiColor: #colorLiteral(red: 0.043, green: 0.573, blue: 0.588, alpha: 1)),
        Color(uiColor: #colorLiteral(red: 0.796, green: 0.290, blue: 0.286, alpha: 1)),
        Color(uiColor: #colorLiteral(red: 0.298, green: 0.353, blue: 0.788, alpha: 1)),
        Color(uiColor: #colorLiteral(red: 0.502, green: 0.545, blue: 0.161, alpha: 1)),
        Color(uiColor: #colorLiteral(red: 0.663, green: 0.404, blue: 0.192, alpha: 1)),
        Color(uiColor: #colorLiteral(red: 0.180, green: 0.451, blue: 0.596, alpha: 1)),
        Color(uiColor: #colorLiteral(red: 0.639, green: 0.259, blue: 0.796, alpha: 1)),
    ]

    static func avatarColor(_ index: Int) -> Color {
        avatarColors[abs(index) % avatarColors.count]
    }

    /// Group accent colours, matched to the avatar set for visual coherence.
    static let groupColors: [Color] = avatarColors

    static func groupColor(_ index: Int) -> Color {
        groupColors[abs(index) % groupColors.count]
    }

    /// Deterministic colour from a name, so a person keeps their colour even if
    /// their index was never explicitly set.
    static func colorIndex(for text: String) -> Int {
        var hash: UInt64 = 5381
        for byte in text.utf8 { hash = (hash &* 33) &+ UInt64(byte) }
        return Int(hash % UInt64(avatarColors.count))
    }

    // MARK: - Helpers

    private static func dynamic(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }
}

extension Color {
    /// The colour that expresses a signed balance: green up, red down, grey level.
    static func forBalance(_ minorUnits: Int) -> Color {
        if minorUnits > 0 { return Palette.positive }
        if minorUnits < 0 { return Palette.negative }
        return Palette.neutral
    }

    static func softForBalance(_ minorUnits: Int) -> Color {
        if minorUnits > 0 { return Palette.positiveSoft }
        if minorUnits < 0 { return Palette.negativeSoft }
        return Palette.surfaceSunken
    }
}
