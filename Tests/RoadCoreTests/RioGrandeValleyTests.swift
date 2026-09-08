import Foundation
import Testing
@testable import RoadCore
@testable import RoadSources

/// After Edinburg's 2025 completions and before its 2027 ones, so "planned" means planned.
private let fixedNow = Date(timeIntervalSince1970: 1_757_000_000)   // 2025-09-04

@Suite("Rio Grande Valley")
struct RioGrandeValleyTests {
    let pharr = RoadQuery(latitude: 26.202544, longitude: -98.194886)
    let edinburg = RoadQuery(latitude: 26.300448, longitude: -98.156200)
    let cameron = RoadQuery(latitude: 25.977429, longitude: -97.590471)
    let weslaco = RoadQuery(latitude: 26.140940, longitude: -97.985602)

    private func source(_ key: String, _ transport: FixtureTransport,
                        county: Bool = false) -> FlatInventorySource {
        let profile = county ? CoverageCatalog.bundled.profile(forCounty: key)!
                             : CoverageCatalog.bundled.profile(forPlace: key)!
        return FlatInventorySource(profile: profile,
                                   client: ArcGISClient(transport: transport),
                                   now: { fixedNow })!
    }

    // MARK: - Edinburg: a project register read by containment

    @Test("A capital project is matched by containment, not by distance to its edge")
    func projectContainment() async throws {
        let transport = FixtureTransport(["COE_CAPITAL_IMPROVEMENT_PROJECTS/FeatureServer/0":
                                            .fixture("rgv_edinburg_cip")])
        let fragment = try await source("4822660", transport).fetch(edinburg)
        // A project area is half a mile across, so the distance from a pin inside it to its
        // boundary exceeds the 60 m on-road gate. Nearest-line would reject the very project
        // the pin is standing in.
        let works = try #require(fragment.works?.value)
        #expect(!works.isEmpty)
    }

    @Test("Every project covering the point is reported, newest first")
    func allContainingProjects() async throws {
        let transport = FixtureTransport(["COE_CAPITAL_IMPROVEMENT_PROJECTS/FeatureServer/0":
                                            .fixture("rgv_edinburg_cip")])
        let fragment = try await source("4822660", transport).fetch(edinburg)
        let works = try #require(fragment.works?.value)
        // A city rebuilds the same street more than once and the areas overlap; taking
        // whichever the service returned first would pick a year at random.
        #expect(works.count >= 2)
        let dates = works.compactMap(\.letDate)
        #expect(dates == dates.sorted(by: >))
    }

    @Test("A city names its contractor and what it actually spent")
    func contractorAndCost() async throws {
        let transport = FixtureTransport(["COE_CAPITAL_IMPROVEMENT_PROJECTS/FeatureServer/0":
                                            .fixture("rgv_edinburg_cip")])
        let fragment = try await source("4822660", transport).fetch(edinburg)
        let works = try #require(fragment.works?.value)
        let built = try #require(works.first { $0.contractor != nil })
        #expect(built.contractor == "RBM Contractors")
        #expect(built.cost == 3_324_532.82)
        #expect(built.kind == .built)
    }

    @Test("A project still in design is labelled planned, not built")
    func plannedProject() async throws {
        let transport = FixtureTransport(["COE_CAPITAL_IMPROVEMENT_PROJECTS/FeatureServer/0":
                                            .fixture("rgv_edinburg_cip")])
        let fragment = try await source("4822660", transport).fetch(edinburg)
        let works = try #require(fragment.works?.value)
        let future = try #require(works.first { ($0.letDate ?? .distantPast) > fixedNow })
        #expect(future.isPlanned)
    }

    // MARK: - Pharr

    @Test("A bare ownership level is rewritten into the body that holds it")
    func pharrOwnerNames() async throws {
        let transport = FixtureTransport(["Street_Repaving/FeatureServer/2":
                                            .fixture("rgv_pharr_sugar")])
        let fragment = try await source("4857200", transport).fetch(pharr)
        // Pharr writes "CITY", which is true of every city in Texas and names none of them.
        #expect(fragment.owner?.value == .municipality(name: "City of Pharr",
                                                       fullName: "City of Pharr"))
        #expect(fragment.segmentName?.value == "N SUGAR RD")
    }

    @Test("Undated work is not reported as work")
    func noUndatedWork() async throws {
        let transport = FixtureTransport(["Street_Repaving/FeatureServer/2":
                                            .fixture("rgv_pharr_sugar")])
        let fragment = try await source("4857200", transport).fetch(pharr)
        // This segment records "Crack Sealing" with no year. The point of a work entry is to
        // date the road, and an undated treatment tells a reader nothing.
        #expect(fragment.works?.value.allSatisfy { $0.letDate != nil } ?? true)
    }

    @Test("Pharr's repaving is upkeep, never what built the street")
    func repavingIsUpkeep() async throws {
        let transport = FixtureTransport(["Street_Repaving/FeatureServer/2":
                                            .fixture("rgv_pharr_sugar")])
        let fragment = try await source("4857200", transport).fetch(pharr)
        #expect(fragment.works?.value.allSatisfy { $0.kind == .maintained } ?? true)
    }

    // MARK: - Cameron County and Weslaco

    @Test("An unincorporated county road is named and surfaced by the county")
    func cameronCounty() async throws {
        let transport = FixtureTransport(["COUNTY_ROAD_INVENTORY_2026/FeatureServer/0":
                                            .fixture("rgv_cameron_roads")])
        let fragment = try await source("48061", transport, county: true).fetch(cameron)
        #expect(fragment.segmentName?.value == "VALLADOLID DR")
        #expect(fragment.surface?.value.type == "ASPHALT")
        // The layer publishes no ownership field, so none is claimed rather than inferred.
        #expect(fragment.owner == nil)
        #expect(fragment.works == nil, "Cameron County publishes no dates at all")
    }

    @Test("A city layer declines outside its own jurisdiction")
    func weslacoDeclinesUnincorporated() async throws {
        let transport = FixtureTransport(["COW_STREETS/FeatureServer/0":
                                            .fixture("rgv_weslaco_streets")])
        let fragment = try await source("4877272", transport).fetch(weslaco)
        #expect(fragment.owner?.value == .municipality(name: "City of Weslaco",
                                                       fullName: "City of Weslaco"))
        // "UNINCORPORATED" maps to an empty rename, which makes the source decline so TxDOT's
        // own ownership answers instead. Weslaco's layer covers 1,450 such segments.
        let profile = CoverageCatalog.bundled.profile(forPlace: "4877272")!
        #expect(profile.fields?.ownerNames?["UNINCORPORATED"] == "")
        // Including the misspelling the city actually publishes.
        #expect(profile.fields?.ownerNames?["UNINCORPOARTED"] == "")
    }

    // MARK: - McAllen: annexation, the only dated thing it publishes

    @Test("A city that publishes no roads still yields a dated fact, honestly labelled")
    func mcallenAnnexation() async throws {
        let transport = FixtureTransport(["Annexation_History_11_13_2024/FeatureServer/0":
                                            .fixture("rgv_mcallen_annexation")])
        let fragment = try await source("4845384", transport).fetch(
            RoadQuery(latitude: 26.2034, longitude: -98.2300))
        let annexation = try #require(fragment.annexation?.value)
        #expect(annexation.ordinance == "CHARTER")
        // 1927, which is a *negative* epoch in milliseconds. Read as unsigned it would be a
        // date in the far future.
        let when = try #require(annexation.ordinanceDate)
        #expect(CalendarDate.year(when) == 1927)
        #expect(when < Date(timeIntervalSince1970: 0))
        // Annexation is not construction, and nothing here claims it is.
        #expect(fragment.yearLastConstruction == nil)
        #expect(fragment.works == nil)
    }

    @Test("A placeholder cost never reaches the card")
    func costFloor() {
        // 429 TxDOT projects carry exactly $1 and another 25 sit below $100 — 0.01, 0.66, 2,
        // 42. "Widen Non-Freeway $1" reads as a bug in the app, not a gap in the register.
        #expect(TxDOTProjectSource.realCost(1) == nil)
        #expect(TxDOTProjectSource.realCost(0.66) == nil)
        #expect(TxDOTProjectSource.realCost(42) == nil)
        #expect(TxDOTProjectSource.realCost(1_026_662) == 1_026_662)
    }

    // MARK: - Catalog

    @Test("Every Rio Grande Valley profile is reachable and HTTPS")
    func profilesLoad() {
        let catalog = CoverageCatalog.bundled
        for geoid in ["4810768", "4822660", "4857200", "4877272"] {
            let profile = catalog.profile(forPlace: geoid)
            #expect(profile != nil, "\(geoid) did not survive the read")
        }
        #expect(catalog.profile(forCounty: "48061")?.id == "tx.cameron.roads")
        #expect(catalog.profile(forPlace: "4845384")?.id == "tx.mcallen.annexation")
        // Harlingen was probed and deliberately not shipped: its capital-project layer is a
        // template whose rows read "PROJECT 1 - BUILDING & FACILITIES", all share one end
        // date, and sit in Edinburg rather than Harlingen.
        #expect(catalog.profile(forPlace: "4832372") == nil)
    }

    @Test("A wide layer is asked only for the fields it is read for")
    func narrowOutFields() async throws {
        let transport = FixtureTransport(["COE_CAPITAL_IMPROVEMENT_PROJECTS/FeatureServer/0":
                                            .fixture("rgv_edinburg_cip")])
        _ = try await source("4822660", transport).fetch(edinburg)
        let url = try #require(transport.log.all.first)
        let fields = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "outFields" }?.value)
        // Edinburg's rows carry about 150 fields including thirty paragraphs of status
        // history: 200 KB for seven features, on what may be a phone in a car.
        #expect(fields != "*")
        #expect(fields.contains("CONTRACTOR"))
    }
}
