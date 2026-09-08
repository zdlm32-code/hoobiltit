import Foundation
import Testing
@testable import RoadCore
@testable import RoadSources

private let fixedNow = Date(timeIntervalSince1970: 1_757_000_000)

@Suite("Georgia — the state that was rejected once, on the wrong layer")
struct GeorgiaTests {
    /// On GA-1 Business through Cedartown, taken from the layer's own geometry.
    let stateRoute = RoadQuery(latitude: 34.010866, longitude: -85.254942)
    /// A rural county road in Appling County, likewise.
    let countyRoad = RoadQuery(latitude: 31.665691, longitude: -82.253924)

    private func source(_ fixture: String) -> FlatInventorySource {
        FlatInventorySource(
            profile: CoverageCatalog.bundled.profile(forState: "13")!,
            client: ArcGISClient(transport: FixtureTransport([
                "GA_RoadInventory__Rural__SR__USBR__GABR__ECG_/FeatureServer/0": .fixture(fixture)])),
            now: { fixedNow })!
    }

    @Test("The state route is picked out of thirteen segments and named by GDOT")
    func stateRouteWins() async throws {
        let fragment = try await source("gdot_state").fetch(stateRoute)
        // Twelve of the thirteen segments in this envelope are city streets. Nearest line, not
        // first returned, is what makes the answer the road the pin is actually on.
        #expect(fragment.owner?.value == .state(agency: "State highway agency"))
        #expect(fragment.segmentName?.value == "GA-1-BR")
        #expect(fragment.classification?.value == "Other principal arterial")
    }

    @Test("Where GDOT has no name the field stays empty for TIGER to fill")
    func unnamedFallsThrough() async throws {
        let fragment = try await source("gdot_county").fetch(countyRoad)
        #expect(fragment.owner?.value == .county(agency: "County highway agency"))
        // street_nm is populated on 161,717 of 872,056 rows — 90% of the state routes but
        // almost none of the county roads. Nil here is the point: it lets TIGER name the road
        // rather than the card showing an owner with no street.
        #expect(fragment.segmentName == nil)
    }

    @Test("Ownership code 0 is unset data, not a sixth class, and claims nothing")
    func codeZeroClaimsNothing() {
        // 34,591 rows carry 0, which is outside the HPMS space. 24,795 of them are
        // STATE_ROUTE=1 — a state road whose owner field was simply never filled. Reading it
        // as anything would attribute 24,795 state highways to a made-up owner.
        #expect(CodeTables.owner(hpms: 0) == nil)
        #expect(CodeTables.owner(hpms: 1) == .state(agency: "State highway agency"))
        #expect(CodeTables.owner(hpms: 25) == .municipality(name: "Other local agency",
                                                            fullName: "Other local agency"))
    }

    @Test("Georgia claims no construction dates, because it publishes none")
    func noDates() async throws {
        let fragment = try await source("gdot_state").fetch(stateRoute)
        #expect(fragment.yearLastConstruction == nil)
        #expect(fragment.yearLastImprovement == nil)
        #expect(fragment.works == nil)
        let profile = try #require(CoverageCatalog.bundled.profile(forState: "13"))
        #expect(profile.fields?.yearBuilt == nil)
        #expect(profile.fields?.workYear == nil)
        #expect(profile.dateCaveat?.isEmpty == false, "the card has to say so")
    }

    @Test("This is not the extract Georgia was rejected on")
    func notTheChattanoogaExtract() throws {
        // Section 22 rejected a layer named `HPMS` that returned zero features in Atlanta: a
        // tri-state regional extract centred on Chattanooga. This one holds 872,056 segments
        // and answers in Atlanta and Savannah.
        let profile = try #require(CoverageCatalog.bundled.profile(forState: "13"))
        #expect(profile.service?.contains("GA_RoadInventory") == true)
        #expect(profile.layer == 0)
    }
}
