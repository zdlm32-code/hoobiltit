import Foundation

/// Runs sources in priority order and merges what they return into one record.
///
/// It never throws. A partial answer is the expected result, so a source that fails or finds
/// nothing is recorded in `notes` and the pipeline continues — one dead endpoint must not
/// cost the user the fields the other sources did resolve.
public struct RoadResolver: Sendable {
    public let sources: [any RoadSource]
    private let cache: (any FragmentCache)?
    private let now: @Sendable () -> Date

    public init(sources: [any RoadSource],
                cache: (any FragmentCache)? = nil,
                now: @escaping @Sendable () -> Date = Date.init) {
        self.sources = sources
        self.cache = cache
        self.now = now
    }

    public func resolve(_ query: RoadQuery) async -> RoadRecord {
        var record = RoadRecord(query: query)
        let key = CacheKey(query)

        for source in sources {
            if let cached = await cachedFragment(for: source, at: key) {
                record.merge(cached)
                continue
            }
            do {
                var fragment = try await source.fetch(query, resolved: record)
                if fragment.notes.isEmpty {
                    fragment.notes = [source.note(fragment.contributesAnything ? .contributed : .foundNothing)]
                }
                // Stored even when it found nothing. "MCDOT does not maintain this road" is
                // a real answer, it costs three requests to re-derive, and it is exactly the
                // outcome a city pin produces every time.
                await cache?.store(fragment, for: source.id, at: key)
                record.merge(fragment)
            } catch {
                // Failures are never cached — the endpoint may simply have been down.
                record.notes.append(
                    source.note(.failed, (error as? LocalizedError)?.errorDescription
                                         ?? String(describing: error))
                )
            }
        }
        return record
    }

    /// A stored answer, if one is present and still within its life.
    ///
    /// The returned fragment keeps the provenance it was stored with, so its `fetchedAt`
    /// still reports when the agency was actually asked. Only the note is rewritten, so the
    /// source log can say the network was not touched.
    private func cachedFragment(for source: any RoadSource, at key: CacheKey) async -> RoadFragment? {
        guard let cache, let entry = await cache.fragment(for: source.id, at: key),
              now().timeIntervalSince(entry.storedAt) < CachePolicy.maximumAge
        else { return nil }

        var fragment = entry.fragment
        let age = Self.ageDescription(from: entry.storedAt, to: now())
        let outcome = fragment.notes.first?.outcome ?? .contributed
        fragment.notes = [source.note(outcome, (fragment.notes.first?.detail).map {
            "\($0) (cached \(age))"
        } ?? "Cached \(age).")]
        return fragment
    }

    static func ageDescription(from storedAt: Date, to now: Date) -> String {
        let seconds = now.timeIntervalSince(storedAt)
        let days = Int(seconds / 86_400)
        if days >= 1 { return days == 1 ? "yesterday" : "\(days) days ago" }
        let hours = Int(seconds / 3_600)
        if hours >= 1 { return hours == 1 ? "an hour ago" : "\(hours) hours ago" }
        return "just now"
    }
}

public extension RoadFragment {
    /// Whether this fragment says anything at all, used both by the resolver's note-writing
    /// and by sources deciding whether they contributed.
    var contributesAnything: Bool {
        segmentName != nil || owner != nil || jurisdiction != nil || classification != nil
            || surface != nil || plat != nil || project != nil || plattedDate != nil
            || lastKnownImprovement != nil || yearLastConstruction != nil
            || yearLastImprovement != nil || routeDesignation != nil
            || declaration != nil || acquisition != nil || bridge != nil || funding != nil
            || parcel != nil || segmentIdentifier != nil || trafficCount != nil
            || works != nil
    }
}
