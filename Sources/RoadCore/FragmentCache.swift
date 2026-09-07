import Foundation

/// Where a cached answer is filed.
///
/// Keyed by a *rounded* coordinate, not the exact one: two taps a few metres apart are the
/// same question, and without rounding the cache would never hit. Four decimal places is
/// about 11 m — tight enough that a key cannot straddle two streets, loose enough that
/// re-tapping the same spot reuses the answer.
public struct CacheKey: Sendable, Hashable {
    public let latitude: Double
    public let longitude: Double
    public let searchRadiusMeters: Double

    /// Rounding to fewer places would let one key cover two roads, which is the one thing a
    /// cache here must never do.
    static let decimalPlaces = 4.0

    public init(_ query: RoadQuery) {
        let scale = pow(10, Self.decimalPlaces)
        self.latitude = (query.coordinate.latitude * scale).rounded() / scale
        self.longitude = (query.coordinate.longitude * scale).rounded() / scale
        self.searchRadiusMeters = query.searchRadiusMeters
    }

    /// Stable string form, for stores that key on text.
    public var identifier: String {
        String(format: "%.4f,%.4f@%.0f", latitude, longitude, searchRadiusMeters)
    }
}

/// A stored answer and when it was actually obtained.
public struct CachedFragment: Sendable {
    public let fragment: RoadFragment
    public let storedAt: Date

    public init(fragment: RoadFragment, storedAt: Date) {
        self.fragment = fragment
        self.storedAt = storedAt
    }
}

/// Somewhere to keep what a source already answered.
///
/// Deliberately per *source* rather than per record: a source that fails should not poison the
/// others' cached answers, and adding a new source later must not invalidate everything
/// already stored.
public protocol FragmentCache: Sendable {
    func fragment(for sourceID: String, at key: CacheKey) async -> CachedFragment?
    func store(_ fragment: RoadFragment, for sourceID: String, at key: CacheKey) async
    func removeAll() async
}

/// How long a stored answer stays usable.
///
/// Road ownership, declarations and plats change on the order of years, so a long life is
/// safe and the network round trip is the expensive part. The value returned still carries
/// its original `fetchedAt` in provenance, so a stale answer is disclosed rather than hidden.
public enum CachePolicy {
    public static let maximumAge: TimeInterval = 30 * 24 * 60 * 60
}
