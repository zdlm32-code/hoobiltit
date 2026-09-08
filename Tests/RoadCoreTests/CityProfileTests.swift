import Foundation
import Testing
@testable import RoadCore
@testable import RoadSources

private let fixedNow = Date(timeIntervalSince1970: 1_757_000_000)

@Suite("City street inventories")
struct CityProfileTests {
    /// Timber Oaks Dr, a residential street. Deliberately chosen in **Denton** County: the
    /// City of Dallas spans five counties, which is why coverage is keyed on place GEOID.
    let timberOaks = RoadQuery(latitude: 33.004114, longitude: -96.863239)
    /// Riojas Rd — one of the ~3,900 San Antonio segments with a genuine install date.
    let riojas = RoadQuery(latitude: 29.317093, longitude: -98.529270)
    /// Celtic — privately owned, and carrying the 2000-01-01 placeholder.
    let celtic = RoadQuery(latitude: 29.513130, longitude: -98.596123)

    private func dallas(_ transport: FixtureTransport) -> FlatInventorySource {
        FlatInventorySource(profile: CoverageCatalog.bundled.profile(forPlace: "4819000")!,
                            client: ArcGISClient(transport: transport), now: { fixedNow })!
    }
    private func sanAntonio(_ transport: FixtureTransport) -> FlatInventorySource {
        FlatInventorySource(profile: CoverageCatalog.bundled.profile(forPlace: "4865000")!,
                            client: ArcGISClient(transport: transport), now: { fixedNow })!
    }

    private var dallasStreet: FixtureTransport {
        FixtureTransport(["PavementCondition/FeatureServer/0": .fixture("dallas_pavement_timberoaks")])
    }

    // MARK: - Dallas

    @Test("A residential street says what was done to it, and when")
    func dallasRecordsTheWork() async throws {
        let fragment = try await dallas(dallasStreet).fetch(timberOaks)
        #expect(fragment.segmentName?.value == "TIMBER OAKS DR")
        let works = try #require(fragment.works?.value)
        let work = try #require(works.first)
        #expect(work.title == "Street Reconstruction")
        #expect(work.kind == .built, "rebuilding a street is not maintenance")
        #expect(CalendarDate.year(try #require(work.letDate)) == 2021)
        // The agency's own extent, which is more use than derived cross streets here.
        #expect(work.location == "18400-18500 TIMBER OAKS DR")
    }

    @Test("Sealing a street is never reported as building it")
    func sealingIsNotBuilding() {
        // Slurry Seal covers 6,549 Dallas segments and Street Reconstruction 6,577, so getting
        // this backwards would mis-answer about half the city.
        #expect(CodeTables.workKind(dallas: "Street Reconstruction") == .built)
        #expect(CodeTables.workKind(dallas: "Panel Replace (1-25%)") == .built)
        #expect(CodeTables.workKind(dallas: "Slurry Seal") == .maintained)
        #expect(CodeTables.workKind(dallas: "Microsurfacing") == .maintained)
        #expect(CodeTables.workKind(dallas: "Mill/Overlay (1-15% Patch)") == .maintained)
        // "None" is 11,007 segments and means no recorded work, not an unknown kind.
        // Both of these were misfiled as upkeep until probe.sh flagged them against the live
        // vocabulary; a full-depth rebuild is the most thorough work a city does to a street.
        #expect(CodeTables.workKind(dallas: "Full-Depth Asphalt") == .built)
        #expect(CodeTables.workKind(dallas: "Street Restoration") == .built)
        #expect(CodeTables.workKind(dallas: "Alley Improvement") == .maintained)
        #expect(CodeTables.workKind(dallas: "None") == nil)
        #expect(CodeTables.workKind(dallas: nil) == nil)
    }

    @Test("Dallas names the body, not just the level of government")
    func dallasOwnerIsNamed() async throws {
        let fragment = try await dallas(dallasStreet).fetch(timberOaks)
        #expect(fragment.owner?.value == .municipality(name: "City of Dallas",
                                                       fullName: "City of Dallas"))
        // maint_resp reads a bare "State" on a highway. The city tier runs first, so that
        // wording is what a Dallas freeway would show if it were not spelled out.
        #expect(CodeTables.owner(dallas: "State")
                == .state(agency: "Texas Department of Transportation"))
    }

    @Test("Pavement, condition and width come across as one fact")
    func dallasSurface() async throws {
        let fragment = try await dallas(dallasStreet).fetch(timberOaks)
        let surface = try #require(fragment.surface?.value)
        #expect(surface.type == "Concrete (JCP or CPCD)")
        #expect(surface.conditionRating == "B")
        // A letter grade is a proper noun; "condition b" reads as a typo.
        #expect(surface.conditionPhrase == "condition B")
        #expect(surface.widthFeet == 36)
    }

    @Test("A cul-de-sac is not described as running between a street and itself")
    func culDeSacCrossStreets() async throws {
        // Dallas writes from_name == to_name on a loop or dead end.
        let fragment = try await dallas(dallasStreet).fetch(timberOaks)
        #expect(fragment.crossStreets == nil)
    }

    // MARK: - San Antonio

    @Test("A genuine install date is kept")
    func sanAntonioRealDate() async throws {
        let transport = FixtureTransport(["Pavements/FeatureServer/0":
                                            .fixture("sanantonio_pavements_riojas")])
        let fragment = try await sanAntonio(transport).fetch(riojas)
        #expect(fragment.segmentName?.value == "RIOJAS RD")
        #expect(CalendarDate.year(try #require(fragment.yearLastImprovement?.value)) == 2022)
        #expect(fragment.owner?.value == .municipality(name: "San Antonio",
                                                       fullName: "San Antonio"))
    }

    /// The trap this profile exists to survive.
    @Test("The placeholder dates on 96% of San Antonio never reach the record")
    func sanAntonioSentinels() async throws {
        let transport = FixtureTransport(["Pavements/FeatureServer/0":
                                            .fixture("sanantonio_pavements_private")])
        let fragment = try await sanAntonio(transport).fetch(celtic)
        // InstallDate is populated on 100% of 98,986 segments and 96% of it is two values:
        // 2000-01-01 on 49,782 rows and 1980-01-01 on 45,272. Taken at face value the app
        // would invent a construction year for nearly every street in the city.
        #expect(fragment.yearLastImprovement == nil)
        #expect(fragment.yearLastConstruction == nil)
        // What is real still comes through.
        #expect(fragment.segmentName?.value == "CELTIC")
        #expect(fragment.owner?.value == .privateOwner)
    }

    @Test("A named owner is read as the body it names")
    func namedAgencies() {
        #expect(CodeTables.owner(named: "Bexar County") == .county(agency: "Bexar County"))
        #expect(CodeTables.owner(named: "Private") == .privateOwner)
        #expect(CodeTables.owner(named: "Property Owner") == .privateOwner)
        #expect(CodeTables.owner(named: "TxDOT")
                == .state(agency: "Texas Department of Transportation"))
        // Calling an air force base a municipality would be plainly wrong.
        if case .federal = CodeTables.owner(named: "Lackland AFB") {} else {
            Issue.record("Lackland AFB is federal")
        }
        if case .federal = CodeTables.owner(named: "Ft Sam Houston") {} else {
            Issue.record("Ft Sam Houston is federal")
        }
        if case .municipality(let name, _) = CodeTables.owner(named: "Alamo Heights") {
            #expect(name == "Alamo Heights")
        } else { Issue.record("a city name is a municipality") }
        // San Antonio's own "no value yet" marker, on 61 segments.
        #expect(CodeTables.owner(named: "TBD") == nil)
        #expect(CodeTables.owner(named: "") == nil)
    }

    // MARK: - The catalog and the pipeline

    @Test("A city is keyed on place, because a city is not inside one county")
    func placeKeying() {
        let catalog = CoverageCatalog.bundled
        #expect(catalog.profile(forPlace: "4819000")?.id == "tx.dallas.pavement")
        #expect(catalog.profile(forPlace: "4865000")?.id == "tx.sanantonio.pavement")
        #expect(catalog.profile(forPlace: "4835000") == nil, "Houston publishes no dates")
    }

    @Test("A city runs before the state, so its own answer is not overwritten")
    func cityOutranksTheState() {
        // TxDOT files every city street for HPMS and calls them all municipal. San Antonio
        // marks 11,017 of them Private, and running second would lose that on every street
        // TxDOT also carries — which is nearly all of them.
        let bexar = Jurisdiction(stateFIPS: "48", countyFIPS: "48029",
                                 countyName: "Bexar County", placeName: "San Antonio city",
                                 placeGEOID: "4865000")
        let ids = PipelineFactory().pipeline(for: bexar).sources.map(\.id)
        let city = try? #require(ids.firstIndex(of: "tx.sanantonio.pavement"))
        let state = try? #require(ids.firstIndex(of: "tx.txdot"))
        #expect(city != nil && state != nil && city! < state!)
    }

    @Test("A city lifts coverage without inventing a level")
    func cityCoverageLevel() {
        let dallasInDenton = Jurisdiction(stateFIPS: "48", countyFIPS: "48121",
                                          countyName: "Denton County",
                                          placeName: "Dallas city", placeGEOID: "4819000")
        let coverage = PipelineFactory().pipeline(for: dallasInDenton).coverage
        // Deliberately `.county`: CoverageLevel's Comparable force-unwraps a hardcoded array,
        // so a case missing from it crashes rather than failing to compile.
        #expect(coverage.level == .county)
        #expect(coverage.profileNames.contains("City of Dallas pavement management"))
    }

    @Test("A jurisdiction with no place is unaffected")
    func noPlaceIsFine() {
        let unincorporated = Jurisdiction(stateFIPS: "48", countyFIPS: "48201",
                                          countyName: "Harris County")
        let ids = PipelineFactory().pipeline(for: unincorporated).sources.map(\.id)
        #expect(!ids.contains { $0.hasPrefix("tx.dallas") || $0.hasPrefix("tx.sanantonio") })
    }
}
