import Foundation
import Testing
@testable import RoadCore
@testable import RoadSources

private let fixedNow = Date(timeIntervalSince1970: 1_757_000_000)

@Suite("Montana — a published domain, and silence on four roads in five")
struct MontanaTests {
    let privateDrive = RoadQuery(latitude: 48.410386, longitude: -115.558052)
    let cityWay = RoadQuery(latitude: 48.395521, longitude: -115.559455)

    private func source(_ fixture: String) -> FlatInventorySource {
        FlatInventorySource(
            profile: CoverageCatalog.bundled.profile(forState: "30")!,
            client: ArcGISClient(transport: FixtureTransport([
                "Montana_Transportation_Framework/FeatureServer/0": .fixture(fixture)])),
            now: { fixedNow })!
    }

    @Test("The name is joined out of four fields, not picked from one")
    func joinsTheName() async throws {
        let fragment = try await source("mdt_city").fetch(cityWay)
        // Montana stores `Brown` and `Way` separately, with prefix and suffix directions in
        // two more fields. Taking the first that yields a value gives "Brown".
        #expect(fragment.segmentName?.value == "Brown Way")
        #expect(fragment.owner?.value == .municipality(name: "City or municipal highway agency",
                                                       fullName: "City or municipal highway agency"))
    }

    @Test("A private road says so")
    func privateRoads() async throws {
        let fragment = try await source("mdt_private").fetch(privateDrive)
        #expect(fragment.segmentName?.value == "Ozette Drive")
        #expect(fragment.owner?.value == .privateOwner)
    }

    @Test("The levels are read from Montana's domain, not guessed")
    func levelsDecode() {
        // One of the few services anywhere that publishes coded values for ownership.
        #expect(CodeTables.owner(level: "City") == .municipality(name: "City or municipal highway agency",
                                                                 fullName: "City or municipal highway agency"))
        #expect(CodeTables.owner(level: "County") == .county(agency: "County highway agency"))
        #expect(CodeTables.owner(level: "State") == .state(agency: "State highway agency"))
        #expect(CodeTables.owner(level: "Tribal") == .tribal(agency: "Indian tribe nation"))
        #expect(CodeTables.owner(level: "Private") == .privateOwner)
        // `Public` says a road is open to the public without saying who keeps it. 3,097 rows,
        // and the honest answer is none.
        #expect(CodeTables.owner(level: "Public") == nil)
        #expect(CodeTables.owner(level: nil) == nil)
    }

    @Test("Where Montana names no owner, the app names none either")
    func silenceIsAnAnswer() throws {
        // `Ownership` is null on 187,758 of 238,768 rows — 78.6% of the state. Those rows
        // still carry a name, so the road is identified and the owner simply is not claimed.
        // A profile that filled the gap with "state" would be wrong four times in five.
        let profile = try #require(CoverageCatalog.bundled.profile(forState: "30"))
        #expect(profile.fields?.ownershipTable == .authorityLevel)
        #expect(CodeTables.owner(level: "") == nil)
        #expect(profile.fields?.yearBuilt == nil)
    }
}
