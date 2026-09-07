import Foundation

/// Comparing road names across agencies that disagree about case, spacing and punctuation.
///
/// The county alone writes the same subdivision as `SUN CITY UNIT 4-C` on one layer and
/// `SUN CITY UNIT 4C` on another, and road names arrive variously as `Santa Fe Dr`,
/// `SANTA FE DR` and `Santa Fe Dr                             01`.
public enum RoadName {
    /// A comparison key, not a display string. Separators are dropped rather than collapsed,
    /// because the disagreements are *inside* the token: the county writes the same
    /// subdivision as `SUN CITY UNIT 4-C` on one layer and `SUN CITY UNIT 4C` on another, and
    /// ADOT writes `I 010` where the app displays `I-10`. Collapsing to single spaces leaves
    /// those as different strings; dropping separators makes them the same key while still
    /// keeping `SANTA FE DR` and `SANTA FE CT` apart.
    public static func comparisonKey(_ name: String) -> String {
        String(name.uppercased().unicodeScalars.filter(CharacterSet.alphanumerics.contains))
    }

    /// Exact match after normalization. Deliberately not fuzzy: a road called "Santa Fe Dr"
    /// and one called "Santa Fe Ct" are different roads, and this app's whole value rests on
    /// not confidently attributing the wrong one.
    public static func matches(_ lhs: String?, _ rhs: String?) -> Bool {
        guard let lhs, let rhs else { return false }
        let (left, right) = (comparisonKey(lhs), comparisonKey(rhs))
        return !left.isEmpty && left == right
    }
}
