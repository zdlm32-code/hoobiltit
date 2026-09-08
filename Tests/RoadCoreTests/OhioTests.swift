import Foundation
import Testing
@testable import RoadCore
@testable import RoadSources

private let fixedNow = Date(timeIntervalSince1970: 1_757_000_000)

@Suite("Ohio — a name in three fields and a letter for who owns it")
struct OhioTests {
    let mainStreet = RoadQuery(latitude: 40.732854, longitude: -84.105040)
    let township = RoadQuery(latitude: 38.953349, longitude: -83.427459)

    private func source(_ fixture: String) -> FlatInventorySource {
        FlatInventorySource(
            profile: CoverageCatalog.bundled.profile(forState: "39")!,
            client: ArcGISClient(transport: FixtureTransport([
                "Road_Inventory/FeatureServer/0": .fixture(fixture)])),
            now: { fixedNow })!
    }

    @Test("A name stored in three fields is joined, not picked from")
    func joinsTheName() async throws {
        let fragment = try await source("odot_main_st").fetch(mainStreet)
        // Ohio holds `S`, `MAIN` and `ST` separately. Taking the first field that yields a
        // value — which is what every other profile does — gives "MAIN".
        #expect(fragment.segmentName?.value == "S MAIN ST")
        #expect(fragment.trafficCount?.value == 4_161)
    }

    @Test("Townships are a road authority in Ohio, and are named as one")
    func townshipTrustees() async throws {
        let fragment = try await source("odot_township").fetch(township)
        #expect(fragment.segmentName?.value == "RALPH MORRISON RD")
        // 111,882 segments. Most states have no such level; HPMS code 3 exists for it.
        #expect(fragment.owner?.value == .municipality(name: "Township trustees",
                                                       fullName: "Township trustees"))
    }

    @Test("The jurisdiction letter decodes to the level its route types prove")
    func jurisdictionLetters() {
        // Undocumented — the layer publishes no domain — so derived by cross-tabbing against
        // ROUTE_TYPE, which is self-describing. The partition is exact.
        #expect(CodeTables.owner(ohio: "S") == .state(agency: "Ohio Department of Transportation"))
        #expect(CodeTables.owner(ohio: "C") == .county(agency: "County engineer"))
        if case .municipality = CodeTables.owner(ohio: "M") {} else { Issue.record("M is municipal") }
        if case .federal = CodeTables.owner(ohio: "F") {} else { Issue.record("F is federal") }
        // 42,156 segments whose rows carry blank names and are 99.9% functional class 7. That
        // reads as private, and "reads as" is not evidence — so it claims nothing.
        #expect(CodeTables.owner(ohio: "P") == nil)
        #expect(CodeTables.owner(ohio: nil) == nil)
    }

    @Test("Ohio's publication year is never dressed up as a build year")
    func noFakeDates() async throws {
        let fragment = try await source("odot_main_st").fetch(mainStreet)
        // PERP_YEAR is 2022 on 100% of 402,947 rows — the dataset's own vintage. RESURFACE_
        // covers 9,228 segments across 2020-2022 only. Neither is mapped.
        #expect(fragment.yearLastConstruction == nil)
        #expect(fragment.yearLastImprovement == nil)
        #expect(fragment.works == nil)
        let profile = try #require(CoverageCatalog.bundled.profile(forState: "39"))
        #expect(profile.fields?.yearBuilt == nil)
        #expect(profile.fields?.workYear == nil)
        #expect(profile.outFields?.contains("PERP_YEAR") == false, "not even fetched")
    }

    @Test("This is not the Ohio layer rejected earlier")
    func differentService() throws {
        // Section 10.3 rejected an Ohio source whose LAST_CONST was the 1900-01-01 placeholder
        // on 5,804 of 58,127 rows, served from a host that now 404s. This one is ODOT's
        // ArcGIS Online copy: 402,947 rows, and no construction field at all to get wrong.
        let profile = try #require(CoverageCatalog.bundled.profile(forState: "39"))
        #expect(profile.service?.contains("services1.arcgis.com") == true)
        #expect(profile.service?.contains("dot.state.oh.us") == false)
    }
}
