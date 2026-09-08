import Foundation
import Testing
@testable import RoadCore
@testable import RoadSources

private let fixedNow = Date(timeIntervalSince1970: 1_757_000_000)

@Suite("Delaware — a code that was undecodable until the sibling layer was read")
struct DelawareTests {
    let dover = RoadQuery(latitude: 39.1582, longitude: -75.5244)
    let wilmington = RoadQuery(latitude: 39.7447, longitude: -75.5484)

    private func source(_ fixture: String) -> FlatInventorySource {
        FlatInventorySource(
            profile: CoverageCatalog.bundled.profile(forState: "10")!,
            client: ArcGISClient(transport: FixtureTransport([
                "DE_Roadways_Main/MapServer/2": .fixture(fixture)])),
            now: { fixedNow })!
    }

    @Test("The state maintains almost every road in Delaware, and says when it last improved it")
    func stateRoads() async throws {
        let fragment = try await source("deldot_state").fetch(dover)
        #expect(fragment.segmentName?.value == "S. STATE STREET")
        #expect(fragment.owner?.value == .state(agency: "State highway agency"))
        // 55.1% of rows carry one, 19 distinct values over 1983–2025, no sentinel.
        #expect(CalendarDate.year(try #require(fragment.yearLastImprovement?.value)) == 2010)
    }

    @Test("A city street is a city street")
    func municipalRoads() async throws {
        let fragment = try await source("deldot_municipal").fetch(wilmington)
        #expect(fragment.segmentName?.value == "N. MARKET STREET")
        #expect(fragment.owner?.value == .municipality(name: "City or municipal highway agency",
                                                       fullName: "City or municipal highway agency"))
    }

    @Test("The codes are the ones the sibling layer proved, and the third claims nothing")
    func codesDecode() throws {
        let mapping = try #require(CoverageCatalog.bundled.profile(forState: "10")?.fields)
        // Derived by joining layer 2's MAINT_RSP_CODE to layer 7's plain-English VALUE_TEXT,
        // which is shaped "<owner> Road Maintained by <maintainer>". Layer 7 is segmented by
        // milepost, so joining on RDWAY_ID alone conflates stretches of one road kept by
        // different bodies — restricting it to the 99% of road ids carrying exactly one text
        // gives code 1 on 7,669 state segments and code 2 on 2,191 municipal ones.
        #expect(mapping.ownerNames?["1"] == "State")
        #expect(mapping.ownerNames?["2"] == "City")
        // Code 3 is every "… Maintained by Other Forces" row — 210 of 210 in the join. It is
        // a real category and still names no authority, so an empty rewrite declines.
        #expect(mapping.ownerNames?["3"] == "")
        #expect(mapping.ownershipTable == .authorityLevel)
    }

    @Test("The acceptance year is not dressed up as a construction year")
    func acceptanceIsNotConstruction() throws {
        let profile = try #require(CoverageCatalog.bundled.profile(forState: "10"))
        // ACCEPT_YEAR_CODE is on 32,039 rows and runs 1900–2004, but it records when the state
        // took the road into its system, not when the road was built. No field means that, so
        // it is left unmapped rather than forced into `yearBuilt`.
        #expect(profile.fields?.yearBuilt == nil)
        #expect(profile.outFields?.contains("ACCEPT_YEAR_CODE") == false, "not even fetched")
        #expect(profile.dateCaveat?.contains("not when it was first built") == true)
    }
}
