import SwiftUI

/// Colors used only inside charts.
///
/// The category badge colours elsewhere in the app are tuned to sit behind a
/// white glyph, which makes several of them too close together to serve as
/// chart series - blue and purple are nearly identical under deuteranopia. So
/// charts get their own fixed ramp.
///
/// Both sets were checked against the six palette checks (lightness band,
/// chroma floor, adjacent CVD separation for protan/deutan/tritan, the
/// normal-vision floor, and contrast against the chart surface) and pass in
/// their respective modes. **Assign these in fixed order and never cycle** -
/// past the eighth slot, fold the tail into "Other" rather than inventing a
/// ninth hue that nobody can tell from the first.
enum ChartPalette {

    /// Slot order is fixed. Index 0 is the default single-series colour.
    static let series: [Color] = (0..<8).map { index in
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? darkSteps[index] : lightSteps[index]
        })
    }

    static func slot(_ index: Int) -> Color {
        series[min(max(0, index), series.count - 1)]
    }

    /// The single hue used when a chart shows one series - most of ours do,
    /// because the bars are already labelled with what they are.
    static var primary: Color { series[0] }

    /// Everything past the eighth slot collapses here.
    static let other = Palette.categoryGray

    /// Grid lines and axis rules, kept recessive.
    static let grid = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? #colorLiteral(red: 0.180, green: 0.196, blue: 0.220, alpha: 1)
            : #colorLiteral(red: 0.898, green: 0.910, blue: 0.925, alpha: 1)
    })

    // Validated against surface #fcfcfb, L band 0.43–0.77.
    private static let lightSteps: [UIColor] = [
        #colorLiteral(red: 0.055, green: 0.576, blue: 0.518, alpha: 1), // #0E9384 teal
        #colorLiteral(red: 0.808, green: 0.435, blue: 0.133, alpha: 1), // #CE6F22 orange
        #colorLiteral(red: 0.424, green: 0.361, blue: 0.878, alpha: 1), // #6C5CE0 violet
        #colorLiteral(red: 0.298, green: 0.549, blue: 0.169, alpha: 1), // #4C8C2B green
        #colorLiteral(red: 0.761, green: 0.255, blue: 0.498, alpha: 1), // #C2417F pink
        #colorLiteral(red: 0.176, green: 0.494, blue: 0.886, alpha: 1), // #2D7EE2 blue
        #colorLiteral(red: 0.604, green: 0.482, blue: 0.063, alpha: 1), // #9A7B10 gold
        #colorLiteral(red: 0.659, green: 0.263, blue: 0.478, alpha: 1), // #A8437A mulberry
    ]

    // Validated against surface #16191E, L band 0.48–0.67.
    private static let darkSteps: [UIColor] = [
        #colorLiteral(red: 0.133, green: 0.663, blue: 0.604, alpha: 1), // #22A99A
        #colorLiteral(red: 0.788, green: 0.506, blue: 0.184, alpha: 1), // #C9812F
        #colorLiteral(red: 0.525, green: 0.447, blue: 0.878, alpha: 1), // #8672E0
        #colorLiteral(red: 0.373, green: 0.647, blue: 0.235, alpha: 1), // #5FA53C
        #colorLiteral(red: 0.824, green: 0.349, blue: 0.573, alpha: 1), // #D25992
        #colorLiteral(red: 0.267, green: 0.514, blue: 0.863, alpha: 1), // #4483DC
        #colorLiteral(red: 0.663, green: 0.541, blue: 0.133, alpha: 1), // #A98A22
        #colorLiteral(red: 0.722, green: 0.369, blue: 0.588, alpha: 1), // #B85E96
    ]
}
