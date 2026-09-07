import Foundation

/// One value in a pooled record, in a form that knows nothing about CloudKit.
///
/// The field mapping is expressed over this rather than over `CKRecord` so that everything
/// interesting — the redaction, the rounding, the vocabulary round-trip, the forward-compatible
/// drop of a value a future version publishes — is testable on macOS with no network, no iCloud
/// account and no entitlement. The adapter that turns this into a `CKRecord` is then small enough
/// to have nowhere to hide a bug.
public enum PoolValue: Sendable, Hashable {
    case text(String)
    case number(Double)
    case date(Date)

    public var text: String? { if case .text(let value) = self { value } else { nil } }
    public var number: Double? { if case .number(let value) = self { value } else { nil } }
    public var date: Date? { if case .date(let value) = self { value } else { nil } }
}

/// A road rating as it appears on the shared map.
///
/// Deliberately **not** a `RoadReport`. Three things are dropped on the way out and the type
/// makes that structural rather than a rule somebody has to remember:
///
/// - **The note never leaves the device.** It is the only free text in the app, and keeping it
///   private is most of the moderation problem solved by construction: with two closed
///   vocabularies and no prose, there is nothing objectionable a stranger can publish.
/// - **The coordinate is rounded to ~100 m.** Not the 11 m the lookup cache uses — that rounding
///   exists so one key cannot cover two roads, a correctness rule whose cost is a wrong answer.
///   Here the cost is a disclosure, and 11 m is house-level. 100 m sits inside the app's own
///   150 m idea of "the road you meant" while leaving "which house" unanswerable.
/// - **The time is rounded to the day.** A 100 m location with a millisecond timestamp is a
///   movement trace; enough reports and it is somebody's commute.
///
/// `crossStreets` is dropped too, for the same reason as the coordinate: it re-sharpens the
/// location for free.
public struct PooledReport: Sendable, Hashable, Identifiable {
    public let id: UUID
    public let cell: PoolCell
    public let coordinate: Coordinate
    public let rating: ConditionRating
    public let issue: RoadIssue
    public let countyRating: ConditionRating?
    public let roadName: String?
    public let segmentIdentifier: String?
    public let jurisdiction: String?
    public let maintainedBy: String?
    /// Midnight of the day it was filed, in the reporter's own time zone at the time.
    public let reportedOn: Date

    /// Bumped only when the published shape changes. Promoted CloudKit fields can never be
    /// deleted, so a version tag is the cheapest escape hatch available.
    public static let schemaVersion = 1

    /// ~100 m.
    public static let publishedDecimalPlaces = 3.0

    /// The redaction happens here and only here, so there is one place to get it wrong and one
    /// place the tests have to cover.
    public init(from report: RoadReport, calendar: Calendar = .current) {
        self.id = report.id
        self.coordinate = report.coordinate.rounded(toDecimalPlaces: Self.publishedDecimalPlaces)
        self.cell = PoolCell(self.coordinate)
        self.rating = report.rating
        self.issue = report.issue
        self.countyRating = report.countyRating
        self.roadName = report.roadName
        self.segmentIdentifier = report.segmentIdentifier
        self.jurisdiction = report.jurisdiction
        self.maintainedBy = report.maintainedBy
        self.reportedOn = calendar.startOfDay(for: report.createdAt)
        // `report.note` and `report.crossStreets` are deliberately absent. See the type comment.
    }

    public init(id: UUID, coordinate: Coordinate, rating: ConditionRating, issue: RoadIssue,
                countyRating: ConditionRating? = nil, roadName: String? = nil,
                segmentIdentifier: String? = nil, jurisdiction: String? = nil,
                maintainedBy: String? = nil, reportedOn: Date) {
        self.id = id
        self.coordinate = coordinate
        self.cell = PoolCell(coordinate)
        self.rating = rating
        self.issue = issue
        self.countyRating = countyRating
        self.roadName = roadName
        self.segmentIdentifier = segmentIdentifier
        self.jurisdiction = jurisdiction
        self.maintainedBy = maintainedBy
        self.reportedOn = reportedOn
    }
}

public extension PooledReport {
    enum Field {
        public static let cell = "cell"
        public static let latitude = "latitude"
        public static let longitude = "longitude"
        public static let rating = "rating"
        public static let issue = "issue"
        public static let countyRating = "countyRating"
        public static let roadName = "roadName"
        public static let segmentID = "segmentID"
        public static let jurisdiction = "jurisdiction"
        public static let maintainedBy = "maintainedBy"
        public static let reportedOn = "reportedOn"
        public static let schemaVersion = "schemaVersion"

        /// Exactly what is published. A test asserts the produced keys equal this set, so a field
        /// added to `RoadReport` cannot leak into the pool by being forgotten about.
        public static let all: Set<String> = [
            cell, latitude, longitude, rating, issue, countyRating,
            roadName, segmentID, jurisdiction, maintainedBy, reportedOn, schemaVersion,
        ]
    }

    var fields: [String: PoolValue] {
        var fields: [String: PoolValue] = [
            Field.cell: .text(cell.identifier),
            Field.latitude: .number(coordinate.latitude),
            Field.longitude: .number(coordinate.longitude),
            Field.rating: .text(rating.rawValue),
            Field.issue: .text(issue.rawValue),
            Field.reportedOn: .date(reportedOn),
            Field.schemaVersion: .number(Double(Self.schemaVersion)),
        ]
        countyRating.map { fields[Field.countyRating] = .text($0.rawValue) }
        roadName.map { fields[Field.roadName] = .text($0) }
        segmentIdentifier.map { fields[Field.segmentID] = .text($0) }
        jurisdiction.map { fields[Field.jurisdiction] = .text($0) }
        maintainedBy.map { fields[Field.maintainedBy] = .text($0) }
        return fields
    }

    /// Reads a published record back.
    ///
    /// Returns nil rather than throwing or substituting a default when a vocabulary value is not
    /// one this build knows. A later version that adds a `RoadIssue` case will publish records
    /// this build cannot read, and the right behaviour is to draw what it understands and ignore
    /// the rest — not to crash, and not to silently mis-file an unknown issue as some other one.
    init?(fields: [String: PoolValue], id: UUID) {
        guard let ratingText = fields[Field.rating]?.text,
              let rating = ConditionRating(rawValue: ratingText),
              let issueText = fields[Field.issue]?.text,
              let issue = RoadIssue(rawValue: issueText),
              let latitude = fields[Field.latitude]?.number,
              let longitude = fields[Field.longitude]?.number,
              let reportedOn = fields[Field.reportedOn]?.date
        else { return nil }

        self.init(id: id,
                  coordinate: Coordinate(latitude: latitude, longitude: longitude),
                  rating: rating,
                  issue: issue,
                  // An unknown county rating is dropped rather than failing the whole record:
                  // it is context, not the claim.
                  countyRating: fields[Field.countyRating]?.text
                      .flatMap { ConditionRating(rawValue: $0) },
                  roadName: fields[Field.roadName]?.text,
                  segmentIdentifier: fields[Field.segmentID]?.text,
                  jurisdiction: fields[Field.jurisdiction]?.text,
                  maintainedBy: fields[Field.maintainedBy]?.text,
                  reportedOn: reportedOn)
    }
}
