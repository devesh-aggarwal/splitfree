import SwiftUI

/// Type and spacing scale.
///
/// Money uses the rounded design at a fixed width so digits don't jitter while a
/// balance animates. Everything else uses the system face so Dynamic Type,
/// tracking and every localisation behave exactly as iOS intends.
enum Typography {
    static func money(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    /// The headline balance on the home screen.
    static let displayMoney = money(40, weight: .bold)
    /// Section-level balance, e.g. a group's total.
    static let titleMoney = money(26, weight: .bold)
    /// A row's amount.
    static let rowMoney = money(17, weight: .semibold)
    /// Tiny amounts inside chips.
    static let captionMoney = money(13, weight: .semibold)

    static let screenTitle = Font.system(.largeTitle, design: .default, weight: .bold)
    static let sectionTitle = Font.system(.title3, design: .default, weight: .semibold)
    static let rowTitle = Font.system(.body, design: .default, weight: .medium)
    static let rowSubtitle = Font.system(.subheadline)
    static let caption = Font.system(.caption)
    static let overline = Font.system(.caption2, design: .default, weight: .semibold)
}

enum Metrics {
    static let screenPadding: CGFloat = 20
    static let cardPadding: CGFloat = 16
    static let cardRadius: CGFloat = 20
    static let controlRadius: CGFloat = 14
    static let chipRadius: CGFloat = 11
    static let rowSpacing: CGFloat = 12
    static let sectionSpacing: CGFloat = 26
    static let avatarSmall: CGFloat = 30
    static let avatarMedium: CGFloat = 42
    static let avatarLarge: CGFloat = 76
    static let minTapTarget: CGFloat = 44
}

enum Motion {
    /// The house spring. Fast enough to feel instant, soft enough to feel alive.
    static let snappy = Animation.spring(response: 0.32, dampingFraction: 0.82)
    /// For layout changes that move a lot of pixels.
    static let smooth = Animation.spring(response: 0.42, dampingFraction: 0.88)
    /// For a value ticking over.
    static let quick = Animation.spring(response: 0.24, dampingFraction: 0.9)
    static let gentle = Animation.easeInOut(duration: 0.22)
}

extension Text {
    func moneyStyle(_ font: Font, color: Color) -> some View {
        self.font(font)
            .foregroundStyle(color)
            .monospacedDigit()
            .contentTransition(.numericText())
    }
}
