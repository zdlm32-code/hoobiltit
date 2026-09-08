import Foundation
import Testing
@testable import RoadCore
@testable import RoadSources

private let fixedNow = Date(timeIntervalSince1970: 1_757_000_000)

@Suite("Vermont — towns and private roads, which is most of the state")
struct VermontTests {
    /// Scotch Hollow Rd, a class 2 town highway near Newbury.
    let townHighway = RoadQuery(latitude: 44.081129, longitude: -72.061161)
    /// Fisher Point Rd on Lake Champlain, one of Vermont's 16,408 private roads.
    let privateRoad = RoadQuery(latitude: 44.062262, longitude: -73.409826)

    private func source(_ fixture: String) -> FlatInventorySource {
        FlatInventorySource(
            profile: CoverageCatalog.bundled.profile(forState: "50")!,
            client: ArcGISClient(transport: FixtureTransport([
                "VT_Road_Centerline_Feb2023/FeatureServer/92": .fixture(fixture)])),
            now: { fixedNow })!
    }

    @Test("The town, not the county, is the road authority")
    func townHighways() async throws {
        let fragment = try await source("vtrans_town").fetch(townHighway)
        #expect(fragment.segmentName?.value == "SCOTCH HOLLOW RD")
        // 44,068 segments — the largest ownership class in the state. HPMS code 3 exists for
        // exactly this and almost nowhere else uses it.
        #expect(fragment.owner?.value == .municipality(name: "Town or township highway agency",
                                                       fullName: "Town or township highway agency"))
        #expect(fragment.surface?.value.type == "Paved")
    }

    @Test("A private road says private, and its placeholder route id is never its name")
    func privateRoads() async throws {
        let fragment = try await source("vtrans_private").fetch(privateRoad)
        #expect(fragment.segmentName?.value == "FISHER POINT RD")
        #expect(fragment.owner?.value == .privateOwner)
        // RTNAME is the fallback name field and reads `-` on 16,731 rows. Without nulling it,
        // every unnamed private road in Vermont would be called "-".
        #expect(fragment.segmentName?.value != "-")
    }

    @Test("Ownership is confirmed by the route ids, not just trusted")
    func routeIdsAgree() throws {
        // Cross-tabbed statewide against RTNAME, which is self-describing: ownership 1 is
        // VT/US/I signed routes, 3 and 4 are both TH- town-highway numbers (98% and 100%),
        // and 26 has no route number at all on 16,406 of 16,408 rows.
        #expect(CodeTables.owner(hpms: 3) == .municipality(name: "Town or township highway agency",
                                                           fullName: "Town or township highway agency"))
        #expect(CodeTables.owner(hpms: 26) == .privateOwner)
        // Vermont's counties are judicial districts and keep no roads: code 2 is used zero
        // times statewide. The table still knows it — Vermont simply never says it.
        #expect(CodeTables.owner(hpms: 2) == .county(agency: "County highway agency"))
    }

    @Test("Surface comes from Vermont's published domain, and Unknown is dropped")
    func surfaceDomain() throws {
        let mapping = try #require(CoverageCatalog.bundled.profile(forState: "50")?.fields)
        // One of only four services found anywhere that publish their own domains, alongside
        // NCDOT, MassDOT and NYSDOT. So these are read, not derived.
        #expect(mapping.surfaceNames?["1"] == "Paved")
        #expect(mapping.surfaceNames?["5"] == "Unimproved or primitive")
        // Code 9 is the domain's own "Unknown" on 12,394 rows. Nulled, so the card says
        // nothing about the surface rather than saying "9" or "Unknown".
        #expect(mapping.surfaceNames?["9"] == nil)
        #expect(mapping.isNull("9"))
    }

    @Test("Layer 92, and no invented dates")
    func profileShape() async throws {
        let profile = try #require(CoverageCatalog.bundled.profile(forState: "50"))
        // Layer 0 of this service is not the centreline. Getting this wrong is silent.
        #expect(profile.layer == 92)
        let fragment = try await source("vtrans_town").fetch(townHighway)
        #expect(fragment.yearLastConstruction == nil)
        #expect(fragment.works == nil)
        #expect(profile.fields?.yearBuilt == nil)
    }
}
