import Foundation
import Testing
@testable import RoadCore
@testable import RoadSources

private let provenance = Provenance(sourceID: "t", sourceName: "Test",
                                    url: URL(string: "https://example.org")!, fetchedAt: Date())

/// Where the Loop 101 on-ramp meets the main line in north Phoenix. ADOT's layer has a gap
/// here, the Census names the road "Pima Fwy", and the NHS segment is unnamed and signed S101.
private let pimaFwy = RoadQuery(latitude: 33.67232, longitude: -111.97124)

private func phoenixInference() -> Attributed<RoadOwner> {
    Attributed(.municipality(name: "Phoenix", fullName: "City of Phoenix"),
               provenance: provenance, confidence: .derived)
}

private func record(named name: String?, owner: Attributed<RoadOwner>? = phoenixInference(),
                    route: String? = nil) -> RoadRecord {
    var record = RoadRecord(query: pimaFwy)
    record.segmentName = name.map { Attributed($0, provenance: provenance, confidence: .spatial) }
    record.routeDesignation = route.map { Attributed($0, provenance: provenance) }
    record.owner = owner
    return record
}

private func nhs() -> NHSOwnershipSource {
    NHSOwnershipSource(client: ArcGISClient(transport: FixtureTransport(
        ["National_Highway_System/MapServer/0": .fixture("nhs_pima_unnamed")])))
}

@Suite("Highways are recognised by name")
struct HighwayNameTests {
    @Test("Route signs and spelled-out routes are the same routes")
    func routes() {
        #expect(HighwayName.sameRoute("S101", "State Rte 101"))
        #expect(HighwayName.sameRoute("S101", "SR-101"))
        #expect(HighwayName.sameRoute("S101", "Loop 101"))
        #expect(HighwayName.sameRoute("I10", "I-10"))
        #expect(HighwayName.sameRoute("I17", "Interstate 17"))
        #expect(HighwayName.sameRoute("U60", "US 60"))
        #expect(!HighwayName.sameRoute("S101", "SR-51"))
        #expect(!HighwayName.sameRoute("I10", "US 10"), "the system matters, not just the number")
    }

    @Test("A south-side street is not State Route 7")
    func directionsAreNotRoutes() {
        #expect(HighwayName.route("S 7th St") == nil)
        #expect(HighwayName.route("S 7 Ave") == nil)
        #expect(HighwayName.route("US Bank Way") == nil)
        #expect(HighwayName.route("I St") == nil)
    }

    @Test("Freeways and numbered routes are highways; expressways and parkways are not assumed")
    func highways() {
        #expect(HighwayName.isHighway("Pima Fwy"))
        #expect(HighwayName.isHighway("Black Canyon Freeway"))
        #expect(HighwayName.isHighway("SR-101"))
        #expect(HighwayName.isHighway("State Rte 101"))
        #expect(!HighwayName.isHighway("Sky Harbor Expy"), "Phoenix owns this one")
        #expect(!HighwayName.isHighway("Bob Stump Memorial Pkwy"))
        #expect(!HighwayName.isHighway("N Tatum Blvd"))
        #expect(!HighwayName.isHighway(nil))
    }

    @Test("Ramps and canal service roads are recognised")
    func rampsAndCanals() {
        #expect(HighwayName.isRamp("SR-101 Exit 37 E1-Ramp"))
        #expect(!HighwayName.isRamp("Pima Fwy"))
        #expect(HighwayName.isCanalServiceRoad("Central Arizona Project Csr"))
        #expect(HighwayName.isCanalServiceRoad("Roosevelt Irrigation District Csr"))
        #expect(!HighwayName.isCanalServiceRoad("Cesar Chavez Blvd"))
    }
}

@Suite("A guess never outranks a record")
struct OwnerGuessTests {
    @Test("A recorded owner replaces one inferred from city limits")
    func recordReplacesInference() {
        var merged = record(named: "Pima Fwy")
        var fragment = RoadFragment()
        fragment.owner = Attributed(.state(agency: "State highway agency"),
                                    provenance: provenance, confidence: .spatial)
        merged.merge(fragment)
        #expect(merged.owner?.value == .state(agency: "State highway agency"))
    }

    @Test("County maintenance from the maintained set is not displaced")
    func maintainedSetStays() {
        let county = Attributed(RoadOwner.county(agency: "Maricopa County Department of Transportation"),
                                provenance: provenance, confidence: .derived)
        var merged = record(named: "Williams Dr", owner: county)
        var fragment = RoadFragment()
        fragment.owner = Attributed(.state(agency: "State highway agency"),
                                    provenance: provenance, confidence: .nameMatch)
        merged.merge(fragment)
        #expect(merged.owner == county)
    }

    @Test("A guess does not replace another guess, and a record is never replaced")
    func firstStillWinsOtherwise() {
        var merged = record(named: "Pima Fwy")
        var guess = RoadFragment()
        guess.owner = Attributed(.notPubliclyMaintained, provenance: provenance, confidence: .derived)
        merged.merge(guess)
        #expect(merged.owner == phoenixInference())

        let adot = Attributed(RoadOwner.state(agency: "Arizona Department of Transportation"),
                              provenance: provenance, confidence: .direct)
        var direct = record(named: "SR-101", owner: adot)
        var later = RoadFragment()
        later.owner = Attributed(.state(agency: "State highway agency"),
                                 provenance: provenance, confidence: .nameMatch)
        direct.merge(later)
        #expect(direct.owner == adot)
    }

    @Test("Left with only a city guess, a freeway shows no owner rather than the wrong one")
    func freewayInferenceIsWithheld() {
        var freeway = record(named: "Pima Fwy")
        freeway.withholdImplausibleOwner()
        #expect(freeway.owner == nil)
        #expect(freeway.notes.contains { $0.detail?.contains("Pima Fwy is a highway") == true })

        var street = record(named: "N Tatum Blvd")
        street.withholdImplausibleOwner()
        #expect(street.owner == phoenixInference(), "a city street inside the city is the city's")

        var canal = record(named: "Central Arizona Project Csr")
        canal.withholdImplausibleOwner()
        #expect(canal.owner == nil, "the canal's operator maintains its service road")
        #expect(canal.notes.contains { $0.detail?.contains("canal service road") == true })
    }
}

@Suite("The national highway layer fills the gap")
struct NHSUnnamedFreewayTests {
    @Test("An unnamed NHS freeway gives the freeway under the pin its owner")
    func unnamedFreeway() async throws {
        let fragment = try await nhs().fetch(pimaFwy, resolved: record(named: "Pima Fwy"))
        #expect(fragment.owner?.value == .state(agency: "State highway agency"))
        #expect(fragment.owner?.confidence == .spatial)
        // Owner only: at an interchange the nearest freeway may be the other one.
        #expect(fragment.trafficCount == nil)
        #expect(fragment.classification == nil)
    }

    @Test("A freeway segment named for the arterial it follows still speaks for the freeway")
    func stemMatch() async throws {
        // Through Scottsdale the NHS calls Loop 101 "PIMA RD": freeway class, state-owned, 10 m
        // from a pin the Census names "Pima Fwy".
        let scottsdale = RoadQuery(latitude: 33.44599, longitude: -111.89108)
        let source = NHSOwnershipSource(client: ArcGISClient(transport: FixtureTransport(
            ["National_Highway_System/MapServer/0": .fixture("nhs_pima_rd_named")])))
        var resolved = RoadRecord(query: scottsdale)
        resolved.segmentName = Attributed("Pima Fwy", provenance: provenance, confidence: .spatial)
        let fragment = try await source.fetch(scottsdale, resolved: resolved)
        #expect(fragment.owner?.value == .state(agency: "State highway agency"))
        #expect(fragment.trafficCount == nil)

        // The arterial itself, under its own name, is not the freeway.
        #expect(!HighwayName.isHighway("N Pima Rd"))
        #expect(HighwayName.sameStem("PIMA RD", "Pima Fwy"))
        #expect(!HighwayName.sameStem("PIMA RD", "Price Fwy"))
    }

    @Test("A matching route sign is a full match")
    func routeSignMatches() async throws {
        let fragment = try await nhs().fetch(pimaFwy, resolved: record(named: "State Rte 101"))
        #expect(fragment.owner?.confidence == .nameMatch)
        #expect(fragment.trafficCount?.value == 160_835)
    }

    @Test("A ramp takes its route's owner and nothing else")
    func rampTakesOwnerOnly() async throws {
        let fragment = try await nhs().fetch(pimaFwy, resolved: record(named: "SR-101 Exit 31 G-Ramp"))
        #expect(fragment.owner?.value == .state(agency: "State highway agency"))
        #expect(fragment.trafficCount == nil, "the main line's traffic is not the ramp's")
        #expect(fragment.classification == nil)
    }

    @Test("A frontage road is not the freeway it runs beside")
    func frontageIsNotTheRoute() async throws {
        #expect(!HighwayName.sameRoute("S101", "SR 101 Front"))
        #expect(!HighwayName.isHighway("SR 101 Front"))
        #expect(!HighwayName.isHighway("I-10 Frontage Rd"))
        let fragment = try await nhs().fetch(pimaFwy, resolved: record(named: "SR 101 Front"))
        #expect(fragment.owner == nil)
        #expect(fragment.trafficCount == nil)
    }

    @Test("The road across an interchange is not the interstate, and not a ramp")
    func crossingIsLocal() async throws {
        let crossing = "I-10 Exit 125 Crossing"
        #expect(!HighwayName.isHighway(crossing))
        #expect(!HighwayName.isRamp(crossing))
        #expect(!HighwayName.sameRoute("I10", crossing))
        #expect(HighwayName.isRamp("I-10 Exit 125 C-Ramp"))

        // So a city inference on it stands, labelled as one.
        var record = record(named: crossing)
        record.withholdImplausibleOwner()
        #expect(record.owner == phoenixInference())
    }

    @Test("A city street beside the freeway is not given the freeway's owner")
    func streetIsNotTheFreeway() async throws {
        let fragment = try await nhs().fetch(pimaFwy, resolved: record(named: "N Tatum Blvd"))
        #expect(fragment.owner == nil)
    }

    @Test("An owner read from the state's own layer is not second-guessed")
    func recordedOwnerSkips() async throws {
        let adot = Attributed(RoadOwner.state(agency: "Arizona Department of Transportation"),
                              provenance: provenance, confidence: .direct)
        let fragment = try await nhs().fetch(pimaFwy, resolved: record(named: "SR-101", owner: adot))
        #expect(fragment.owner == nil)
        #expect(fragment.notes.first?.outcome == .skipped)
    }
}
