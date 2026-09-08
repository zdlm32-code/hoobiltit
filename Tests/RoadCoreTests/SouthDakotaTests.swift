import Foundation
import Testing
@testable import RoadCore
@testable import RoadSources

private let fixedNow = Date(timeIntervalSince1970: 1_757_000_000)

@Suite("South Dakota — townships, road districts, and the state's own server")
struct SouthDakotaTests {
    let townshipRoad = RoadQuery(latitude: 43.713795, longitude: -98.471132)
    let districtRoad = RoadQuery(latitude: 44.380596, longitude: -98.259976)

    private func source(_ fixture: String) -> FlatInventorySource {
        FlatInventorySource(
            profile: CoverageCatalog.bundled.profile(forState: "46")!,
            client: ArcGISClient(transport: FixtureTransport([
                "DOT_Local_Roads_viewer/FeatureServer/0": .fixture(fixture)])),
            now: { fixedNow })!
    }

    @Test("A township road is a township road")
    func townships() async throws {
        let fragment = try await source("sddot_township").fetch(townshipRoad)
        #expect(fragment.segmentName?.value == "1ST ST")
        // 38,361 segments — a quarter of the state.
        #expect(fragment.owner?.value == .municipality(name: "Township road system",
                                                       fullName: "Township road system"))
    }

    @Test("A road district is an authority South Dakota names and nobody else does")
    func roadDistricts() async throws {
        let fragment = try await source("sddot_district").fetch(districtRoad)
        #expect(fragment.segmentName?.value == "APPALOOSA TRL N")
        #expect(fragment.owner?.value == .municipality(name: "Road district",
                                                       fullName: "Road district"))
    }

    @Test("County secondary is kept apart from county, because the state keeps them apart")
    func systemsDecode() {
        #expect(CodeTables.owner(sdLocalSystem: 3) == .county(agency: "County secondary highway system"))
        #expect(CodeTables.owner(sdLocalSystem: 4) == .county(agency: "County highway system"))
        #expect(CodeTables.owner(sdLocalSystem: 7) == .municipality(name: "City street system",
                                                                    fullName: "City street system"))
        // `0 - Other Administration` (6,219) and `99 - Not Attributed` (7,827) name no
        // authority. 99 is mostly the state trunk system, which DATA_CLASS answers instead.
        #expect(CodeTables.owner(sdLocalSystem: 0) == nil)
        #expect(CodeTables.owner(sdLocalSystem: 99) == nil)
        #expect(CodeTables.owner(sdDataClass: 1) == .state(agency: "South Dakota Department of Transportation"))
        // 2 rural, 3 city and 6 ramp repeat what LOCAL_SYSTEM said or describe a shape.
        #expect(CodeTables.owner(sdDataClass: 2) == nil)
        #expect(CodeTables.owner(sdDataClass: 6) == nil)
    }

    @Test("Two rules in order, and the extended functional class is left alone")
    func profileShape() throws {
        let profile = try #require(CoverageCatalog.bundled.profile(forState: "46"))
        let rules = try #require(profile.fields?.ownershipRules)
        // LOCAL_SYSTEM first, DATA_CLASS second: a state highway carries `99 - Not Attributed`
        // in the first field, so only the second can answer it.
        #expect(rules.count == 2)
        #expect(rules[0].field == "LOCAL_SYSTEM")
        #expect(rules[1].field == "DATA_CLASS")
        // FUNC_CLASS is the two-digit extended scheme (01–19), as New York's is. Read through
        // the FHWA 1–7 table, `19 - Urban Local Streets` would decode as nothing and `11 -
        // Urban Interstate` as nothing either. Not mapped.
        #expect(profile.fields?.functionalClass == nil)
        // Served from SDDOT's own server, not ArcGIS Online — the first state found that way.
        #expect(profile.service?.contains("sdgis.sd.gov") == true)
    }
}
