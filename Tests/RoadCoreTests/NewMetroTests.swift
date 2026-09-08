import Foundation
import Testing
@testable import RoadCore
@testable import RoadSources

private let fixedNow = Date(timeIntervalSince1970: 1_757_000_000)

@Suite("Massachusetts and Denver")
struct NewMetroTests {
    let charlesRiverSq = RoadQuery(latitude: 42.359692, longitude: -71.071403)
    let boardwalkDrive = RoadQuery(latitude: 42.679299, longitude: -71.187802)
    let pecos = RoadQuery(latitude: 39.785451, longitude: -105.006423)

    private func massdot(_ fixture: String) -> FlatInventorySource {
        FlatInventorySource(profile: CoverageCatalog.bundled.profile(forState: "25")!,
                            client: ArcGISClient(transport: FixtureTransport([
                                "MassDOTRoads_gdb/FeatureServer/0": .fixture(fixture)])),
                            now: { fixedNow })!
    }
    private var denver: FlatInventorySource {
        FlatInventorySource(profile: CoverageCatalog.bundled.profile(forPlace: "0820000")!,
                            client: ArcGISClient(transport: FixtureTransport([
                                "Denver_Pavement_Treatments/FeatureServer/428": .fixture("denver_pecos")])),
                            now: { fixedNow })!
    }

    // MARK: - Massachusetts

    @Test("A street nobody has accepted says so, rather than guessing at a city")
    func unaccepted() async throws {
        let fragment = try await massdot("massdot_unaccepted").fetch(charlesRiverSq)
        #expect(fragment.segmentName?.value == "CHARLES RIVER SQUARE")
        // 120,329 segments — a fifth of Massachusetts — are `0`, "unaccepted by city or town".
        // Somebody may plough it, but no public body has taken it on, and the developer who
        // laid it is the real answer to who built it.
        #expect(fragment.owner?.value == .notPubliclyMaintained)
    }

    @Test("A private road is private")
    func privateRoad() async throws {
        let fragment = try await massdot("massdot_private").fetch(boardwalkDrive)
        #expect(fragment.segmentName?.value == "BOARDWALK DRIVE")
        #expect(fragment.owner?.value == .privateOwner)
    }

    @Test("MassDOT's published domain covers eighteen owners, not four")
    func jurisdictionDomain() {
        #expect(CodeTables.owner(massdot: "1")
                == .state(agency: "Massachusetts Department of Transportation"))
        #expect(CodeTables.owner(massdot: "0") == .notPubliclyMaintained)
        #expect(CodeTables.owner(massdot: "H") == .privateOwner)
        // The unusually complete part: separate values for the conservation department, the
        // port authority, four branches of the military and the BIA.
        #expect(CodeTables.owner(massdot: "3")
                == .state(agency: "Department of Conservation and Recreation"))
        #expect(CodeTables.owner(massdot: "5")
                == .state(agency: "Massachusetts Port Authority"))
        if case .federal = CodeTables.owner(massdot: "J") {} else { Issue.record("J is the Navy") }
        if case .tribal = CodeTables.owner(massdot: "G") {} else { Issue.record("G is the BIA") }
        #expect(CodeTables.owner(massdot: "Z") == nil)
        #expect(CodeTables.owner(massdot: nil) == nil)
    }

    @Test("A surface code is expanded into the agency's own words")
    func surfaceCodes() throws {
        // Stored as a bare integer. `6` covers 185,085 segments and the published domain calls
        // it a bituminous concrete road; shown raw it is the digit 6.
        let profile = try #require(CoverageCatalog.bundled.profile(forState: "25"))
        let names = try #require(profile.fields?.surfaceNames)
        #expect(names["6"] == "Bituminous concrete")
        #expect(names["7"] == "Portland cement concrete")
        #expect(names["2"] == "Gravel or stone")
    }

    @Test("Every field the profile asks for exists on the layer")
    func outFieldsAreReal() throws {
        // Boston's clipped copy of this schema truncates STREETNAME to STREET_NAM. Naming a
        // field the layer does not have makes the service reject the *whole* query with a 400,
        // so the source failed outright rather than merely missing a name.
        let profile = try #require(CoverageCatalog.bundled.profile(forState: "25"))
        let requested = try #require(profile.outFields)
        #expect(requested.contains("STREET_NAME"))
        #expect(!requested.contains("STREET_NAM"))
    }

    // MARK: - Denver

    @Test("Denver names the body that maintains the street, not just the city")
    func denverOwner() async throws {
        let fragment = try await denver.fetch(pecos)
        #expect(fragment.segmentName?.value == "N PECOS ST")
        #expect(fragment.owner?.value == .municipality(name: "City and County of Denver",
                                                       fullName: "City and County of Denver"))
    }

    @Test("An abbreviated treatment is expanded, and dated")
    func denverTreatment() async throws {
        let fragment = try await denver.fetch(pecos)
        let work = try #require(fragment.works?.value.first)
        // Stored as `HIPR`, which reads as noise on a card.
        #expect(work.title == "Hot in-place recycling")
        #expect(work.kind == .maintained)
        #expect(CalendarDate.year(try #require(work.letDate)) == 2017)
    }

    @Test("The treatment classifier is shared, because the words are")
    func sharedClassifier() {
        // Dallas writes "Street Reconstruction" and Denver writes "Reconstruct"; the same
        // words decide the same way, so one table serves both.
        #expect(CodeTables.workKind(pavementTreatment: "Reconstruct") == .built)
        #expect(CodeTables.workKind(pavementTreatment: "Full Depth Paving") == .built)
        #expect(CodeTables.workKind(pavementTreatment: "Street Reconstruction") == .built)
        #expect(CodeTables.workKind(pavementTreatment: "Chip Seal") == .maintained)
        #expect(CodeTables.workKind(pavementTreatment: "Mill and Overlay") == .maintained)
        #expect(CodeTables.workKind(pavementTreatment: "Slurry Seal") == .maintained)
        #expect(CodeTables.workKind(pavementTreatment: "None") == nil)
    }
}

@Suite("Virginia — where the locality is not the owner")
struct VirginiaTests {
    let arlingtonStreet = RoadQuery(latitude: 38.888146, longitude: -77.137878)
    let secondaryRoute = RoadQuery(latitude: 37.824565, longitude: -75.664414)

    private func vdot(_ fixture: String) -> FlatInventorySource {
        FlatInventorySource(profile: CoverageCatalog.bundled.profile(forState: "51")!,
                            client: ArcGISClient(transport: FixtureTransport([
                                "LRS_Route_Master/FeatureServer/0": .fixture(fixture)])),
                            now: { Date(timeIntervalSince1970: 1_757_000_000) })!
    }

    @Test("A locality that really does maintain its own streets is credited")
    func localityStreet() async throws {
        let fragment = try await vdot("vdot_arlington").fetch(arlingtonStreet)
        #expect(fragment.segmentName?.value == "Patrick Henry DR")
        #expect(fragment.owner?.value == .county(agency: "Arlington County"))
    }

    /// The trap this profile exists to avoid.
    @Test("A VDOT secondary road is not handed to the county it runs through")
    func secondaryIsVDOT() async throws {
        let fragment = try await vdot("vdot_secondary").fetch(secondaryRoute)
        // `RTE_JURIS_PROPER_NM` on this row reads "Accomack County", and reading that as
        // ownership would hand 64,076 VDOT-maintained secondary roads to their counties.
        #expect(fragment.owner?.value
                == .state(agency: "Virginia Department of Transportation"))
        #expect(fragment.owner?.value != .county(agency: "Accomack County"))
    }

    @Test("Route type is the ownership signal, and Arlington and Henrico prove it")
    func routeTypeIsTheSignal() throws {
        // Virginia is arranged unlike any other state: VDOT maintains the secondary system in
        // every locality except Arlington and Henrico. Those two have almost no secondary
        // routes — 7 and 4 — while VDOT-maintained Fairfax has 9,422. The data confirms the
        // arrangement, which is why route type can be trusted over the locality name.
        let profile = try #require(CoverageCatalog.bundled.profile(forState: "51"))
        let rules = try #require(profile.fields?.ownershipRules)
        #expect(rules[0].field == "RTE_TYPE_NM")
        #expect(rules[0].names?["Secondary Route"] == "Virginia Department of Transportation")
        #expect(rules[0].names?["Street Route"] == "", "a street route declines, so rule two runs")
        #expect(rules[1].field == "RTE_JURIS_PROPER_NM")
    }

    @Test("The agency's route label is not mistaken for a street name")
    func commonNameNotUsed() throws {
        // RTE_COMMON_NM reads "SC-682E (Accomack County)". TIGER gives "Anns Cove Rd".
        let profile = try #require(CoverageCatalog.bundled.profile(forState: "51"))
        #expect(profile.fields?.name == nil)
        #expect(profile.fields?.nameParts?.contains("RTE_STREET_NM") == true)
    }
}
