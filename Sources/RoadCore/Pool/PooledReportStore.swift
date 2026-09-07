import Foundation

/// The shared pool, behind a protocol so everything above it can be tested without a network, an
/// iCloud account or an entitlement.
///
/// The same shape as `FragmentCache`/`MemoryCache` and `Transport`/`FixtureTransport`: one
/// protocol in `RoadCore`, one real implementation that is the only file importing the framework,
/// and one in-memory double for tests.
public protocol PooledReportStore: Sendable {
    func reports(in cells: [PoolCell]) async throws -> [PooledReport]
    func flagCounts(in cells: [PoolCell]) async throws -> [UUID: Int]
    func publish(_ report: PooledReport) async throws
    func retract(id: UUID) async throws
    func flag(id: UUID) async throws
    /// Whether this device can contribute. Reads work regardless — the public database is
    /// readable without an iCloud account, and gating reads on the account check is the mistake
    /// that shows a signed-out user an empty map.
    func canContribute() async -> Bool
}

/// Why the pool could not answer. Surfaced, never swallowed — the app's rule is that a partial
/// answer is normal and a failure is disclosed.
public enum PoolFailure: Error, Sendable, Hashable {
    case offline
    /// Backpressure. `retryAfter` comes from CloudKit's own header when it supplies one.
    case rateLimited(retryAfter: TimeInterval?)
    case notSignedIn
    /// The container or schema is wrong — a developer error, not something the driver can fix.
    case misconfigured(String)
    case unknown(String)

    /// What the map says. Never blames the user for something that is not theirs.
    public var message: String {
        switch self {
        case .offline: "Shared reports are offline."
        case .rateLimited: "Shared reports are busy. Trying again shortly."
        case .notSignedIn: "Sign in to iCloud to add yours."
        case .misconfigured, .unknown: "Shared reports are unavailable."
        }
    }
}

/// How many reports one device may publish in a day.
///
/// With no free text and no identities, volume is the only spam vector left. Twenty is far more
/// than a person driving around files and far less than a script would want.
public enum PoolLimits {
    public static let publishesPerDay = 20
    /// Distinct flags at which a report stops being drawn. Client-side, because there is no
    /// server to act on a flag.
    public static let flagsToHide = 3
}
