import Foundation
import Testing
@testable import RoadCore
@testable import RoadSources

private let fixedNow = Date(timeIntervalSince1970: 1_757_000_000)

private func source(_ transport: FixtureTransport) -> MCDOTRoadInfoSource {
    MCDOTRoadInfoSource(client: ArcGISClient(transport: transport), now: { fixedNow })
}

@Suite("MCDOT source — the county-maintained path")
struct CountyMaintainedTests {
    let query = RoadQuery(latitude: 33.767648, longitude: -112.528617)

    @Test("Derives county ownership from maintained-set membership")
    func ownership() async throws {
        let fragment = try await source(.loneMountain).fetch(query)
        guard case .county(let agency)? = fragment.owner?.value else {
            Issue.record("expected county ownership, got \(String(describing: fragment.owner?.value))")
            return
        }
        #expect(agency.contains("Maricopa County"))
        // Ownership is concluded, never read from a column, and must say so.
        #expect(fragment.owner?.confidence == .derived)
    }

    @Test("An empty municipality layer means unincorporated, not a failed lookup")
    func unincorporated() async throws {
        let fragment = try await source(.loneMountain).fetch(query)
        #expect(fragment.jurisdiction?.value == "Unincorporated Maricopa County")
        #expect(fragment.jurisdiction?.confidence == .derived)
    }

    @Test("Reads segment identity and strips the ordinal from the classification")
    func segment() async throws {
        let fragment = try await source(.loneMountain).fetch(query)
        #expect(fragment.segmentName?.value == "Lone Mountain Rd")
        // Stored as "01 - Local"; the ordinal is an internal sort key, not user-facing.
        #expect(fragment.classification?.value == "Local")
        #expect(fragment.crossStreets?.value == "Crozier Rd to 215th Ave")
        #expect(fragment.supervisorDistrict?.value == 4)
    }

    @Test("Reads the pavement build-up")
    func surface() async throws {
        let surface = try #require(try await source(.loneMountain).fetch(query).surface?.value)
        #expect(surface.type == "Dirt Native")
        #expect(surface.laneCount == 2)
        #expect(surface.widthFeet == 30)
    }

    @Test("Never surfaces FromDate as a build date")
    func doesNotInventAConstructionYear() async throws {
        let fragment = try await source(.loneMountain).fetch(query)
        // FromDate is ArcGIS temporal versioning (ENDPOINTS.md §5.1). The fixture carries a
        // populated value; reading it as a construction date would be the headline bug.
        #expect(fragment.yearLastConstruction == nil)
        #expect(fragment.plattedDate == nil)
    }
}

@Suite("MCDOT source — the city-maintained path")
struct MunicipalTests {
    let query = RoadQuery(latitude: 33.4386, longitude: -112.4118)

    @Test("An empty maintained-roads response resolves to the city, and is not an error")
    func cityOwnership() async throws {
        let fragment = try await source(.goodyear).fetch(query)
        guard case .municipality(let name, let fullName)? = fragment.owner?.value else {
            Issue.record("expected municipal ownership, got \(String(describing: fragment.owner?.value))")
            return
        }
        #expect(name == "GOODYEAR")
        #expect(fullName == "City of Goodyear")
        #expect(fragment.notes.first?.outcome == .contributed)
    }

    @Test("Reports no county segment detail rather than guessing")
    func noSegmentDetail() async throws {
        let fragment = try await source(.goodyear).fetch(query)
        #expect(fragment.segmentName == nil)
        #expect(fragment.surface == nil)
        // But jurisdiction and plat still resolve — partial is the normal case.
        #expect(fragment.jurisdiction?.value == "City of Goodyear")
        #expect(fragment.plat != nil)
    }

    @Test("Surfaces the annexation ordinance and its PDF")
    func annexation() async throws {
        let annexation = try #require(try await source(.goodyear).fetch(query).annexation?.value)
        #expect(annexation.ordinance == "156")
        #expect(annexation.ordinanceURL?.absoluteString.hasSuffix("Goodyear_84-156.pdf") == true)
        #expect(annexation.ordinanceDate != nil)
    }
}

@Suite("MCDOT source — plats and segment selection")
struct PlatAndNearestTests {
    let query = RoadQuery(latitude: 33.5988, longitude: -112.2749)

    @Test("Picks the nearest of several segments in the envelope")
    func nearestSegmentWins() async throws {
        // The fixture holds three candidates; only geometry distinguishes them.
        let fragment = try await source(.sunCity).fetch(query)
        #expect(fragment.segmentName?.value == "Santa Fe Dr")
    }

    @Test("Resolves the recorded plat with a deep link to the document")
    func plat() async throws {
        let plat = try #require(try await source(.sunCity).fetch(query).plat?.value)
        #expect(plat.subdivisionName.isEmpty == false)
        #expect(plat.recorderNumber != nil)
        #expect(plat.recorderURL?.host() == "recorder.maricopa.gov")
        // Layer 3 has no recording date, so the app must not imply one.
        #expect(try await source(.sunCity).fetch(query).plattedDate == nil)
    }

    @Test("Matches the plat spatially, since names differ between layers")
    func platConfidenceIsSpatial() async throws {
        // Layer 2 says "SUN CITY UNIT 4-C", layer 3 says "SUN CITY UNIT 4C" (§5.6).
        let fragment = try await source(.sunCity).fetch(query)
        #expect(fragment.plat?.confidence == .spatial)
    }
}

@Suite("Query construction")
struct QueryFormTests {
    @Test("Every query is an envelope, and never uses the broken distance parameter")
    func envelopeOnly() async throws {
        let transport = FixtureTransport.loneMountain
        _ = try await source(transport).fetch(RoadQuery(latitude: 33.767648, longitude: -112.528617))

        #expect(transport.log.all.count == 3)
        for url in transport.log.all {
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems ?? []
            let names = Set(items.map(\.name))
            // Point + distance/units silently returns zero features on this server (§4).
            #expect(!names.contains("distance"))
            #expect(!names.contains("units"))
            #expect(items.first { $0.name == "geometryType" }?.value == "esriGeometryEnvelope")
            #expect(items.first { $0.name == "inSR" }?.value == "4326")
        }
    }

    @Test("Polygon layers are queried with a pin-sized envelope so intersects means contains")
    func polygonLayersUseTightEnvelope() async throws {
        let transport = FixtureTransport.loneMountain
        _ = try await source(transport).fetch(
            RoadQuery(latitude: 33.767648, longitude: -112.528617, searchRadiusMeters: 150))

        func width(_ url: URL) -> Double {
            let value = URLComponents(url: url, resolvingAgainstBaseURL: false)!
                .queryItems!.first { $0.name == "geometry" }!.value!
            let parts = value.split(separator: ",").compactMap { Double($0) }
            return parts[2] - parts[0]
        }
        let byLayer = Dictionary(uniqueKeysWithValues: transport.log.all.map {
            (FixtureTransport.layerID(of: $0)!, $0)
        })
        // Municipality (7) and subdivision (3) are polygons; maintained roads (2) is a corridor.
        #expect(width(byLayer[7]!) < width(byLayer[2]!))
        #expect(width(byLayer[3]!) < width(byLayer[2]!))
    }
}
