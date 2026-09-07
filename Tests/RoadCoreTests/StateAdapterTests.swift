import Foundation
import Testing
@testable import RoadCore
@testable import RoadSources

private let fixedNow = Date(timeIntervalSince1970: 1_757_000_000)

private func year(_ date: Date) -> Int { CalendarDate.year(date) }

// MARK: - Pennsylvania, a flat inventory

@Suite("PennDOT — one denormalised inventory layer")
struct FlatInventoryTests {
    /// Central Philadelphia. The envelope returns fourteen segments, including SIXTEENTH ST
    /// twice: once state-owned and built 1916, once locally owned with no year at all.
    let philadelphia = RoadQuery(latitude: 39.95851, longitude: -75.16558)

    // Force-unwrapped rather than `#require`d: a nil here means the bundled catalog lost its
    // Pennsylvania entry, which every other test in this suite would also fail on.
    private func source(_ transport: FixtureTransport) -> FlatInventorySource {
        FlatInventorySource(profile: CoverageCatalog.bundled.profile(forState: "42")!,
                            client: ArcGISClient(transport: transport),
                            now: { fixedNow })!
    }

    private var philly: FixtureTransport {
        FixtureTransport(["roadwaysegments/MapServer/0": .fixture("penndot_philly")])
    }

    @Test("Names the road, dates it, and says who maintains it")
    func readsPennsylvania() async throws {
        let fragment = try await source(philly).fetch(philadelphia)
        #expect(fragment.segmentName?.value == "SIXTEENTH ST")
        let owner = try #require(fragment.owner?.value)
        // JURIS decoded, not MAINT_RESPON_IND. Every segment here reads MAINT_RESPON_IND 40,
        // which as HPMS would be "city or municipal" — including on I-676.
        #expect(owner == .state(agency: "Pennsylvania Department of Transportation"))
        #expect(fragment.trafficCount?.value == 10_286)
        #expect(year(try #require(fragment.yearLastConstruction?.value)) == 1916)
    }

    @Test("A year of zero never reaches the record")
    func nullSentinel() async throws {
        // Every locally owned Pennsylvania segment publishes YR_BUILT = 0 and YR_RESURF = 0.
        // Read naively that is either "year 0" or, once a date decoder gets hold of it, 1970.
        let localOnly = FixtureTransport(["roadwaysegments/MapServer/0": .body(localSegmentJSON)])
        let fragment = try await source(localOnly).fetch(philadelphia)
        #expect(fragment.segmentName?.value == "SIXTEENTH ST")
        #expect(fragment.yearLastConstruction == nil, "0 is PennDOT's null, not a year")
        #expect(fragment.yearLastImprovement == nil)
        // And the card is told why, rather than just showing a gap.
        #expect(fragment.notes.first?.detail?.contains("maintains itself") == true)
    }

    @Test("A state-owned segment keeps its real 1916 build year")
    func realYearSurvives() async throws {
        let stateOnly = FixtureTransport(["roadwaysegments/MapServer/0": .body(stateSegmentJSON)])
        let fragment = try await source(stateOnly).fetch(philadelphia)
        let built = try #require(fragment.yearLastConstruction?.value)
        #expect(year(built) == 1916)
        let resurfaced = try #require(fragment.yearLastImprovement?.value)
        #expect(year(resurfaced) == 2004)
        // Kept as separate facts. Fusing them into one "built" would erase the distinction
        // between laying a road and repaving it.
        #expect(built != resurfaced)
    }

    @Test("Values are matched by location, never claimed as direct")
    func spatialConfidence() async throws {
        let fragment = try await source(philly).fetch(philadelphia)
        #expect(fragment.segmentName?.confidence == .spatial)
    }

    @Test("An unsigned street is not labelled Route 000")
    func routeSentinel() async throws {
        // PennDOT writes TRAF_RT_NO = "000" on every road carrying no signed route number,
        // and it parses as a perfectly good number.
        let fragment = try await source(philly).fetch(philadelphia)
        #expect(fragment.routeDesignation == nil)
        #expect(fragment.routeDesignation?.value != "000")
    }

    @Test("Nothing here is a normal answer, not a failure")
    func emptyIsFine() async throws {
        let empty = FixtureTransport(["roadwaysegments/MapServer/0": .body(#"{"features":[]}"#)])
        let fragment = try await source(empty).fetch(philadelphia)
        #expect(!fragment.contributesAnything)
        #expect(fragment.notes.first?.outcome == .foundNothing)
    }
}

/// One locally owned row, lifted verbatim from the captured Philadelphia response.
private let localSegmentJSON = """
{"features":[{"attributes":{"STREET_NAME":"SIXTEENTH ST","ST_RT_NO":"G043","YR_BUILT":0,\
"YR_RESURF":0,"JURIS":"5","MAINT_RESPON_IND":null,"CUR_AADT":6030},\
"geometry":{"paths":[[[-75.1652,39.9526],[-75.1652,39.9530]]]}}]}
"""

private let stateSegmentJSON = """
{"features":[{"attributes":{"STREET_NAME":"SIXTEENTH ST","ST_RT_NO":"3027","YR_BUILT":1916,\
"YR_RESURF":2004,"JURIS":"1","MAINT_RESPON_IND":"40","CUR_AADT":10286},\
"geometry":{"paths":[[[-75.1652,39.9526],[-75.1652,39.9530]]]}}]}
"""

// MARK: - Louisiana, an LRS

@Suite("Louisiana DOTD — linear-referenced events")
struct LRSEventTests {
    /// A residential block in Baton Rouge. Balis Dr is here; so is Perkins Rd, which is the
    /// only road in the box the construction table has a row for.
    let balisDrive = RoadQuery(latitude: 30.419270, longitude: -91.145970)

    private func source(_ transport: FixtureTransport) -> LRSEventSource {
        LRSEventSource(profile: CoverageCatalog.bundled.profile(forState: "22")!,
                       client: ArcGISClient(transport: transport),
                       now: { fixedNow })!
    }

    private var batonRouge: FixtureTransport {
        FixtureTransport([
            "Roads_and_Highways_OpenData/MapServer/49": .fixture("la_49_batonrouge"),
            "Roads_and_Highways_OpenData/MapServer/91": .fixture("la_91_batonrouge"),
            "Roads_and_Highways_OpenData/MapServer/69": .fixture("la_69_batonrouge"),
            "Roads_and_Highways_OpenData/MapServer/84": .fixture("la_84_batonrouge"),
        ])
    }

    @Test("Names a residential street and its owner, statewide")
    func namesLocalStreets() async throws {
        // Louisiana's route layer is 576,063 features and does reach residential streets,
        // which is what makes name-and-owner a real answer here rather than a state-highway
        // one.
        let fragment = try await source(batonRouge).fetch(balisDrive)
        #expect(fragment.segmentName?.value == "BALIS DR")
        #expect(fragment.owner?.value.displayName == "City or municipal highway agency")
    }

    @Test("Does not date a street from the construction row of the road next to it")
    func doesNotBorrowANeighboursYear() async throws {
        // This is the whole reason LRSEventSource exists rather than "first event in the
        // envelope". The construction table's only row anywhere in this box is Perkins Rd,
        // measures 1.653-2.26, year 1971. Balis Dr is a different route id, one street over.
        let fragment = try await source(batonRouge).fetch(balisDrive)
        #expect(fragment.segmentName?.value == "BALIS DR")
        #expect(fragment.yearLastConstruction == nil,
                "1971 belongs to Perkins Rd; Balis Dr has no published year")
        // Name and owner still land, which is the bar for a useful answer here.
        #expect(fragment.owner != nil)
    }

    @Test("A pin on Perkins Rd does get 1971")
    func joinsWhenTheRouteMatches() async throws {
        // Perkins Rd appears as three consecutive route segments (1.930-1.999, 1.999-2.072,
        // 2.072-2.203) and the construction event spans all three, so the id filter and the
        // measure overlap both have to hold for this to resolve.
        let onPerkins = RoadQuery(latitude: 30.418620, longitude: -91.147830)
        let fragment = try await source(batonRouge).fetch(onPerkins)
        #expect(fragment.segmentName?.value == "PERKINS RD")
        #expect(year(try #require(fragment.yearLastConstruction?.value)) == 1971)
        #expect(fragment.classification?.value == "Other principal arterial")
    }

    @Test("The dedicated ownership table outranks the route layer's copy")
    func eventLayerWinsOverRouteLayer() async throws {
        // Layers 49 and 91 disagree: Balis Dr reads Ownership 2 on the route layer and 4 on
        // the HPMS event table. 91 is listed first in the catalog and must win.
        let fragment = try await source(batonRouge).fetch(balisDrive)
        let owner = try #require(fragment.owner)
        // Layer 49 publishes Ownership 2 (county) for Balis Dr and layer 91 publishes 4
        // (municipal). 91 is first in the catalog and wins.
        #expect(owner.value == CodeTables.owner(hpms: 4))
        #expect(owner.value != CodeTables.owner(hpms: 2))
        #expect(owner.confidence == .direct, "an event-table answer, not the route layer's")
        #expect(owner.provenance.url.path().contains("/91/"))
    }

    @Test("A dead event table costs only its own fields")
    func oneDeadLayerDoesNotFailTheSource() async throws {
        var routes = batonRouge.routes
        routes["Roads_and_Highways_OpenData/MapServer/91"] = .status(500)
        let fragment = try await source(FixtureTransport(routes)).fetch(balisDrive)
        #expect(fragment.segmentName != nil, "the route layer still answered")
    }

    @Test("Every event layer is queried, and concurrently")
    func queriesAllEventLayers() async throws {
        let transport = batonRouge
        _ = try await source(transport).fetch(balisDrive)
        let layers = Set(transport.log.all.compactMap { FixtureTransport.layerID(of: $0) })
        #expect(layers.isSuperset(of: [49, 91, 69, 84]))
    }

    @Test("No route here is a normal answer")
    func emptyIsFine() async throws {
        let empty = FixtureTransport(["Roads_and_Highways_OpenData/MapServer/49":
                                        .body(#"{"features":[]}"#)])
        let fragment = try await source(empty).fetch(balisDrive)
        #expect(!fragment.contributesAnything)
        #expect(fragment.notes.first?.outcome == .foundNothing)
    }
}
