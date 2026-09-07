import Foundation
import SwiftData
import RoadCore

/// One saved report.
@Model
public final class StoredReport {
    @Attribute(.unique) public var id: UUID
    public var createdAt: Date
    public var latitude: Double
    public var longitude: Double
    public var rating: String
    public var issue: String
    public var note: String?
    public var roadName: String?
    public var crossStreets: String?
    public var maintainedBy: String?
    public var jurisdiction: String?
    public var segmentIdentifier: String?
    public var countyRating: String?

    public init(_ report: RoadReport) {
        id = report.id
        createdAt = report.createdAt
        latitude = report.coordinate.latitude
        longitude = report.coordinate.longitude
        rating = report.rating.rawValue
        issue = report.issue.rawValue
        note = report.note
        roadName = report.roadName
        crossStreets = report.crossStreets
        maintainedBy = report.maintainedBy
        jurisdiction = report.jurisdiction
        segmentIdentifier = report.segmentIdentifier
        countyRating = report.countyRating?.rawValue
    }

    public var report: RoadReport? {
        guard let rating = ConditionRating(rawValue: rating),
              let issue = RoadIssue(rawValue: issue) else { return nil }
        return RoadReport(
            id: id,
            coordinate: Coordinate(latitude: latitude, longitude: longitude),
            createdAt: createdAt, rating: rating, issue: issue, note: note,
            roadName: roadName, crossStreets: crossStreets, maintainedBy: maintainedBy,
            jurisdiction: jurisdiction, segmentIdentifier: segmentIdentifier,
            countyRating: countyRating.flatMap(ConditionRating.init(rawValue:))
        )
    }
}

/// Durable store for the user's own reports.
///
/// Mirrors `SwiftDataFragmentCache` — an actor around a non-`Sendable` `ModelContext` — but
/// nothing here expires. These are the user's observations, not a cache of somebody else's data.
public actor ReportStore {
    private let container: ModelContainer
    private var context: ModelContext

    public init(inMemory: Bool = false) throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: inMemory)
        container = try ModelContainer(for: StoredReport.self, configurations: configuration)
        context = ModelContext(container)
    }

    /// Newest first, which is the order they are read in.
    public func all() -> [RoadReport] {
        let descriptor = FetchDescriptor<StoredReport>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        return ((try? context.fetch(descriptor)) ?? []).compactMap(\.report)
    }

    public func save(_ report: RoadReport) {
        context.insert(StoredReport(report))
        try? context.save()
    }

    public func delete(id: UUID) {
        let descriptor = FetchDescriptor<StoredReport>(predicate: #Predicate { $0.id == id })
        for stored in (try? context.fetch(descriptor)) ?? [] { context.delete(stored) }
        try? context.save()
    }

    public func removeAll() {
        try? context.delete(model: StoredReport.self)
        try? context.save()
    }
}
