import Foundation

/// Where a single field came from. Every user-visible value carries one so the UI can say
/// "according to X" and link out to the exact query that produced it.
public struct Provenance: Sendable, Hashable, Codable {
    public let sourceID: String
    public let sourceName: String
    /// The precise request URL. Not the service root — the query, so it can be re-run.
    public let url: URL
    public let fetchedAt: Date
    /// True when the value came from a snapshot shipped in the app bundle rather than a
    /// live call. The UI must disclose this, along with `fetchedAt`.
    public let isBundled: Bool

    public init(sourceID: String, sourceName: String, url: URL, fetchedAt: Date, isBundled: Bool = false) {
        self.sourceID = sourceID
        self.sourceName = sourceName
        self.url = url
        self.fetchedAt = fetchedAt
        self.isBundled = isBundled
    }
}

/// How firmly a value is tied to the segment under the pin.
///
/// No two sources share a segment identifier (see docs/ENDPOINTS.md §5.4), so most
/// cross-source values are matched by geometry or by name and must say so.
public enum MatchConfidence: String, Sendable, Hashable, Codable, CaseIterable {
    /// The feature returned for this point, from the authoritative layer for this field.
    case direct
    /// A containing polygon or an overlapping line, matched by geometry.
    case spatial
    /// Matched on a normalized road name, not geometry. Weakest; always disclose.
    case nameMatch
    /// Concluded from other fields rather than read from any one of them — e.g. ownership
    /// derived from municipality plus maintained-set membership.
    case derived
}

/// A value plus the receipt for it. `Attributed` is the only way a field reaches the UI.
public struct Attributed<Value: Sendable & Hashable & Codable>: Sendable, Hashable, Codable {
    public let value: Value
    public let provenance: Provenance
    public let confidence: MatchConfidence

    public init(_ value: Value, provenance: Provenance, confidence: MatchConfidence = .direct) {
        self.value = value
        self.provenance = provenance
        self.confidence = confidence
    }

    public func map<T>(_ transform: (Value) -> T) -> Attributed<T> {
        Attributed<T>(transform(value), provenance: provenance, confidence: confidence)
    }
}

/// What one source did, including when it found nothing or failed. Absence is a normal,
/// reportable outcome here, not an error state — an empty MCDOT result is how the app
/// learns a city maintains the road.
public struct SourceNote: Sendable, Hashable, Codable {
    public enum Outcome: String, Sendable, Hashable, Codable {
        case contributed
        case foundNothing
        case failed
        case skipped
    }

    public let sourceID: String
    public let sourceName: String
    public let outcome: Outcome
    /// Plain-language detail, safe to surface. For `.failed`, the error description.
    public let detail: String?

    public init(sourceID: String, sourceName: String, outcome: Outcome, detail: String? = nil) {
        self.sourceID = sourceID
        self.sourceName = sourceName
        self.outcome = outcome
        self.detail = detail
    }
}
