import Foundation
import Testing
@testable import RoadCore
@testable import RoadSources

private let fixedNow = Date(timeIntervalSince1970: 1_757_000_000)

@Suite("New Hampshire — Class VI roads, which nobody maintains")
struct NewHampshireTests {
    let classSix = RoadQuery(latitude: 43.349390, longitude: -71.499910)
    let privateRoad = RoadQuery(latitude: 43.524242, longitude: -71.697397)

    private func source(_ fixture: String) -> FlatInventorySource {
        FlatInventorySource(
            profile: CoverageCatalog.bundled.profile(forState: "33")!,
            client: ArcGISClient(transport: FixtureTransport([
                "RoadsForDOTViewer/MapServer/5": .fixture(fixture)])),
            now: { fixedNow })!
    }

    @Test("A Class VI road reports that nobody keeps it")
    func classSixRoads() async throws {
        let fragment = try await source("nhdot_classvi").fetch(classSix)
        #expect(fragment.segmentName?.value == "Abberton Rd")
        // 3,351 segments. A Class VI highway is a public right of way the town has voted to
        // stop maintaining — it is not private, not abandoned, and not maintained. Saying
        // "town" would be wrong in the way that matters most to somebody standing on one.
        #expect(fragment.owner?.value == .notPubliclyMaintained)
    }

    @Test("A private road is private")
    func privateRoads() async throws {
        let fragment = try await source("nhdot_private").fetch(privateRoad)
        #expect(fragment.segmentName?.value == "10th Mountain Rd")
        #expect(fragment.owner?.value == .privateOwner)
    }

    @Test("LC_LEGEND is used and OWNERSHIP is not, because OWNERSHIP is a trap")
    func theRightField() throws {
        let profile = try #require(CoverageCatalog.bundled.profile(forState: "33"))
        // `OWNERSHIP` reads TOWN and PRIVATE on the local rows but numeric maintenance-patrol
        // codes — 611, 325, 324 — on the state ones. Mapped, it would file a state highway as
        // a municipality called "611". `LC_LEGEND` has exactly seven values and no codes.
        #expect(profile.fields?.ownership == "LC_LEGEND")
        #expect(profile.outFields?.contains("OWNERSHIP") == false, "not even fetched")
        #expect(CodeTables.owner(level: "Local") == .municipality(name: "City or town highway agency",
                                                                  fullName: "City or town highway agency"))
        #expect(CodeTables.owner(level: "Not Maintained") == .notPubliclyMaintained)
        // 111 recreation roads and 15 out-of-state stubs name no authority.
        #expect(CodeTables.owner(level: "Recreation") == nil)
        #expect(CodeTables.owner(level: "Out of state") == nil)
    }

    @Test("The first-party publication, on layer 5")
    func profileShape() throws {
        let profile = try #require(CoverageCatalog.bundled.profile(forState: "33"))
        // The same inventory also sits inside a *Vermont* Amtrak study on ArcGIS Online. This
        // is NH GRANIT's own copy, which is the one to depend on.
        #expect(profile.service?.contains("nhgeodata.unh.edu") == true)
        #expect(profile.layer == 5)
        #expect(profile.fields?.yearBuilt == nil)
    }
}
