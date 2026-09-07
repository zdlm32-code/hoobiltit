import SwiftUI

/// The drive card's colours, in one place so night can be tuned without hunting through a view.
///
/// The night palette is not "the dark one". A card that goes pure white on pure black halates
/// badly on an OLED screen at night — the text blooms and is harder to read than a softer
/// grey — so nothing here is `#FFF` and nothing is `#000`.
public struct DriveCardPalette: Sendable {
    /// Type-erased so day can keep the adaptive system material it already used, while night
    /// pins an explicit colour. A `Color` here would force day off the material and onto a
    /// UIKit-only constant, which the package cannot have — it builds on macOS too.
    public var background: AnyShapeStyle
    public var headline: Color
    public var owner: Color
    public var context: Color
    public var detail: Color
    /// Dates, and nothing else on the card, are coloured. One colour, one meaning.
    public var year: Color
    public var shadow: Double

    public static let day = DriveCardPalette(
        background: AnyShapeStyle(.background.secondary),
        headline: .primary,
        owner: .secondary,
        context: .secondary,
        detail: .secondary.opacity(0.7),
        year: .accentColor,
        shadow: 1)

    public static let night = DriveCardPalette(
        background: AnyShapeStyle(Color(white: 0.07).opacity(0.94)),
        headline: Color(white: 0.90),
        owner: Color(white: 0.74),
        context: Color(white: 0.58),
        detail: Color(white: 0.46),
        // Amber rather than the accent blue: warmer, far less glare in a dark cabin, and it
        // still reads as "this is the number" at a glance.
        year: Color(red: 1.00, green: 0.74, blue: 0.40),
        // A drop shadow on a dark card just muddies its edge.
        shadow: 0)
}
