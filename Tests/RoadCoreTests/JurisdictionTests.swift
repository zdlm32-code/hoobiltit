import Foundation
import Testing
@testable import RoadCore

private func locator(_ transport: FixtureTransport) -> JurisdictionLocator {
    JurisdictionLocator(client: ArcGISClient(transport: transport))
}

private let houston = Coordinate(latitude: 29.7604, longitude: -95.3698)
private let williamsDrive = Coordinate(latitude: 33.689441, longitude: -112.317668)

private var harrisTransport: FixtureTransport {
    FixtureTransport(["State_County/MapServer/1": .fixture("tiger_county_harris"),
                      "Places_CouSub_ConCity_SubMCD/MapServer/4": .fixture("tiger_place_houston")])
}

@Suite("Jurisdiction lookup")
struct JurisdictionTests {
    @Test("Resolves state, county and place from a coordinate")
    func resolves() async throws {
        let found = try #require(await locator(harrisTransport).locate(houston))
        #expect(found.stateFIPS == "48")
        #expect(found.countyFIPS == "48201")
        #expect(found.countyName == "Harris County")
        #expect(found.placeName == "Houston city")
        #expect(found.description == "Harris County, Texas")
    }

    @Test("Unincorporated land is an answer, not a failure")
    func unincorporated() async throws {
        // Lone Mountain is outside any incorporated place. The place layer returns an empty
        // feature set, and the county still resolves.
        let transport = FixtureTransport([
            "State_County/MapServer/1": .fixture("tiger_county_maricopa"),
            "Places_CouSub_ConCity_SubMCD/MapServer/4": .fixture("tiger_place_empty")])
        let found = try #require(await locator(transport).locate(williamsDrive))
        #expect(found.countyFIPS == "04013")
        #expect(found.placeName == nil)
    }

    @Test("County names are never suffixed, so a parish stays a parish")
    func neverAppendsCounty() {
        // Louisiana has parishes, Alaska has boroughs and census areas, and Virginia has
        // independent cities that are county equivalents. Appending "County" would be wrong
        // in four states.
        let parish = Jurisdiction(stateFIPS: "22", countyFIPS: "22033",
                                  countyName: "East Baton Rouge Parish")
        #expect(parish.description == "East Baton Rouge Parish, Louisiana")
        #expect(!parish.description.contains("Parish County"))
    }

    // MARK: The reason drive mode is affordable

    @Test("A second fix in the same county costs no request at all")
    func containmentAvoidsTheNetwork() async throws {
        let subject = locator(harrisTransport)
        _ = await subject.locate(houston)
        #expect(await subject.requestCount == 1)

        // 3 km away, still inside Harris County. The locator holds the county's boundary and
        // answers by ray casting rather than asking again. Without this, drive mode issues a
        // TIGERweb request every 25 m — the location provider's distanceFilter.
        let downTheRoad = Coordinate(latitude: 29.7874, longitude: -95.3698)
        let again = try #require(await subject.locate(downTheRoad))
        #expect(again.countyFIPS == "48201")
        #expect(await subject.requestCount == 1, "no second request")
    }

    @Test("Leaving the county's boundary triggers exactly one refetch")
    func crossingTheLineRefetches() async throws {
        let subject = locator(harrisTransport)
        _ = await subject.locate(houston)
        // Well outside Harris County's polygon.
        _ = await subject.locate(Coordinate(latitude: 33.689441, longitude: -112.317668))
        #expect(await subject.requestCount == 2)
    }

    @Test("The memo grid is finer than the app's own search radius")
    func memoGrid() {
        // ~110 m at three decimal places, against a 150 m road-search envelope. The memo can
        // therefore never be more wrong about position than the query it serves already is.
        #expect(JurisdictionLocator.memoKey(Coordinate(latitude: 29.76041, longitude: -95.36982))
                == JurisdictionLocator.memoKey(Coordinate(latitude: 29.76044, longitude: -95.36984)))
        #expect(JurisdictionLocator.memoKey(Coordinate(latitude: 29.7604, longitude: -95.3698))
                != JurisdictionLocator.memoKey(Coordinate(latitude: 29.7704, longitude: -95.3698)))
    }

    @Test("Queries are envelopes, like every other query in the app")
    func usesEnvelopes() async throws {
        // TIGERweb also accepts a point-plus-distance form, and adopting it would put a
        // second query shape into the app. Point buffers return zero features with HTTP 200
        // on Caltrans, WSDOT and FDOT; staying envelope-only is what makes that unreachable.
        let transport = harrisTransport
        _ = await locator(transport).locate(houston)
        #expect(!transport.log.all.isEmpty)
        for url in transport.log.all {
            let query = url.query() ?? ""
            #expect(query.contains("esriGeometryEnvelope"))
            #expect(!query.contains("esriSRUnit"), "no point-buffer query may appear")
            // maxAllowableOffset is measured in the units of the *output* reference, so it
            // silently does nothing without outSR — a county boundary comes back 90x larger.
            if query.contains("maxAllowableOffset") { #expect(query.contains("outSR=4326")) }
        }
    }

    @Test("A lookup failure yields nil rather than a wrong county")
    func failureIsSilent() async throws {
        let dead = FixtureTransport(["State_County/MapServer/1": .status(503)])
        #expect(await locator(dead).locate(houston) == nil)
    }
}
