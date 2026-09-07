import Foundation
import SwiftData
import RoadCore

/// One source's answer for one rounded location.
@Model
public final class StoredFragment {
    /// `sourceID` + the rounded coordinate. Unique, so a re-fetch replaces rather than
    /// accumulates.
    @Attribute(.unique) public var key: String
    public var sourceID: String
    /// The encoded `RoadFragment`. Stored as data rather than modelled field-by-field: the
    /// record's shape changes every time a source is added, and a blob does not need a
    /// migration each time.
    ///
    /// Note that a fragment's `notes` are stored along with its values, so the human-readable
    /// summary a source wrote is frozen at fetch time. If that wording changes, cached entries
    /// keep the old text until they expire. Values are unaffected; only the prose is stale.
    public var payload: Data
    public var storedAt: Date

    public init(key: String, sourceID: String, payload: Data, storedAt: Date) {
        self.key = key
        self.sourceID = sourceID
        self.payload = payload
        self.storedAt = storedAt
    }
}

/// SwiftData-backed cache of per-source answers.
///
/// An actor because SwiftData's `ModelContext` is not `Sendable` and the resolver calls this
/// from whatever context it happens to be on.
public actor SwiftDataFragmentCache: FragmentCache {
    private let container: ModelContainer
    private var context: ModelContext
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(inMemory: Bool = false) throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: inMemory)
        container = try ModelContainer(for: StoredFragment.self, configurations: configuration)
        context = ModelContext(container)
    }

    private static func key(sourceID: String, _ key: CacheKey) -> String {
        "\(sourceID)#\(key.identifier)"
    }

    public func fragment(for sourceID: String, at key: CacheKey) async -> CachedFragment? {
        let identifier = Self.key(sourceID: sourceID, key)
        var descriptor = FetchDescriptor<StoredFragment>(
            predicate: #Predicate { $0.key == identifier }
        )
        descriptor.fetchLimit = 1
        guard let stored = try? context.fetch(descriptor).first,
              let fragment = try? decoder.decode(RoadFragment.self, from: stored.payload)
        else { return nil }
        return CachedFragment(fragment: fragment, storedAt: stored.storedAt)
    }

    public func store(_ fragment: RoadFragment, for sourceID: String, at key: CacheKey) async {
        guard let payload = try? encoder.encode(fragment) else { return }
        let identifier = Self.key(sourceID: sourceID, key)

        // Replace any existing entry rather than letting duplicates pile up under one key.
        var descriptor = FetchDescriptor<StoredFragment>(
            predicate: #Predicate { $0.key == identifier }
        )
        descriptor.fetchLimit = 1
        if let existing = try? context.fetch(descriptor).first {
            existing.payload = payload
            existing.storedAt = Date()
        } else {
            context.insert(StoredFragment(key: identifier, sourceID: sourceID,
                                          payload: payload, storedAt: Date()))
        }
        try? context.save()
    }

    public func removeAll() async {
        try? context.delete(model: StoredFragment.self)
        try? context.save()
    }

    /// Drops entries past their usable life. Worth calling at launch: the store is otherwise
    /// unbounded, and a stale answer is worse than no answer once it is old enough.
    public func removeExpired(now: Date = Date()) async {
        let cutoff = now.addingTimeInterval(-CachePolicy.maximumAge)
        try? context.delete(model: StoredFragment.self,
                            where: #Predicate { $0.storedAt < cutoff })
        try? context.save()
    }
}
