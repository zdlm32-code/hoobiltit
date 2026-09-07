import Foundation
import Testing
@testable import RoadCore

private struct StubSource: RoadSource {
    let id: String
    let displayName: String
    let build: @Sendable () throws -> RoadFragment

    func fetch(_ query: RoadQuery, resolved: RoadRecord) async throws -> RoadFragment { try build() }
}

private struct Boom: LocalizedError {
    var errorDescription: String? { "the endpoint fell over" }
}

private func provenance(_ id: String) -> Provenance {
    Provenance(sourceID: id, sourceName: id, url: URL(string: "https://example.test/\(id)")!,
               fetchedAt: Date(timeIntervalSince1970: 0))
}

@Suite("Resolver — graceful degradation")
struct ResolverTests {
    let query = RoadQuery(latitude: 33.767648, longitude: -112.528617)

    @Test("A failing source does not cost the fields other sources resolved")
    func failureIsIsolated() async {
        let failing = StubSource(id: "flaky", displayName: "Flaky") { throw Boom() }
        let working = StubSource(id: "good", displayName: "Good") {
            var f = RoadFragment()
            f.segmentName = Attributed("Lone Mountain Rd", provenance: provenance("good"))
            return f
        }

        let record = await RoadResolver(sources: [failing, working]).resolve(query)

        #expect(record.segmentName?.value == "Lone Mountain Rd")
        #expect(record.failures.count == 1)
        #expect(record.failures.first?.detail == "the endpoint fell over")
    }

    @Test("Every source is reported, including the ones that found nothing")
    func notesCoverAllSources() async {
        let empty = StubSource(id: "empty", displayName: "Empty") { RoadFragment() }
        let record = await RoadResolver(sources: [empty]).resolve(query)

        #expect(record.notes.count == 1)
        #expect(record.notes.first?.outcome == .foundNothing)
        // Finding nothing is a normal outcome, not a failure.
        #expect(record.failures.isEmpty)
        #expect(record.isEmpty)
    }

    @Test("Sources run in priority order and the first answer for a field wins")
    func firstWriterWins() async {
        func named(_ id: String, _ name: String) -> StubSource {
            StubSource(id: id, displayName: id) {
                var f = RoadFragment()
                f.segmentName = Attributed(name, provenance: provenance(id))
                return f
            }
        }
        let record = await RoadResolver(sources: [named("first", "Authoritative Rd"),
                                                  named("second", "Fallback Rd")]).resolve(query)

        #expect(record.segmentName?.value == "Authoritative Rd")
        #expect(record.segmentName?.provenance.sourceID == "first")
    }

    @Test("A later source still fills fields the earlier one left empty")
    func laterSourceFillsGaps() async {
        let owner = StubSource(id: "owner", displayName: "Owner") {
            var f = RoadFragment()
            f.owner = Attributed(.county(agency: "MCDOT"), provenance: provenance("owner"))
            return f
        }
        let project = StubSource(id: "project", displayName: "Project") {
            var f = RoadFragment()
            f.project = Attributed(ProjectReference(projectNumber: "TT0248", title: "Deer Valley Road"),
                                   provenance: provenance("project"), confidence: .spatial)
            return f
        }
        let record = await RoadResolver(sources: [owner, project]).resolve(query)

        #expect(record.owner != nil)
        #expect(record.project?.value.projectNumber == "TT0248")
        #expect(record.project?.confidence == .spatial)
        #expect(record.notes.allSatisfy { $0.outcome == .contributed })
    }
}

@Suite("Client — error surfaces")
struct ClientErrorTests {
    let layer = ArcGISLayer("https://example.test/MapServer", layer: 2)!
    let envelope = Geo.envelope(around: Coordinate(latitude: 33.7, longitude: -112.5), radiusMeters: 150)

    @Test("An ArcGIS error body served with HTTP 200 is raised, not decoded as empty")
    func errorBodyWithOKStatus() async {
        let body = #"{"error":{"code":400,"message":"Unable to complete operation.","details":[]}}"#
        let client = ArcGISClient(transport: FixtureTransport(["MapServer/2": .body(body)]))

        await #expect(throws: ArcGISError.self) {
            _ = try await client.query(layer: layer, envelope: envelope)
        }
    }

    @Test("A non-2xx status is raised")
    func badStatus() async {
        let client = ArcGISClient(transport: FixtureTransport(["MapServer/2": .status(503)]))
        await #expect(throws: ArcGISError.self) {
            _ = try await client.query(layer: layer, envelope: envelope)
        }
    }

    @Test("Unreadable JSON is raised rather than silently yielding no features")
    func malformed() async {
        let client = ArcGISClient(transport: FixtureTransport(["MapServer/2": .body("<html>nope</html>")]))
        await #expect(throws: ArcGISError.self) {
            _ = try await client.query(layer: layer, envelope: envelope)
        }
    }
}
