import Foundation
import Testing
@testable import RoadCore
@testable import RoadSources

private let fixedNow = Date(timeIntervalSince1970: 1_757_000_000)

@Suite("Michigan and New York")
struct MichiganNewYorkTests {
    let michiganCounty = RoadQuery(latitude: 42.351103, longitude: -85.353241)
    let bronx = RoadQuery(latitude: 40.873498, longitude: -73.853299)
    let nyPrivate = RoadQuery(latitude: 42.561448, longitude: -74.060231)

    private func state(_ fips: String, _ route: String, _ fixture: String) -> FlatInventorySource {
        FlatInventorySource(profile: CoverageCatalog.bundled.profile(forState: fips)!,
                            client: ArcGISClient(transport: FixtureTransport([
                                route: .fixture(fixture)])),
                            now: { fixedNow })!
    }

    // MARK: - Michigan

    @Test("A four-part name is joined, and HPMS ownership needs no new table")
    func michigan() async throws {
        let fragment = try await state("26",
            "MDOTRHCenterline2025_Districts/FeatureServer/0", "mdot_county").fetch(michiganCounty)
        // FEDIRP + FENAME + FETYPE + FEDIRS.
        #expect(fragment.segmentName?.value == "N 42nd St")
        // Michigan's `Ownership` is the plain HPMS code space — 1, 2, 4, 40, 80 — so the
        // table shipped for Louisiana reads it unchanged.
        #expect(fragment.owner?.value == .county(agency: "County highway agency"))
    }

    @Test("Michigan publishes no date, and none is invented from the traffic year")
    func michiganHasNoDates() async throws {
        let fragment = try await state("26",
            "MDOTRHCenterline2025_Districts/FeatureServer/0", "mdot_county").fetch(michiganCounty)
        // `AADTYear` dates the traffic count, not the road.
        #expect(fragment.yearLastConstruction == nil)
        #expect(fragment.works == nil)
        let profile = try #require(CoverageCatalog.bundled.profile(forState: "26"))
        #expect(profile.fields?.yearBuilt == nil)
        #expect(profile.outFields?.contains("AADTYear") == false)
    }

    // MARK: - New York

    @Test("A city road is named after the borough that owns it")
    func newYorkCity() async throws {
        let fragment = try await state("36",
            "Geocortex/HDSV/MapServer/11", "nysdot_bronx").fetch(bronx)
        #expect(fragment.segmentName?.value == "BOSTON RD")
        // `OWNING_JURIS` 04 gives the level, `OWNED_BY_MUNI_NAME` the body.
        #expect(fragment.owner?.value == .municipality(name: "Bronx", fullName: "Bronx"))
    }

    @Test("A private road is private")
    func newYorkPrivate() async throws {
        let fragment = try await state("36",
            "Geocortex/HDSV/MapServer/11", "nysdot_private").fetch(nyPrivate)
        // HPMS 26, which New York labels "Private or not a public road".
        #expect(fragment.owner?.value == .privateOwner)
    }

    @Test("A state road can never be renamed after a municipality")
    func stateRoadsCarryNoMunicipality() throws {
        // The naming is safe only because of a total correlation: `OWNED_BY_MUNI_NAME` is null
        // on all 76,742 NYSDOT rows and present on all 109,379 city rows. Were that not so,
        // `renamed(to:)` would turn a state highway into a borough.
        let profile = try #require(CoverageCatalog.bundled.profile(forState: "36"))
        let rule = try #require(profile.fields?.ownershipRules?.first)
        #expect(rule.field == "OWNING_JURIS")
        #expect(rule.nameField == "OWNED_BY_MUNI_NAME")
        #expect(rule.table == .hpmsOwnership)
    }

    /// The trap this repo predicted years of sections ago.
    @Test("New York's functional class is not decoded with the FHWA table")
    func extendedFunctionalClassIsNotDecoded() throws {
        // `FUNC_CLASS` runs to 19 here — the two-digit extended scheme. Read through the FHWA
        // 1-7 table, 19 is nothing and 7 would mean something it does not.
        let profile = try #require(CoverageCatalog.bundled.profile(forState: "36"))
        #expect(profile.fields?.functionalClass == nil)
        #expect(profile.fields?.functionalClassTable == nil)
    }

    @Test("The statewide layer is used, not the federal-aid subsets")
    func usesTheFullLayer() throws {
        // Layers 1-4 are Federal Aid Eligible and hold 16,677 to 54,221 rows each; layer 11 is
        // Maintenance Jurisdiction and holds 394,175.
        let profile = try #require(CoverageCatalog.bundled.profile(forState: "36"))
        #expect(profile.layer == 11)
    }
}

@Suite("Louisville — found while looking for Indiana")
struct LouisvilleTests {
    let palRoad = RoadQuery(latitude: 38.236860, longitude: -85.776099)
    let oxmoor = RoadQuery(latitude: 38.242267, longitude: -85.615699)

    private func source(_ fixture: String) -> FlatInventorySource {
        FlatInventorySource(profile: CoverageCatalog.bundled.profile(forPlace: "2148000")!,
                            client: ArcGISClient(transport: FixtureTransport([
                                "Metro_Road_Paving_Condition_2025_PCI_View_layer/FeatureServer/0":
                                    .fixture(fixture)])),
                            now: { fixedNow })!
    }

    @Test("A Louisville street is owned by Louisville Metro")
    func metroStreet() async throws {
        let fragment = try await source("louisville_metro").fetch(palRoad)
        #expect(fragment.segmentName?.value == "PAL RD")
        #expect(fragment.owner?.value == .municipality(name: "Louisville Metro",
                                                       fullName: "Louisville Metro"))
    }

    @Test("A private street is private")
    func privateStreet() async throws {
        let fragment = try await source("louisville_private").fetch(oxmoor)
        #expect(fragment.owner?.value == .privateOwner)
    }

    /// Why every candidate is now checked at an in-state pin.
    @Test("This layer was returned by a search for Indiana, and is in Kentucky")
    func crossStateFalsePositive() throws {
        // Its owner names are Jefferson County suburbs — Jeffersontown, Shively, Middletown —
        // and it returns zero features at Indianapolis against 171 in downtown Louisville. It
        // is keyed to Louisville's place GEOID, so a pin in Indiana never reaches it.
        let catalog = CoverageCatalog.bundled
        #expect(catalog.profile(forPlace: "2148000")?.id == "ky.louisville.pavement")
        #expect(catalog.profile(forState: "18") == nil, "Indiana ships nothing")
    }

    @Test("An owner the city cannot name declines rather than guessing")
    func outOfJefferson() throws {
        let profile = try #require(CoverageCatalog.bundled.profile(forPlace: "2148000"))
        // "OUT OF JEFFERSON" says only that the road left the county.
        #expect(profile.fields?.ownerNames?["OUT OF JEFFERSON"] == "")
        #expect(profile.fields?.ownerNames?["METRO"] == "Louisville Metro")
    }
}

@Suite("Kentucky — acceptance is not ownership")
struct KentuckyTests {
    let lexingtonStreet = RoadQuery(latitude: 38.062568, longitude: -84.455213)
    let countyRoad = RoadQuery(latitude: 37.294323, longitude: -87.510226)

    private func source(_ fixture: String) -> FlatInventorySource {
        FlatInventorySource(profile: CoverageCatalog.bundled.profile(forState: "21")!,
                            client: ArcGISClient(transport: FixtureTransport([
                                "KYTC_-_State_Road_Assets_Flattened/FeatureServer/0":
                                    .fixture(fixture)])),
                            now: { fixedNow })!
    }

    @Test("A city road is named after its city, not the cabinet")
    func cityRoad() async throws {
        let fragment = try await source("kytc_city").fetch(lexingtonStreet)
        #expect(fragment.segmentName?.value == "BRYANWOOD PKWY")
        #expect(fragment.owner?.value == .municipality(name: "Lexington", fullName: "Lexington"))
    }

    @Test("The field called Ownership_Status is not ownership")
    func acceptanceIsNotOwnership() throws {
        // It reads ACCEPTED on 479,967 of 480,065 — it records whether the state took the road
        // into its system, not who keeps it. Route_Type is the signal.
        let profile = try #require(CoverageCatalog.bundled.profile(forState: "21"))
        let rules = try #require(profile.fields?.ownershipRules)
        #expect(rules.allSatisfy { $0.field == "Route_Type" })
        #expect(profile.fields?.ownership == nil)
    }

    /// The interaction that produced a municipality called "Cnty".
    @Test("A rule's rename map is not a whitelist, so every value is listed")
    func namesMapIsNotAWhitelist() async throws {
        // `ownerNames` rewrites a value before classification; a value it does not mention
        // falls through and is classified raw. With only CITY listed in the second rule, CNTY
        // reached `owner(named:)` and came back title-cased as a municipality named "Cnty".
        let profile = try #require(CoverageCatalog.bundled.profile(forState: "21"))
        for rule in try #require(profile.fields?.ownershipRules) {
            let names = try #require(rule.names)
            for routeType in ["KY", "US", "I", "PKWY", "CITY", "CNTY", "PRIV", "FED",
                              "PEND", "OTHR"] {
                #expect(names[routeType] != nil,
                        "\(routeType) is unlisted in a rule and would classify raw")
            }
        }
        // And the county road it produced now claims nothing.
        let fragment = try await source("kytc_county").fetch(countyRoad)
        #expect(fragment.segmentName?.value == "MAPLE LN")
        #expect(fragment.owner == nil)
    }
}

@Suite("Iowa and Portland")
struct IowaPortlandTests {
    let iowaCity = RoadQuery(latitude: 42.106342, longitude: -94.242141)
    let portland = RoadQuery(latitude: 45.512287, longitude: -122.687455)

    @Test("Iowa supplies the owner and leaves the naming to TIGER")
    func iowaOwnership() async throws {
        let source = FlatInventorySource(
            profile: CoverageCatalog.bundled.profile(forState: "19")!,
            client: ArcGISClient(transport: FixtureTransport([
                "Road_Network_View/FeatureServer/0": .fixture("iowadot_city")])),
            now: { fixedNow })!
        let fragment = try await source.fetch(iowaCity)
        #expect(fragment.owner?.value == .municipality(name: "City or municipal highway agency",
                                                       fullName: "City or municipal highway agency"))
        // Iowa's own name field prefixes the owner onto the road — "CITY OF DANA, ECKSTEIN
        // STREET" — and the short form still trails a direction, "S AVENUE, N". TIGER's is
        // better, so nothing is claimed here and TIGER names it.
        #expect(fragment.segmentName == nil)
        let profile = try #require(CoverageCatalog.bundled.profile(forState: "19"))
        #expect(profile.fields?.name == nil)
        #expect(profile.fields?.nameParts == nil)
    }

    @Test("Portland's owner field names the body with no rename table at all")
    func portlandOwnership() async throws {
        let source = FlatInventorySource(
            profile: CoverageCatalog.bundled.profile(forPlace: "4159000")!,
            client: ArcGISClient(transport: FixtureTransport([
                "TriMet_Road_Centerlines/FeatureServer/0": .fixture("trimet_portland")])),
            now: { fixedNow })!
        let fragment = try await source.fetch(portland)
        #expect(fragment.segmentName?.value == "HARRISON")
        #expect(fragment.owner?.value == .municipality(name: "City of Portland",
                                                       fullName: "City of Portland"))
        // 33 bodies, every shape already handled: a trailing "County" gives a county,
        // "Department of Transportation" the state, a city name a municipality.
        #expect(CodeTables.owner(named: "Washington County")
                == .county(agency: "Washington County"))
        #expect(CodeTables.owner(named: "Oregon Department of Transportation")
                == .state(agency: "Oregon Department of Transportation"))
        // "Unknown" on 3,224 rows says nothing and claims nothing.
        #expect(CodeTables.owner(named: "Unknown") == nil)
    }
}

@Suite("New Mexico — an event table, not a road network")
struct NewMexicoTests {
    let i25 = RoadQuery(latitude: 35.1050, longitude: -106.6295)

    @Test("A state highway is owned by the state")
    func stateHighway() async throws {
        let source = FlatInventorySource(
            profile: CoverageCatalog.bundled.profile(forState: "35")!,
            client: ArcGISClient(transport: FixtureTransport([
                "HPMS2026/FeatureServer/0": .fixture("nmdot_i25")])),
            now: { fixedNow })!
        let fragment = try await source.fetch(i25)
        #expect(fragment.owner?.value == .state(agency: "State highway agency"))
        // No name field exists on the layer, so TIGER names the road.
        #expect(fragment.segmentName == nil)
    }

    @Test("Only three fields are requested, and that is deliberate")
    func narrowOutFields() throws {
        // 2,898,383 rows is not 2.9 million roads: it is the same roads split at every
        // attribute change. A 150 m envelope returns 1,840 features and about 350 KB even
        // asking for three fields — the largest per-lookup payload of any profile shipped.
        let profile = try #require(CoverageCatalog.bundled.profile(forState: "35"))
        let requested = try #require(profile.outFields)
        #expect(requested.count <= 3)
        #expect(profile.fields?.functionalClass == nil, "not worth the bytes")
    }
}
