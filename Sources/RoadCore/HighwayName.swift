import Foundation

/// Recognising a highway by its name.
///
/// Two questions turn on it that no source answers directly. Is an *unnamed* National Highway
/// System segment the road under the pin? And can "the pin is inside Phoenix, so Phoenix owns
/// it" possibly be right? Both came up on Loop 101: ADOT's own layer has a gap where the ramp
/// meets the main line, the Census names the road "Pima Fwy", the NHS segment there carries no
/// name at all — only the sign `S101` — and the city inference filled the silence.
public enum HighwayName {
    /// A numbered route.
    public struct Route: Hashable, Sendable {
        public enum System: Hashable, Sendable { case interstate, us, state }
        public let system: System
        public let number: Int

        public init(system: System, number: Int) {
            self.system = system
            self.number = number
        }
    }

    /// Reads the NHS's compact signs ("I10", "U60", "S101") and the spelled-out forms the
    /// agencies use ("I-10", "Interstate 10", "US 60", "SR-101", "State Rte 101", "Loop 101").
    ///
    /// A bare `S` or `U` counts only in the compact sign form, with nothing between letter and
    /// number. Spelled out, "S 7 Ave" is a street on the south side of town.
    public static func route(_ name: String) -> Route? {
        let text = name.uppercased().trimmingCharacters(in: .whitespaces)
        for (system, pattern) in patterns {
            guard let regex = try? Regex(pattern),
                  let match = try? regex.prefixMatch(in: text),
                  let digits = match.output[1].substring,
                  let number = Int(digits)
            else { continue }
            return Route(system: system, number: number)
        }
        return nil
    }

    private static let patterns: [(Route.System, String)] = [
        (.interstate, #"^(?:I|IH|INTERSTATE)[\s-]*(\d{1,3})(?![0-9A-Z])"#),
        (.us, #"^(?:US|U\.S\.)(?:\s*(?:HWY|HIGHWAY|RTE|ROUTE))?[\s-]*(\d{1,3})(?![0-9A-Z])"#),
        (.us, #"^U(\d{1,3})$"#),
        (.state, #"^(?:SR|SH|AZ|LOOP|STATE\s+(?:RTE|ROUTE|HWY|HIGHWAY))[\s-]*(\d{1,4})(?![0-9A-Z])"#),
        (.state, #"^S(\d{1,4})$"#),
    ]

    /// Whether two spellings name the same numbered route: `S101` and "State Rte 101".
    ///
    /// A frontage road is never its route, though it carries the number: "SR 101 Front" runs
    /// beside Loop 101, ADOT's own layer declines to claim it, and matching it to the main line
    /// handed it the freeway's owner and its 160,835 vehicles a day.
    public static func sameRoute(_ lhs: String?, _ rhs: String?) -> Bool {
        guard let lhs, let rhs, !isBesideTheRoute(lhs), !isBesideTheRoute(rhs),
              let left = route(lhs), let right = route(rhs) else { return false }
        return left == right
    }

    /// A freeway or a numbered route, by its own name: "Pima Fwy", "Black Canyon Freeway",
    /// "I-17", "SR-101". Deliberately not "Expressway" or "Parkway" — a city can own either,
    /// and Phoenix owns the Sky Harbor one.
    public static func isHighway(_ name: String?) -> Bool {
        guard let name, !isBesideTheRoute(name) else { return false }
        if route(name) != nil { return true }
        return words(of: name).contains { ["FWY", "FREEWAY", "INTERSTATE"].contains($0) }
    }

    /// Whether two names share a base once the road type is set aside: "PIMA RD" and
    /// "Pima Fwy". The NHS names some freeway segments after the arterial alignment they follow,
    /// so the type word disagrees while the road is the same.
    public static func sameStem(_ lhs: String?, _ rhs: String?) -> Bool {
        guard let lhs, let rhs else { return false }
        let (left, right) = (stem(lhs), stem(rhs))
        return !left.isEmpty && left == right
    }

    private static func stem(_ name: String) -> [Substring] {
        var words = words(of: name)
        while let last = words.last, typeWords.contains(String(last)) { words.removeLast() }
        return words
    }

    private static let typeWords: Set<String> = [
        "FWY", "FREEWAY", "RD", "ROAD", "HWY", "HIGHWAY", "PKWY", "PARKWAY", "EXPY",
        "EXPRESSWAY", "BLVD", "BOULEVARD", "AVE", "AVENUE", "ST", "STREET", "DR", "DRIVE",
    ]

    /// A ramp or exit: "SR-101 Exit 37 E1-Ramp". On the route for ownership, not for traffic —
    /// the main line's 180,000 vehicles a day are not the ramp's.
    public static func isRamp(_ name: String?) -> Bool {
        guard let name, !isCrossing(name) else { return false }
        return words(of: name).contains { ["RAMP", "EXIT"].contains($0) }
    }

    /// The local road across an interchange: "I-10 Exit 125 Crossing", which ADOT's own layer
    /// names and classes as a minor ramp but declines to claim — the next stretch of the same
    /// road is Sarival Ave, Goodyear's. It carries the route's number and the word "Exit", and
    /// is neither the route nor a ramp onto it.
    public static func isCrossing(_ name: String?) -> Bool {
        guard let name else { return false }
        return words(of: name).contains { ["CROSSING", "XING"].contains($0) }
    }

    /// Frontage roads and crossings: named for the route, and not the route.
    public static func isBesideTheRoute(_ name: String?) -> Bool {
        isFrontage(name) || isCrossing(name)
    }

    /// A frontage road: "SR 101 Front", "I-10 Frontage Rd". Local more often than not, and
    /// never the main line, whatever number it carries.
    public static func isFrontage(_ name: String?) -> Bool {
        guard let name else { return false }
        return words(of: name).contains { ["FRONT", "FRONTAGE"].contains($0) }
    }

    /// A canal service road: "Central Arizona Project Csr". Maintained by the canal's operator
    /// — CAP, SRP, the Roosevelt Irrigation District — and not by the city it runs through.
    public static func isCanalServiceRoad(_ name: String?) -> Bool {
        guard let name else { return false }
        return words(of: name).last == "CSR"
    }

    /// Roads that city limits say nothing about: a city does not own the freeway or the canal
    /// road that crosses it.
    public static func isNotTheCitys(_ name: String?) -> Bool {
        isHighway(name) || isCanalServiceRoad(name)
    }

    private static func words(of name: String) -> [Substring] {
        name.uppercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber })
    }
}
