import Foundation
import Testing
@testable import RoadCore
@testable import RoadSources

private let fixedNow = Date(timeIntervalSince1970: 1_757_000_000)

@Suite("Texas metros beyond the big four")
struct TexasMetroTests {
    /// Albany Dr, a Laredo residential street with a genuine 1993 construction year.
    let albany = RoadQuery(latitude: 27.6073405, longitude: -99.5228467)
    /// Lonesome Dove Trl, installed and replaced the same day in 2005.
    let lonesomeDove = RoadQuery(latitude: 32.618114, longitude: -97.108583)
    /// AT&T Way, whose only dates are both bulk-loaded defaults.
    let attWay = RoadQuery(latitude: 32.7511837, longitude: -97.0894030)

    private func city(_ geoid: String, _ transport: FixtureTransport) -> FlatInventorySource {
        FlatInventorySource(profile: CoverageCatalog.bundled.profile(forPlace: geoid)!,
                            client: ArcGISClient(transport: transport), now: { fixedNow })!
    }

    // MARK: - Laredo

    @Test("A residential street gets a real construction year, which almost nothing publishes")
    func laredoYearBuilt() async throws {
        let transport = FixtureTransport(["Pavement_Condition_Index/FeatureServer/0":
                                            .fixture("laredo_pavement_albany")])
        let fragment = try await city("4841464", transport).fetch(albany)
        #expect(fragment.segmentName?.value == "ALBANY DR")
        #expect(CalendarDate.year(try #require(fragment.yearLastConstruction?.value)) == 1993)
        #expect(fragment.owner?.value == .municipality(name: "City of Laredo",
                                                       fullName: "City of Laredo"))
        #expect(fragment.surface?.value.type == "ASPHALT")
        #expect(fragment.surface?.value.conditionIndex == 55)
    }

    @Test("A shouted agency name is not shouted back")
    func titleCasing() {
        // The layer writes "CITY OF LAREDO". Capitalised naively that is "City Of Laredo".
        #expect(CodeTables.owner(named: "CITY OF LAREDO")
                == .municipality(name: "City of Laredo", fullName: "City of Laredo"))
        // A name already in mixed case is left exactly as the agency wrote it.
        #expect(CodeTables.owner(named: "Alamo Heights")
                == .municipality(name: "Alamo Heights", fullName: "Alamo Heights"))
    }

    @Test("Laredo's 1980 placeholder is not a construction year")
    func laredoSentinel() throws {
        // 5,405 of 10,627 segments — 50.9% — carry exactly 1980, against a smooth spread of
        // about 2% per year across the other 53 values. Half a city was not built in one year.
        let profile = try #require(CoverageCatalog.bundled.profile(forPlace: "4841464"))
        #expect(profile.fields?.nullNumbers?.contains(1980) == true)
    }

    // MARK: - Arlington

    @Test("A street carries both when it went in and when it was last replaced")
    func arlingtonDates() async throws {
        let transport = FixtureTransport(["COA_Street_Custodian/FeatureServer/0":
                                            .fixture("arlington_pavement_lonesome")])
        let fragment = try await city("4804000", transport).fetch(lonesomeDove)
        #expect(fragment.segmentName?.value == "Lonesome Dove Trl")
        #expect(CalendarDate.year(try #require(fragment.yearLastConstruction?.value)) == 2005)
        #expect(fragment.classification?.value == "Residential")
        #expect(fragment.owner?.value == .municipality(name: "City of Arlington",
                                                       fullName: "City of Arlington"))
    }

    @Test("One rebuild is one fact, not two rows saying the same day")
    func sameDayNotRepeated() async throws {
        let transport = FixtureTransport(["COA_Street_Custodian/FeatureServer/0":
                                            .fixture("arlington_pavement_lonesome")])
        let fragment = try await city("4804000", transport).fetch(lonesomeDove)
        // Arlington records a street rebuilt in one go as installed and replaced on the same
        // day; "built 5 Dec 2005, improved 5 Dec 2005" is two rows spent on one fact.
        #expect(fragment.yearLastImprovement == nil)
    }

    /// The trap: the fields that look right are empty, and the ones that work carry defaults.
    @Test("Arlington's bulk-loaded default dates never reach the record")
    func arlingtonSentinels() async throws {
        let transport = FixtureTransport(["COA_Street_Custodian/FeatureServer/0":
                                            .fixture("arlington_pavement_sentinel")])
        let fragment = try await city("4804000", transport).fetch(attWay)
        // 2,209 segments are "installed" on 1908-06-09 and 1,370 "replaced" on 2008-06-12 —
        // single exact dates against roughly 1,280 distinct values spread under 1% each.
        #expect(fragment.yearLastConstruction == nil)
        #expect(fragment.yearLastImprovement == nil)
        // Everything else about the segment still comes through.
        #expect(fragment.segmentName?.value == "AT&T Way")
        #expect(fragment.owner != nil)
    }

    @Test("The fields named Built and Reconstructed are the wrong ones")
    func readsInstalledNotBuilt() throws {
        // Both exist on all 17,359 rows and both are null on every one of them. Reading them
        // would have produced a city-wide source that silently answered nothing.
        let profile = try #require(CoverageCatalog.bundled.profile(forPlace: "4804000"))
        #expect(profile.fields?.yearBuilt == "Installed")
        #expect(profile.fields?.yearImproved == "Replaced")
        let requested = try #require(profile.outFields)
        #expect(!requested.contains("Built"))
        #expect(!requested.contains("Reconstructed"))
    }

    @Test("Both metro profiles are reachable")
    func profilesLoad() {
        #expect(CoverageCatalog.bundled.profile(forPlace: "4841464")?.id == "tx.laredo.pavement")
        #expect(CoverageCatalog.bundled.profile(forPlace: "4804000")?.id == "tx.arlington.pavement")
    }
}
