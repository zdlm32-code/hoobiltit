import Foundation
import Testing
@testable import RoadCore
@testable import RoadStore

private func provenance(_ id: String, at date: Date) -> Provenance {
    Provenance(sourceID: id, sourceName: id, url: URL(string: "https://example.test/\(id)")!,
               fetchedAt: date)
}

/// Counts how often it is actually asked, so a test can prove the network was skipped.
private final class CountingSource: RoadSource, @unchecked Sendable {
    let id: String
    let displayName: String
    private(set) var callCount = 0
    private let build: @Sendable () -> RoadFragment

    init(id: String = "counting", build: @escaping @Sendable () -> RoadFragment) {
        self.id = id
        self.displayName = id
        self.build = build
    }

    func fetch(_ query: RoadQuery, resolved: RoadRecord) async throws -> RoadFragment {
        callCount += 1
        return build()
    }
}

private struct FailingSource: RoadSource {
    let id = "flaky"
    let displayName = "Flaky"
    func fetch(_ query: RoadQuery, resolved: RoadRecord) async throws -> RoadFragment {
        struct Boom: LocalizedError { var errorDescription: String? { "endpoint down" } }
        throw Boom()
    }
}

/// In-memory cache, so resolver behaviour is testable without SwiftData.
private actor MemoryCache: FragmentCache {
    private var entries: [String: CachedFragment] = [:]
    var storeCount = 0

    func fragment(for sourceID: String, at key: CacheKey) async -> CachedFragment? {
        entries["\(sourceID)#\(key.identifier)"]
    }
    func store(_ fragment: RoadFragment, for sourceID: String, at key: CacheKey) async {
        storeCount += 1
        entries["\(sourceID)#\(key.identifier)"] = CachedFragment(fragment: fragment, storedAt: Date())
    }
    func removeAll() async { entries.removeAll() }
    func count() -> Int { entries.count }
}

private let fixedNow = Date(timeIntervalSince1970: 1_757_000_000)

private func namedFragment(_ name: String) -> RoadFragment {
    var fragment = RoadFragment()
    fragment.segmentName = Attributed(name, provenance: provenance("counting", at: fixedNow))
    return fragment
}

@Suite("Cache keys")
struct CacheKeyTests {
    @Test("Two taps a few metres apart are the same question")
    func roundsToTheSameKey() {
        // ~4 m apart.
        let a = CacheKey(RoadQuery(latitude: 33.768612, longitude: -112.525137))
        let b = CacheKey(RoadQuery(latitude: 33.768634, longitude: -112.525119))
        #expect(a == b)
    }

    @Test("Taps far enough apart to be different roads are different keys")
    func separatesDistinctLocations() {
        // ~60 m apart, which at this latitude can be the next street.
        let a = CacheKey(RoadQuery(latitude: 33.767648, longitude: -112.528617))
        let b = CacheKey(RoadQuery(latitude: 33.7692, longitude: -112.5251))
        #expect(a != b)
    }

    @Test("A different search radius is a different question")
    func radiusIsPartOfTheKey() {
        let tight = CacheKey(RoadQuery(latitude: 33.767648, longitude: -112.528617, searchRadiusMeters: 150))
        let wide = CacheKey(RoadQuery(latitude: 33.767648, longitude: -112.528617, searchRadiusMeters: 400))
        #expect(tight != wide)
    }
}

@Suite("Resolver caching")
struct ResolverCacheTests {
    let query = RoadQuery(latitude: 33.767648, longitude: -112.528617)

    @Test("A second lookup of the same place does not touch the network")
    func servesFromCache() async {
        let cache = MemoryCache()
        let source = CountingSource { namedFragment("Lone Mountain Rd") }
        let resolver = RoadResolver(sources: [source], cache: cache, now: { fixedNow })

        let first = await resolver.resolve(query)
        let second = await resolver.resolve(query)

        #expect(source.callCount == 1)
        #expect(first.segmentName?.value == "Lone Mountain Rd")
        #expect(second.segmentName?.value == "Lone Mountain Rd")
    }

    @Test("A cached answer keeps the date the agency was actually asked")
    func provenanceSurvives() async {
        let cache = MemoryCache()
        let resolver = RoadResolver(sources: [CountingSource { namedFragment("Lone Mountain Rd") }],
                                    cache: cache, now: { fixedNow })
        _ = await resolver.resolve(query)
        let second = await resolver.resolve(query)

        // Not the time it was served from the cache — the time it was fetched.
        #expect(second.segmentName?.provenance.fetchedAt == fixedNow)
        // And the source log says the network was skipped.
        #expect(second.notes.first?.detail?.contains("ached") == true)
    }

    @Test("Finding nothing is cached too")
    func cachesNegativeResults() async {
        // A city pin makes MCDOT return nothing every time, at the cost of three requests.
        let cache = MemoryCache()
        let source = CountingSource { RoadFragment() }
        let resolver = RoadResolver(sources: [source], cache: cache, now: { fixedNow })

        _ = await resolver.resolve(query)
        let second = await resolver.resolve(query)

        #expect(source.callCount == 1)
        #expect(second.notes.first?.outcome == .foundNothing)
    }

    @Test("Failures are never cached, because the endpoint may just have been down")
    func doesNotCacheFailures() async {
        let cache = MemoryCache()
        let resolver = RoadResolver(sources: [FailingSource()], cache: cache, now: { fixedNow })

        _ = await resolver.resolve(query)
        _ = await resolver.resolve(query)

        #expect(await cache.count() == 0)
    }

    @Test("An answer past its life is refetched")
    func expires() async {
        let cache = MemoryCache()
        let source = CountingSource { namedFragment("Lone Mountain Rd") }
        // Stored at "now", read back well past the maximum age.
        let resolver = RoadResolver(sources: [source], cache: cache, now: { Date() })
        _ = await resolver.resolve(query)

        let later = RoadResolver(sources: [source], cache: cache,
                                 now: { Date().addingTimeInterval(CachePolicy.maximumAge + 60) })
        _ = await later.resolve(query)

        #expect(source.callCount == 2)
    }

    @Test("Each source is cached separately, so one addition does not invalidate the rest")
    func perSourceEntries() async {
        let cache = MemoryCache()
        let first = CountingSource(id: "first") { namedFragment("A") }
        let second = CountingSource(id: "second") { namedFragment("B") }
        _ = await RoadResolver(sources: [first, second], cache: cache, now: { fixedNow })
            .resolve(query)

        #expect(await cache.count() == 2)
    }
}

@Suite("SwiftData store")
struct SwiftDataCacheTests {
    let query = RoadQuery(latitude: 33.767648, longitude: -112.528617)

    @Test("Round-trips a fragment through the store")
    func roundTrip() async throws {
        let cache = try SwiftDataFragmentCache(inMemory: true)
        var fragment = RoadFragment()
        fragment.segmentName = Attributed("Lone Mountain Rd", provenance: provenance("s", at: fixedNow))
        fragment.owner = Attributed(.countyCourtesy(agency: "MCDOT"),
                                    provenance: provenance("s", at: fixedNow), confidence: .derived)
        fragment.declaration = Attributed(
            RoadDeclaration(roadName: "LONE MOUNTAIN RD", roadFileNumber: "RF A518",
                            effectiveDate: fixedNow),
            provenance: provenance("s", at: fixedNow))

        await cache.store(fragment, for: "s", at: CacheKey(query))
        let restored = try #require(await cache.fragment(for: "s", at: CacheKey(query)))

        #expect(restored.fragment.segmentName?.value == "Lone Mountain Rd")
        #expect(restored.fragment.declaration?.value.roadFileNumber == "RF A518")
        // The enum case and its payload survive encoding.
        guard case .countyCourtesy? = restored.fragment.owner?.value else {
            Issue.record("owner case did not round-trip")
            return
        }
        #expect(restored.fragment.owner?.confidence == .derived)
    }

    @Test("Storing the same key twice replaces rather than accumulates")
    func replacesOnRestore() async throws {
        let cache = try SwiftDataFragmentCache(inMemory: true)
        var first = RoadFragment()
        first.segmentName = Attributed("Old", provenance: provenance("s", at: fixedNow))
        var second = RoadFragment()
        second.segmentName = Attributed("New", provenance: provenance("s", at: fixedNow))

        await cache.store(first, for: "s", at: CacheKey(query))
        await cache.store(second, for: "s", at: CacheKey(query))

        #expect(await cache.fragment(for: "s", at: CacheKey(query))?.fragment.segmentName?.value == "New")
    }

    @Test("Expired entries are dropped, current ones kept")
    func removesExpired() async throws {
        let cache = try SwiftDataFragmentCache(inMemory: true)
        await cache.store(RoadFragment(), for: "s", at: CacheKey(query))

        await cache.removeExpired()
        #expect(await cache.fragment(for: "s", at: CacheKey(query)) != nil)

        await cache.removeExpired(now: Date().addingTimeInterval(CachePolicy.maximumAge + 60))
        #expect(await cache.fragment(for: "s", at: CacheKey(query)) == nil)
    }
}
