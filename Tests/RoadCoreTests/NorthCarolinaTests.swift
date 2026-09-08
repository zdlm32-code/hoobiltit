import Foundation
import Testing
@testable import RoadCore
@testable import RoadSources

private let fixedNow = Date(timeIntervalSince1970: 1_757_000_000)

@Suite("North Carolina — the one agency that documents itself")
struct NorthCarolinaTests {
    let i295 = RoadQuery(latitude: 35.028543, longitude: -79.037198)
    let charlotte = RoadQuery(latitude: 35.2271, longitude: -80.8431)

    private func source(_ fixture: String) -> FlatInventorySource {
        FlatInventorySource(
            profile: CoverageCatalog.bundled.profile(forState: "37")!,
            client: ArcGISClient(transport: FixtureTransport([
                "NCDOT_RoadCharacteristicsQtr/MapServer/0": .fixture(fixture)])),
            now: { fixedNow })!
    }

    @Test("A state road is dated and its work named from the agency's own vocabulary")
    func stateRoad() async throws {
        let fragment = try await source("ncdot_i295").fetch(i295)
        #expect(fragment.segmentName?.value == "I 295 N")
        #expect(fragment.owner?.value
                == .state(agency: "North Carolina Department of Transportation"))
        let work = try #require(fragment.works?.value.first)
        // `NR` in the data. NCDOT is the only agency probed anywhere that publishes coded
        // value domains, so this label is the agency's own words rather than an inference.
        #expect(work.title == "New Construction")
        #expect(work.kind == .built)
        #expect(CalendarDate.year(try #require(work.letDate)) == 2020)
        #expect(fragment.surface?.value.type == "Bituminous", "not the stored 'Bitum'")
    }

    @Test("A city street is owned by the city, named")
    func cityStreet() async throws {
        let fragment = try await source("ncdot_charlotte").fetch(charlotte)
        #expect(fragment.segmentName?.value == "S Tryon St")
        // OwnerType 4 gives the level and OwnerName gives the body. The code alone would
        // render this as "city or municipal highway agency".
        #expect(fragment.owner?.value == .municipality(name: "Charlotte", fullName: "Charlotte"))
    }

    // MARK: - The two-rule ownership

    @Test("Ownership is read from whichever field actually carries it")
    func ownershipRules() throws {
        let profile = try #require(CoverageCatalog.bundled.profile(forState: "37"))
        let rules = try #require(profile.fields?.ownershipRules)
        #expect(rules.count == 2)
        // The named body first...
        #expect(rules[0].field == "OwnerType")
        #expect(rules[0].nameField == "OwnerName")
        // ...then NCDOT's own declaration, which lives in a third field entirely. 607,062
        // segments say `System` and name no owner at all; reading that blank as "state" would
        // be a guess where the agency published an answer.
        #expect(rules[1].field == "RouteMaintCode")
        #expect(rules[1].names?["System"] == "North Carolina Department of Transportation")
        #expect(rules[1].names?["Non-System"] == "", "an empty rename declines")
    }

    @Test("A coded owner keeps its kind when it gains a name")
    func renaming() {
        #expect(CodeTables.owner(hpms: 4)?.renamed(to: "Charlotte")
                == .municipality(name: "Charlotte", fullName: "Charlotte"))
        #expect(CodeTables.owner(hpms: 2)?.renamed(to: "Wake County")
                == .county(agency: "Wake County"))
        // A private owner has no body to name, and naming one would invent a party.
        #expect(RoadOwner.privateOwner.renamed(to: "Anything") == .privateOwner)
    }

    @Test("Improvement types come from the published domain, not a guess")
    func improvementVocabulary() {
        #expect(CodeTables.work(ncdot: "NR")?.kind == .built)
        #expect(CodeTables.work(ncdot: "RE")?.label == "Reconstruction")
        #expect(CodeTables.work(ncdot: "MA")?.kind == .built)
        #expect(CodeTables.work(ncdot: "RS")?.kind == .maintained)
        #expect(CodeTables.work(ncdot: "SI")?.kind == .maintained)
        #expect(CodeTables.work(ncdot: "OT")?.kind == .ancillary)
        #expect(CodeTables.work(ncdot: "ZZ") == nil, "an undocumented code is not invented")
        #expect(CodeTables.work(ncdot: nil) == nil)
    }

    @Test("North Carolina needs no sentinel filter, and that is worth asserting")
    func noSentinels() throws {
        // Unlike San Antonio (96% placeholder), Laredo (50.9%) and Arlington (two bulk dates),
        // NCDOT's ImprvDate is 1,872 distinct values with the largest at 4.0%. The profile
        // carries no date sentinel, and if that ever changes it should be a deliberate edit.
        let profile = try #require(CoverageCatalog.bundled.profile(forState: "37"))
        #expect(profile.fields?.nullNumbers == [0])
    }
}
