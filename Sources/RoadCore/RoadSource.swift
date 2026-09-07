import Foundation

/// One swappable data provider.
///
/// A source contributes only the fields it actually knows, and reports what it did — finding
/// nothing is a normal outcome that callers act on, not a failure to swallow.
public protocol RoadSource: Sendable {
    var id: String { get }
    var displayName: String { get }

    /// - Parameter resolved: what earlier sources in the pipeline have already concluded.
    ///   Sources run in priority order precisely so later ones can use this; a project source,
    ///   for instance, needs the segment name to tell "a project on this road" from "a project
    ///   on the next street over". Most sources ignore it.
    func fetch(_ query: RoadQuery, resolved: RoadRecord) async throws -> RoadFragment
}

public extension RoadSource {
    /// Convenience for sources and tests that need no upstream context.
    func fetch(_ query: RoadQuery) async throws -> RoadFragment {
        try await fetch(query, resolved: RoadRecord(query: query))
    }

    func provenance(url: URL, fetchedAt: Date, isBundled: Bool = false) -> Provenance {
        Provenance(sourceID: id, sourceName: displayName, url: url,
                   fetchedAt: fetchedAt, isBundled: isBundled)
    }

    func note(_ outcome: SourceNote.Outcome, _ detail: String? = nil) -> SourceNote {
        SourceNote(sourceID: id, sourceName: displayName, outcome: outcome, detail: detail)
    }
}
