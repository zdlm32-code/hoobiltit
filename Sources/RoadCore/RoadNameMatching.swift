import Foundation

/// Comparing road names across agencies that disagree about case, spacing, punctuation and
/// abbreviation.
///
/// The county alone writes the same subdivision as `SUN CITY UNIT 4-C` on one layer and
/// `SUN CITY UNIT 4C` on another, and road names arrive variously as `Santa Fe Dr`,
/// `SANTA FE DR` and `Santa Fe Dr                             01`.
public enum RoadName {
    /// Street-type suffixes, mapped to one spelling each.
    ///
    /// Different agencies abbreviate differently and it silently costs answers. Census TIGER
    /// writes `Congress Ave`; FHWA's National Highway System writes `CONGRESS AV` for the same
    /// road, so a strict comparison rejected it and the app threw away the ownership and traffic
    /// the NHS had for every road whose suffix happened to be spelled differently.
    ///
    /// Every entry maps a spelling to its own type and never across types: `DR` and `CT` stay
    /// distinct, because "Santa Fe Dr" and "Santa Fe Ct" are different roads and the whole value
    /// of this app rests on not confidently naming the wrong one.
    static let streetTypes: [String: String] = [
        "AV": "AVE", "AVE": "AVE", "AVEN": "AVE", "AVENUE": "AVE",
        "ST": "ST", "STR": "ST", "STREET": "ST",
        "DR": "DR", "DRV": "DR", "DRIVE": "DR",
        "RD": "RD", "ROAD": "RD",
        "CT": "CT", "COURT": "CT",
        "BLVD": "BLVD", "BLV": "BLVD", "BOULEVARD": "BLVD",
        "LN": "LN", "LANE": "LN",
        "PL": "PL", "PLACE": "PL",
        "PKWY": "PKWY", "PKY": "PKWY", "PARKWAY": "PKWY",
        "HWY": "HWY", "HIGHWAY": "HWY",
        "CIR": "CIR", "CIRCLE": "CIR",
        "TRL": "TRL", "TRAIL": "TRL",
        "TER": "TER", "TERR": "TER", "TERRACE": "TER",
        "SQ": "SQ", "SQUARE": "SQ",
        "EXPY": "EXPY", "EXPWY": "EXPY", "EXPRESSWAY": "EXPY",
        "FWY": "FWY", "FREEWAY": "FWY",
        "PLZ": "PLZ", "PLAZA": "PLZ",
        "XING": "XING", "CROSSING": "XING",
        "WAY": "WAY", "LOOP": "LOOP", "PIKE": "PIKE", "RUN": "RUN", "ROW": "ROW",
    ]

    /// Compass prefixes and suffixes, which is a different problem — see `matches`.
    static let directions: Set<String> = [
        "N", "S", "E", "W", "NE", "NW", "SE", "SW",
        "NORTH", "SOUTH", "EAST", "WEST",
        "NORTHEAST", "NORTHWEST", "SOUTHEAST", "SOUTHWEST",
    ]

    /// A comparison key, not a display string.
    ///
    /// Separators are dropped rather than collapsed, because the disagreements are *inside* the
    /// token: the county writes the same subdivision as `SUN CITY UNIT 4-C` on one layer and
    /// `SUN CITY UNIT 4C` on another, and ADOT writes `I 010` where the app displays `I-10`.
    /// The street type is normalised to one spelling so `Congress Ave` and `CONGRESS AV` agree.
    ///
    /// Directions are **kept**: this key is also road identity — it groups the drive log and
    /// decides when drive mode re-resolves — and `N 7th St` and `S 7th St` are two roads.
    public static func comparisonKey(_ name: String) -> String {
        tokens(of: name).joined()
    }

    static func tokens(of name: String) -> [String] {
        var tokens = name.uppercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
        // Only the last token, so a road actually called "Court St" keeps its name.
        if let last = tokens.last, let canonical = streetTypes[last], tokens.count > 1 {
            tokens[tokens.count - 1] = canonical
        }
        return tokens
    }

    /// Exact match after normalization, with one deliberate relaxation.
    ///
    /// Deliberately not fuzzy: a road called "Santa Fe Dr" and one called "Santa Fe Ct" are
    /// different roads, and this app's whole value rests on not confidently attributing the
    /// wrong one.
    ///
    /// The relaxation is compass prefixes, and it is asymmetric on purpose. TIGER writes
    /// `W 1st St` where the NHS writes `1ST ST` — the same road, named more and less
    /// specifically — so a difference is allowed **only when one side has no direction at all**.
    /// When both carry one and they disagree, they stay different roads, because `N 7th St` and
    /// `S 7th St` genuinely are.
    public static func matches(_ lhs: String?, _ rhs: String?) -> Bool {
        guard let lhs, let rhs else { return false }
        let (left, right) = (tokens(of: lhs), tokens(of: rhs))
        guard !left.isEmpty, !right.isEmpty else { return false }
        // Joined, not compared token by token: the agencies disagree about separators *inside* a
        // token too, so "SUN CITY UNIT 4-C" and "SUN CITY UNIT 4C" tokenise differently and are
        // the same name.
        if left.joined() == right.joined() { return true }

        let leftDirection = direction(in: left)
        let rightDirection = direction(in: right)
        // Both said which way, and disagreed. Two roads.
        guard leftDirection == nil || rightDirection == nil else { return false }
        // Neither said, so there is nothing to relax and they simply differ.
        guard leftDirection != nil || rightDirection != nil else { return false }
        return stripDirections(left).joined() == stripDirections(right).joined()
    }

    /// The compass token, if the name carries one at either end.
    static func direction(in tokens: [String]) -> String? {
        if let first = tokens.first, directions.contains(first), tokens.count > 1 { return first }
        if let last = tokens.last, directions.contains(last), tokens.count > 1 { return last }
        return nil
    }

    static func stripDirections(_ tokens: [String]) -> [String] {
        var tokens = tokens
        if tokens.count > 1, let first = tokens.first, directions.contains(first) {
            tokens.removeFirst()
        }
        if tokens.count > 1, let last = tokens.last, directions.contains(last) {
            tokens.removeLast()
        }
        return tokens
    }
}
