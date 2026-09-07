import Foundation
import Testing
@testable import RoadCore
@testable import RoadSources

private let fixedNow = Date(timeIntervalSince1970: 1_757_000_000)

private func adot(_ transport: FixtureTransport) -> ADOTStateRouteSource {
    ADOTStateRouteSource(client: ArcGISClient(transport: transport), now: { fixedNow })
}

private func year(_ date: Date) -> Int {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar.component(.year, from: date)
}

@Suite("ADOT source — state routes")
struct ADOTStateRouteTests {
    let query = RoadQuery(latitude: 33.4602, longitude: -112.3756)

    @Test("Picks the ADOT record over its coincident local mirror")
    func prefersADOTNamespace() async throws {
        // ATIS stores I-10 twice: "  I 010" and "07  I 10", identical geometry, 1.7 m from
        // the pin. Taking the nearest outright is a coin flip that can silence this source
        // on the interstate itself.
        let fragment = try await adot(.interstate10).fetch(query)
        #expect(fragment.routeDesignation?.value == "I-10")
        #expect(fragment.classification?.value == "Interstate")
    }

    @Test("Claims state ownership and strips ADOT's value codes")
    func ownership() async throws {
        let fragment = try await adot(.interstate10).fetch(query)
        guard case .state(let agency)? = fragment.owner?.value else {
            Issue.record("expected state ownership, got \(String(describing: fragment.owner?.value))")
            return
        }
        // Stored as "DOT-Arizona Department of Transportation".
        #expect(agency == "Arizona Department of Transportation")
        // And "013-Maricopa".
        #expect(fragment.jurisdiction?.value == "Maricopa County, Arizona")
    }

    @Test("Reads the only genuine construction date in any source")
    func constructionDate() async throws {
        let fragment = try await adot(.interstate10).fetch(query)
        let built = try #require(fragment.yearLastConstruction?.value)
        #expect(year(built) == 2011)
        // Improvement is a separate fact and must not be fused with it.
        #expect(fragment.yearLastImprovement != nil)
    }

    @Test("Reports the project credited with the construction, not the latest resurfacing")
    func projectMatchesConstruction() async throws {
        // Layer 3's comment reads "Per H729601C"; layer 24's most recent entry is H881901C
        // from 2019. Showing the 2019 project beside a 2011 construction date reads as a
        // contradiction, so they occupy different fields.
        let fragment = try await adot(.interstate10).fetch(query)
        #expect(fragment.project?.value.projectNumber == "H729601C")
        #expect(fragment.lastKnownImprovement?.value.projectNumber == "H881901C")
        #expect(fragment.project?.value.projectNumber != fragment.lastKnownImprovement?.value.projectNumber)
    }

    @Test("Upgrades confidence when the typed layer confirms the TRACS from free text")
    func confidenceReflectsHowTheTracsWasFound() async throws {
        // H729601C is scraped from a comment but also present on the typed project layer,
        // so it is a matched record rather than a string pulled out of prose.
        let fragment = try await adot(.interstate10).fetch(query)
        #expect(fragment.project?.confidence == .direct)
    }
}

@Suite("ADOT source — knowing when to stay quiet")
struct ADOTSilenceTests {
    @Test("Says nothing when ATIS knows the road only as a non-ADOT mirror")
    func silentOnLocalStreets() async throws {
        let fragment = try await adot(.goodyearNonADOT)
            .fetch(RoadQuery(latitude: 33.4386, longitude: -112.4118))

        #expect(fragment.owner == nil)
        #expect(fragment.segmentName == nil)
        #expect(fragment.yearLastConstruction == nil)
        #expect(fragment.notes.first?.outcome == .foundNothing)
    }

    @Test("A nearby freeway does not claim a residential pin")
    func doesNotReachForTheNearestStateRoute() async throws {
        // The fixture holds only local streets; an "pick the nearest ADOT route" rule would
        // have to reach outside the coincidence tolerance to answer, and must not.
        let fragment = try await adot(.goodyearNonADOT)
            .fetch(RoadQuery(latitude: 33.4386, longitude: -112.4118))
        #expect(fragment.routeDesignation == nil)
    }
}

@Suite("ADOT source — resolver ordering")
struct ADOTOrderingTests {
    @Test("Running before the county source keeps the interstate out of city hands")
    func adotWinsOwnershipOnStateRoutes() async {
        // The I-10 pin sits inside Goodyear's municipal boundary, so county-only resolution
        // reports "City of Goodyear" for an interstate (ENDPOINTS.md §5.2).
        let query = RoadQuery(latitude: 33.4602, longitude: -112.3756)
        let record = await RoadResolver(sources: [
            adot(.interstate10),
            MCDOTRoadInfoSource(client: ArcGISClient(transport: FixtureTransport.goodyear), now: { fixedNow }),
        ]).resolve(query)

        guard case .state? = record.owner?.value else {
            Issue.record("expected ADOT to claim ownership first, got \(String(describing: record.owner?.value))")
            return
        }
        // The county still contributes what ADOT does not know.
        #expect(record.annexation != nil)
        #expect(record.notes.count == 2)
    }
}

@Suite("ADOT source — not trusting ATIS about other people's roads")
struct ADOTForeignOwnerTests {
    /// A real layer-29 row for MC 85: ATIS records a Maricopa County road as being in
    /// **Apache County**, four hundred kilometres away. The county-code field is only
    /// trustworthy on ADOT's own routes.
    private static let mc85 = """
    {"features":[{"attributes":{
      "RouteId":"  I 010                         ",
      "County":"001-Apache",
      "Ownership":"MMA-Maricopa County DOT (2)",
      "Maintenance":"MMA-Maricopa County DOT (2)",
      "Owner":"MMA"}}]}
    """

    @Test("Claims neither ownership nor county when ATIS says someone else owns the road")
    func staysOutOfItWhenOwnerIsNotADOT() async throws {
        let transport = FixtureTransport([
            "ATIS_prod_gdb/FeatureServer/1": .fixture("atis_1_i10"),
            "ATIS_prod_gdb/FeatureServer/29": .body(Self.mc85),
        ])
        let fragment = try await adot(transport)
            .fetch(RoadQuery(latitude: 33.4602, longitude: -112.3756))

        #expect(fragment.owner == nil)
        // The bad county code must not leak through either.
        #expect(fragment.jurisdiction == nil)
        // The route itself is still ADOT's, so naming it is fine.
        #expect(fragment.routeDesignation?.value == "I-10")
    }
}

@Suite("ADOT value cleaning")
struct ADOTValueTests {
    @Test("Strips the leading code from ADOT's coded values")
    func agencyCodes() {
        #expect(ADOTStateRouteSource.stripAgencyCode("DOT-Arizona Department of Transportation")
                == "Arizona Department of Transportation")
        #expect(ADOTStateRouteSource.stripAgencyCode("013-Maricopa") == "Maricopa")
        #expect(ADOTStateRouteSource.stripAgencyCode("GDY-Goodyear (4)") == "Goodyear (4)")
        #expect(ADOTStateRouteSource.stripAgencyCode("Nothing to strip") == "Nothing to strip")
    }

    @Test("Strips the ordinal from route types and subtypes")
    func ordinals() {
        #expect(ADOTStateRouteSource.stripOrdinal("70-Interstate") == "Interstate")
        #expect(ADOTStateRouteSource.stripOrdinal("74-Ramps") == "Ramps")
        #expect(ADOTStateRouteSource.stripOrdinal("I - Interstate") == "Interstate")
        #expect(ADOTStateRouteSource.stripOrdinal("98-Non-ADOT Rte") == "Non-ADOT Rte")
    }

    @Test("Finds TRACS numbers inside ADOT's free-text notes")
    func tracsExtraction() {
        #expect(ADOTStateRouteSource.tracsNumber(in: "Per H729601C") == "H729601C")
        #expect(ADOTStateRouteSource.tracsNumber(in: "Per H729601C(Cy11)/Cy11Aerial/Photolog") == "H729601C")
        #expect(ADOTStateRouteSource.tracsNumber(in: "Per ROW response from Ray 20120302, Reviewed") == nil)
        #expect(ADOTStateRouteSource.tracsNumber(in: "SS94901C") == "SS94901C")
    }
}

@Suite("ADOT's carriageway bookkeeping stays out of the card")
struct ADOTDisplayNameTests {
    @Test("A driver sees the road's name, not the direction ATIS files it under")
    func stripsNonCardinal() {
        // ATIS names each direction of a divided highway separately, because mileposts run one
        // way. Driving Loop 101 southbound therefore produced "SR-101 nonCard" on screen —
        // the right feature, an unreadable label.
        #expect(ADOTStateRouteSource.displayRouteName("SR-101 nonCard") == "SR-101")
        #expect(ADOTStateRouteSource.displayRouteName("SR-101") == "SR-101")
        #expect(ADOTStateRouteSource.displayRouteName("I-10 nonCard") == "I-10")
    }

    @Test("A frontage road keeps its own identity")
    func doesNotCollapseFrontages() {
        // A frontage road genuinely is a different road from the highway beside it, so this
        // one is expanded rather than dropped — collapsing it would name the wrong road.
        #expect(ADOTStateRouteSource.displayRouteName("SR-101 Front") == "SR-101 Frontage")
        #expect(ADOTStateRouteSource.displayRouteName("SR-101 Front nonCard") == "SR-101 Frontage")
    }

    @Test("Ramps keep their exit, which is how you know which one you are on")
    func keepsRampDetail() {
        #expect(ADOTStateRouteSource.displayRouteName("SR-101 Exit 59 A-Ramp")
                == "SR-101 Exit 59 A-Ramp")
    }

    @Test("The route type reads as English")
    func routeTypeIsReadable() {
        #expect(ADOTStateRouteSource.displayRouteType("91-State Rte non-Card") == "State Route")
        #expect(ADOTStateRouteSource.displayRouteType("90-State Rte") == "State Route")
        #expect(ADOTStateRouteSource.displayRouteType("70-Interstate") == "Interstate")
        #expect(ADOTStateRouteSource.displayRouteType("73-Frontages") == "Frontages")
        // Seen on US-60 heading west through Mesa.
        #expect(ADOTStateRouteSource.displayRouteType("92-US Hwy non-Card") == "US Highway")
        #expect(ADOTStateRouteSource.displayRouteName("US-60 nonCard") == "US-60")
    }

    @Test("Nothing is ever emptied out")
    func neverReturnsBlank() {
        // A name that is *only* the suffix would otherwise render as an empty headline.
        #expect(!ADOTStateRouteSource.displayRouteName("nonCard").isEmpty)
        #expect(!ADOTStateRouteSource.displayRouteType("91-").isEmpty)
    }
}
