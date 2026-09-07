import Foundation

/// What the lock screen and the Dynamic Island show while you drive.
///
/// Deliberately finished strings rather than a `RoadRecord`. The payload crosses a process
/// boundary into the widget extension, so it has to be small, `Codable`, and free of anything
/// the extension should not have to link. It is also `Hashable`, which is what lets the
/// controller skip an update whose rendered text has not changed — on one long road the
/// payload is byte-identical every 250 m, so the frequent checking costs the activity nothing.
public struct DriveActivityState: Codable, Hashable, Sendable {
    public var road: String
    public var context: String?
    public var owner: String?
    /// Pre-joined, e.g. "Built 2009 · Resurfaced 2017".
    public var years: String?
    /// Just the digits, for the Dynamic Island's compact slot where about four characters fit.
    public var compactYear: String?
    public var detail: String?

    public init(card: DriveCardContent) {
        self.road = card.roadName ?? "Looking\u{2026}"
        self.context = card.context
        self.owner = card.owner
        self.years = card.years.isEmpty ? card.dateNote
                                        : card.years.joined(separator: "  \u{00B7}  ")
        // "Built 2009" -> "2009". Falls back to nothing rather than to a word that will not fit.
        self.compactYear = card.years.first.flatMap { first in
            first.split(separator: " ").last.map(String.init).flatMap { Int($0) != nil ? $0 : nil }
        }
        self.detail = card.details.first
    }
}
