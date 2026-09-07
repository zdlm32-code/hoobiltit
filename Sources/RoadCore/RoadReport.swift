import Foundation

/// Road condition, on the county's own five-point scale.
///
/// Deliberately the same wording MCDOT publishes as `EstimatedOcr`, so a user's reading sits
/// beside the county's on the same road. A five-star scale would be easier to tap and
/// comparable to nothing.
public enum ConditionRating: String, Sendable, Hashable, Codable, CaseIterable, Comparable {
    case veryPoor = "Very Poor"
    case poor = "Poor"
    case fair = "Fair"
    case good = "Good"
    case veryGood = "Very Good"

    public var label: String { rawValue }

    /// Worst first, which is the order that matters when scanning a list of complaints.
    private var rank: Int {
        switch self {
        case .veryPoor: 0
        case .poor: 1
        case .fair: 2
        case .good: 3
        case .veryGood: 4
        }
    }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rank < rhs.rank }

    /// Parses the county's value. Their strings are exactly these, but casing and stray
    /// whitespace vary across layers, as everything else in this data does.
    public static func county(_ value: String?) -> ConditionRating? {
        guard let value else { return nil }
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return allCases.first { $0.rawValue.lowercased() == cleaned }
    }

    /// How this reading compares with the county's, in words. Nil when they agree or when the
    /// county publishes nothing for the road — most city streets.
    public static func disagreement(mine: ConditionRating,
                                    county: ConditionRating?) -> String? {
        guard let county, county != mine else { return nil }
        let steps = abs(mine.rank - county.rank)
        let direction = mine < county ? "worse" : "better"
        let plural = steps == 1 ? "step" : "steps"
        return "The county rates this \(county.label). You rated it \(steps) \(plural) \(direction)."
    }
}

/// What is wrong with the road.
///
/// Each case carries the category the county files that work under, read from the MIP layers:
/// Bridge, Cattle Guard, Concrete, Drainage, Dust Mitigation, Guardrail, Intersection,
/// Pavement Preservation. An export tagged with the county's own category is legible to the
/// people who would act on it; free text is not.
public enum RoadIssue: String, Sendable, Hashable, Codable, CaseIterable {
    case pavement
    case drainage
    case concrete
    case guardrail
    case intersection
    case dust
    case bridge
    case cattleGuard
    case other

    public var label: String {
        switch self {
        case .pavement: "Pavement — potholes, cracking, rutting"
        case .drainage: "Drainage — ponding or flooding"
        case .concrete: "Sidewalk, curb or gutter"
        case .guardrail: "Guardrail or barrier"
        case .intersection: "Intersection or signals"
        case .dust: "Dust or unpaved surface"
        case .bridge: "Bridge or structure"
        case .cattleGuard: "Cattle guard"
        case .other: "Something else"
        }
    }

    public var shortLabel: String {
        switch self {
        case .pavement: "Pavement"
        case .drainage: "Drainage"
        case .concrete: "Concrete"
        case .guardrail: "Guardrail"
        case .intersection: "Intersection"
        case .dust: "Dust"
        case .bridge: "Bridge"
        case .cattleGuard: "Cattle guard"
        case .other: "Other"
        }
    }

    public var symbol: String {
        switch self {
        case .pavement: "road.lanes"
        case .drainage: "drop"
        case .concrete: "square.split.bottomrightquarter"
        case .guardrail: "shield"
        case .intersection: "arrow.triangle.branch"
        case .dust: "wind"
        case .bridge: "arrow.left.and.right"
        case .cattleGuard: "square.grid.3x1.below.line.grid.1x2"
        case .other: "questionmark.circle"
        }
    }

    /// The county's own maintenance category, or nil where they have none for it.
    public var countyCategory: String? {
        switch self {
        case .pavement: "Pavement Preservation"
        case .drainage: "Drainage"
        case .concrete: "Concrete"
        case .guardrail: "Guardrail"
        case .intersection: "Intersection"
        case .dust: "Dust Mitigation"
        case .bridge: "Bridge"
        case .cattleGuard: "Cattle Guard"
        case .other: nil
        }
    }
}

/// One report, pinned to where it was seen.
///
/// The road identity is a *snapshot* copied in at the time, not a live lookup. Re-resolving
/// later could quietly change which road a report is about, and would make the list useless
/// without a signal.
public struct RoadReport: Sendable, Hashable, Codable, Identifiable {
    public let id: UUID
    public let coordinate: Coordinate
    public let createdAt: Date
    public let rating: ConditionRating
    public let issue: RoadIssue
    public let note: String?

    public let roadName: String?
    public let crossStreets: String?
    public let maintainedBy: String?
    public let jurisdiction: String?
    /// MCDOT's stable per-segment identifier, so reports on one stretch group without relying
    /// on name matching.
    public let segmentIdentifier: String?
    /// The county's own rating at the time, which is what the comparison is drawn against.
    public let countyRating: ConditionRating?

    public init(id: UUID = UUID(), coordinate: Coordinate, createdAt: Date = Date(),
                rating: ConditionRating, issue: RoadIssue, note: String? = nil,
                roadName: String? = nil, crossStreets: String? = nil,
                maintainedBy: String? = nil, jurisdiction: String? = nil,
                segmentIdentifier: String? = nil, countyRating: ConditionRating? = nil) {
        self.id = id
        self.coordinate = coordinate
        self.createdAt = createdAt
        self.rating = rating
        self.issue = issue
        self.note = note
        self.roadName = roadName
        self.crossStreets = crossStreets
        self.maintainedBy = maintainedBy
        self.jurisdiction = jurisdiction
        self.segmentIdentifier = segmentIdentifier
        self.countyRating = countyRating
    }

    public var disagreesWithCounty: String? {
        ConditionRating.disagreement(mine: rating, county: countyRating)
    }
}

/// CSV generation.
///
/// Quoting is the part of a CSV that fails silently: one comma or quotation mark in a note
/// shifts every column after it and nothing complains. Kept as a pure function with tests
/// rather than string interpolation at the call site.
public enum ReportCSV {
    public static let columns = [
        "Date", "Latitude", "Longitude", "Rating", "County rating", "Issue",
        "County category", "Road", "Between", "Maintained by", "Jurisdiction",
        "Segment ID", "Note",
    ]

    /// RFC 4180: wrap in quotes when the value contains a comma, quote or newline, and double
    /// any quotes inside.
    public static func escape(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "" }
        guard value.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" })
        else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    public static func row(_ report: RoadReport) -> String {
        let formatter = ISO8601DateFormatter()
        return [
            escape(formatter.string(from: report.createdAt)),
            escape(String(format: "%.6f", report.coordinate.latitude)),
            escape(String(format: "%.6f", report.coordinate.longitude)),
            escape(report.rating.label),
            escape(report.countyRating?.label),
            escape(report.issue.shortLabel),
            escape(report.issue.countyCategory),
            escape(report.roadName),
            escape(report.crossStreets),
            escape(report.maintainedBy),
            escape(report.jurisdiction),
            escape(report.segmentIdentifier),
            escape(report.note),
        ].joined(separator: ",")
    }

    public static func document(_ reports: [RoadReport]) -> String {
        ([columns.joined(separator: ",")] + reports.map(row)).joined(separator: "\n") + "\n"
    }
}
