import Foundation
import Testing
@testable import RoadCore
@testable import RoadSources

private let maricopa = Jurisdiction(stateFIPS: "04", countyFIPS: "04013",
                                    countyName: "Maricopa County", placeName: "Goodyear city")
private let philadelphia = Jurisdiction(stateFIPS: "42", countyFIPS: "42101",
                                        countyName: "Philadelphia County",
                                        placeName: "Philadelphia city")
private let eastBatonRouge = Jurisdiction(stateFIPS: "22", countyFIPS: "22033",
                                          countyName: "East Baton Rouge Parish")
private let harris = Jurisdiction(stateFIPS: "48", countyFIPS: "48201",
                                  countyName: "Harris County", placeName: "Houston city")
/// Puerto Rico, as the example of the national floor. This has been Texas, then Massachusetts,
/// then Wyoming, and each stopped qualifying by being mapped — with every state eventually in
/// the catalog there would be none left to point at. `Jurisdiction.stateNames` knows the
/// territories and the catalog will not hold one.
private let sanJuan = Jurisdiction(stateFIPS: "72", countyFIPS: "72127",
                                   countyName: "San Juan Municipio")

private func ids(_ jurisdiction: Jurisdiction?) -> [String] {
    PipelineFactory().pipeline(for: jurisdiction).sources.map(\.id)
}

@Suite("Pipeline selection by jurisdiction")
struct PipelineFactoryTests {
    /// The national tier runs everywhere and always last.
    let national = ["census.tiger", "fhwa.nhs", "usdot.nbi"]

    @Test("Maricopa still gets the v1 pipeline, in the v1 order")
    func maricopaIsUnchanged() {
        // The strongest available guard that the catalog machinery did not quietly change
        // what shipped. The order here is load-bearing: ADOT before MCDOT, because a pin on
        // I-10 sits inside Goodyear's city limits and the state must claim it before the
        // county source infers a municipal owner.
        let shipped = ["adot.atis", "adot.funding", "mcdot.rit", "mcdot.centerline",
                       "mcdot.declaration", "mcdot.projects", "mcassessor.parcels"]
        // ADOT's statewide HPMS table now trails the county sources rather than joining the
        // state ones. In the state slot it named an owner for every road in Arizona and so
        // beat MCDOT on Maricopa's own county roads, losing the distinction between a road the
        // county accepted and one it merely maintains as a courtesy.
        #expect(ids(maricopa) == shipped + ["az.adot"] + national)
        let order = ids(maricopa)
        #expect(order.firstIndex(of: "mcdot.rit")! < order.firstIndex(of: "az.adot")!)
        #expect(order.firstIndex(of: "adot.atis")! < order.firstIndex(of: "mcdot.rit")!)

        // v1 ran NBI between the county projects and the parcels. It now runs after them,
        // which is safe because the two touch disjoint fields — NBI writes `bridge`, the
        // parcel source writes `parcel` — and NBI's gate is a segment name, which the county
        // sources set well before either.
        #expect(order.firstIndex(of: "mcdot.rit")! < order.firstIndex(of: "usdot.nbi")!)
    }

    @Test("Pennsylvania resolves through the flat-inventory adapter")
    func pennsylvania() {
        #expect(ids(philadelphia) == ["pa.penndot"] + national)
        let coverage = PipelineFactory().pipeline(for: philadelphia).coverage
        #expect(coverage.level == .state)
        #expect(coverage.profileNames == ["PennDOT roadway inventory"])
    }

    @Test("Louisiana resolves through the LRS adapter")
    func louisiana() {
        #expect(ids(eastBatonRouge) == ["la.dotd"] + national)
        #expect(PipelineFactory().pipeline(for: eastBatonRouge).coverage.level == .state)
    }

    @Test("Texas resolves through the flat-inventory adapter")
    func texas() {
        // Harris County has no county profile, so Texas is state-tier only: TxDOT owns and
        // classifies the road, and the join gives it a name the national tier would otherwise
        // have had to supply.
        //
        // `tx.dcis` is appended by the catalog's `sourceIDs` even though the adapter is
        // generic, and it must run *after* the inventory, not instead of it.
        #expect(ids(harris) == ["tx.txdot", "tx.dcis"] + national)
        #expect(PipelineFactory().pipeline(for: harris).coverage.level == .state)
    }

    @Test("An unmapped county falls to the national tier alone")
    func unmappedCounty() {
        // Puerto Rico is not in the catalog. The app must still name the road rather than
        // going silent, and must say plainly that nothing local is mapped.
        #expect(ids(sanJuan) == national)
        let coverage = PipelineFactory().pipeline(for: sanJuan).coverage
        #expect(coverage.level == .national)
        #expect(coverage.profileNames.isEmpty)
    }

    @Test("A failed jurisdiction lookup still yields a working pipeline")
    func noJurisdiction() {
        // If TIGERweb is unreachable the app has no FIPS to route on. Returning an empty
        // pipeline would make the whole lookup fail; the national tier still answers.
        #expect(ids(nil) == national)
        #expect(PipelineFactory().pipeline(for: nil).coverage.level == .national)
    }

    @Test("An unknown source id in a catalog is skipped, not fatal")
    func unknownSourceIDIsSkipped() {
        var profile = CoverageProfile(id: "future.county", displayName: "Future", adapter: .bespoke)
        profile.sourceIDs = ["mcdot.rit", "not.a.real.source"]
        let catalog = CoverageCatalog(schemaVersion: 1, catalogVersion: 2, capturedOn: "2026-09-07",
                                      states: [:], counties: ["04013": profile])
        let sources = PipelineFactory(catalog: catalog).pipeline(for: maricopa).sources.map(\.id)
        #expect(sources == ["mcdot.rit"] + national)
    }
}

@Suite("Saying plainly what is not covered")
struct CoverageExplanationTests {
    private func record(name: String? = nil, owner: RoadOwner? = nil, built: Date? = nil) -> RoadRecord {
        var record = RoadRecord(query: RoadQuery(latitude: 29.7604, longitude: -95.3698))
        let provenance = Provenance(sourceID: "t", sourceName: "Test",
                                    url: URL(string: "https://example.org")!, fetchedAt: Date())
        if let name { record.segmentName = Attributed(name, provenance: provenance) }
        if let owner { record.owner = Attributed(owner, provenance: provenance) }
        if let built { record.yearLastConstruction = Attributed(built, provenance: provenance) }
        return record
    }

    @Test("An unmapped county names itself and the gap")
    func nationalTierExplains() throws {
        let coverage = Coverage(level: .national, jurisdiction: harris)
        let explanation = try #require(coverage.explanation(for: record(name: "Rusk St")))
        #expect(explanation.contains("Harris County, Texas"))
        #expect(explanation.contains("TIGER/Line"))
        // The sentence must attribute the gap to the app's coverage, not to the road. It is
        // fine to say TIGER carries no ownership; it is wrong to suggest the street is
        // unowned or unmaintained.
        let text = explanation.lowercased()
        #expect(text.contains("mapped"), "the gap is ours, not the road's")
        for wrong in ["road has no owner", "not owned", "no one maintains", "unmaintained"] {
            #expect(!text.contains(wrong))
        }
    }

    @Test("A state that cannot date local roads says so instead of showing a blank")
    func dateCaveatShown() throws {
        let coverage = Coverage(level: .state, jurisdiction: philadelphia,
                                profileNames: ["PennDOT roadway inventory"],
                                dateCaveats: ["PennDOT publishes a construction year only for roads it maintains itself."])
        let record = record(name: "SIXTEENTH ST", owner: .municipality(name: "Local government",
                                                                      fullName: "Local government"))
        let explanation = try #require(coverage.explanation(for: record))
        #expect(explanation.contains("only for roads it maintains itself"))
    }

    @Test("A complete answer needs no explanation")
    func nothingToExplain() {
        let coverage = Coverage(level: .state, jurisdiction: philadelphia,
                                dateCaveats: ["ignored when a date was found"])
        let complete = record(name: "SIXTEENTH ST",
                              owner: .state(agency: "PennDOT"),
                              built: CalendarDate.januaryFirst(ofYear: 1916))
        #expect(coverage.missing(in: complete).isEmpty)
        #expect(coverage.explanation(for: complete) == nil)
    }

    @Test("A bridge date counts as the dated leg")
    func anyDateSatisfiesTheBar() {
        // The bar chosen for this work is name, owner and *something* dated — the date may
        // come from any source, which is why an NBI structure on the road counts.
        var record = record(name: "Main St", owner: .county(agency: "County"))
        #expect(Coverage(level: .state, jurisdiction: nil).missing(in: record).contains(.date))
        record.bridge = Attributed(BridgeReference(carries: "Main St", crosses: "Dry Creek",
                                                   yearBuilt: 1927),
                                   provenance: Provenance(sourceID: "nbi", sourceName: "NBI",
                                                          url: URL(string: "https://example.org")!,
                                                          fetchedAt: Date()))
        #expect(!Coverage(level: .state, jurisdiction: nil).missing(in: record).contains(.date))
    }
}
