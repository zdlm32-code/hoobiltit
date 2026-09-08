import Foundation
import Testing
@testable import RoadCore

@Suite("Coverage catalog")
struct CoverageCatalogTests {
    @Test("The bundled catalog decodes and is dated")
    func bundledLoads() throws {
        let catalog = CoverageCatalog.bundled
        #expect(catalog.schemaVersion == CoverageCatalog.supportedSchema)
        #expect(catalog.catalogVersion > 0)
        let captured = try #require(catalog.capturedDate)
        #expect(captured > Date(timeIntervalSince1970: 1_700_000_000))
    }

    @Test("A profile omitting an optional key still decodes")
    func omittedKeysDoNotEmptyTheCatalog() throws {
        // A synthesised Decodable throws on a missing key even when the property has a
        // default value, and `CoverageCatalog.bundled` falls back to an *empty* catalog on
        // any decode error. So one omitted field silently drops every jurisdiction in the
        // country to the national tier, with no error anywhere. It happened once already.
        let minimal = """
        {"schemaVersion":1,"catalogVersion":7,"capturedOn":"2026-09-07",
         "states":{"42":{"id":"x","displayName":"X","adapter":"flatInventory",
                         "service":"https://example.org/a/MapServer","layer":0}},
         "counties":{}}
        """
        let catalog = try JSONDecoder().decode(CoverageCatalog.self, from: Data(minimal.utf8))
        let profile = try #require(catalog.profile(forState: "42"))
        #expect(profile.requiredSchema == 1, "defaults apply on read, not at decode")
        #expect(profile.drawsParcels == false)
        // The same trap one level up: this JSON has no `places` key at all, which is what
        // every catalog published before the city tier existed looks like. It must load the
        // states and counties it does have rather than failing whole.
        #expect(catalog.placeProfiles.isEmpty)
        #expect(catalog.profile(forPlace: "4819000") == nil)
    }

    @Test("Only the most local caveat is shown, not all of them joined")
    func oneCaveat() {
        // A pin in Brownsville consults a city, a state and a county profile. Joined, their
        // three sentences became a paragraph saying the same thing three ways.
        var record = RoadRecord(query: RoadQuery(latitude: 25.9015, longitude: -97.4975))
        record.segmentName = Attributed("E 12TH ST",
            provenance: Provenance(sourceID: "x", sourceName: "X",
                                   url: URL(string: "https://example.com")!, fetchedAt: Date()),
            confidence: .spatial)
        let coverage = Coverage(level: .county, jurisdiction: nil,
                                profileNames: ["City", "State", "County"],
                                dateCaveats: ["The city publishes no dates.",
                                              "The state publishes none either.",
                                              "Nor does the county."])
        let explanation = try? #require(coverage.explanation(for: record))
        #expect(explanation == "The city publishes no dates.")
        // And the short form has always agreed with that.
        #expect(coverage.shortDateNote(for: record)?.isEmpty == false)
    }

    @Test("The bundled catalog's places survive the read")
    func placesLoad() throws {
        let catalog = CoverageCatalog.bundled
        #expect(!catalog.placeProfiles.isEmpty)
        for geoid in catalog.placeProfiles.keys {
            #expect(catalog.profile(forPlace: geoid) != nil, "\(geoid) did not survive")
            #expect(geoid.count == 7, "a place GEOID is state FIPS plus five digits")
        }
    }

    @Test("Every entry in the bundled catalog survives the read, not just the file")
    func bundledIsNotTheEmptyFallback() {
        // Guards the same failure from the other side: the fallback is a valid empty catalog,
        // so a decode failure looks like "no coverage anywhere" rather than like an error.
        let catalog = CoverageCatalog.bundled
        #expect(!catalog.states.isEmpty)
        #expect(!catalog.counties.isEmpty)
        for fips in catalog.states.keys { #expect(catalog.profile(forState: fips) != nil) }
        for fips in catalog.counties.keys { #expect(catalog.profile(forCounty: fips) != nil) }
    }

    @Test("Pennsylvania is described as a flat inventory keyed on JURIS")
    func pennsylvania() throws {
        let pa = try #require(CoverageCatalog.bundled.profile(forState: "42"))
        #expect(pa.adapter == .flatInventory)
        #expect(pa.layer == 0)
        let fields = try #require(pa.fields)
        #expect(fields.name == ["STREET_NAME"])
        // The whole PennDOT trap in one assertion.
        #expect(fields.ownership == "JURIS")
        #expect(fields.ownership != "MAINT_RESPON_IND")
        #expect(fields.ownershipTable == .penndotJurisdiction)
        #expect(fields.ownershipTable != .hpmsOwnership)
        // Without this every local Pennsylvania road reports a build year of 0.
        #expect(fields.nullNumbers == [0])
        #expect(pa.dateCaveat != nil, "PA cannot date local roads and must say so")
    }

    @Test("Louisiana joins events, with the dedicated ownership table ahead of the route layer's copy")
    func louisiana() throws {
        let la = try #require(CoverageCatalog.bundled.profile(forState: "22"))
        #expect(la.adapter == .lrsEvents)
        #expect(la.routeLayer == 49)
        let events = try #require(la.eventLayers)
        #expect(events.map(\.layer) == [91, 69, 70, 84])
        // Layers 49 and 91 disagree about Balis Dr; 91 is the dedicated HPMS table.
        #expect(events.first?.fields.ownership == "Ownership")
        #expect(events.first?.fields.ownershipTable == .hpmsOwnership)
        #expect(la.dateCaveat != nil)
    }

    @Test("Arizona keeps its hand-written sources, with the statewide table behind them")
    func arizonaStaysBespoke() throws {
        let az = try #require(CoverageCatalog.bundled.profile(forState: "04"))
        // Arizona reads the statewide HPMS tables through the generic LRS adapter *and* keeps
        // its two compiled sources, which run first and are followed by the table only where
        // they found nothing.
        #expect(az.adapter == .lrsEvents)
        #expect(az.sourceIDs == ["adot.atis", "adot.funding"])
        #expect(az.runsCompiledFirst)
        #expect(az.eventLayers?.contains { $0.fields.ownershipTable == .adotOwnership } == true)

        let maricopa = try #require(CoverageCatalog.bundled.profile(forCounty: "04013"))
        #expect(maricopa.adapter == .bespoke)
        #expect(maricopa.drawsParcels, "the parcel overlay is gated on this")
        #expect(CoverageCatalog.bundled.profile(forState: "42")?.drawsParcels == false)
        #expect(maricopa.sourceIDs == ["mcdot.rit", "mcdot.centerline", "mcdot.declaration",
                                       "mcdot.projects", "mcassessor.parcels"])
    }

    @Test("An entry from a future schema is skipped without taking the catalog down")
    func futureEntryDegradesAlone() throws {
        var future = CoverageProfile(id: "future", displayName: "Future", adapter: .flatInventory)
        future.minSchema = CoverageCatalog.supportedSchema + 1
        future.service = "https://example.org/arcgis/rest/services/X/MapServer"
        let known = try #require(CoverageCatalog.bundled.profile(forState: "42"))

        let catalog = CoverageCatalog(schemaVersion: 99, catalogVersion: 2,
                                      capturedOn: "2026-09-07",
                                      states: ["99": future, "42": known], counties: [:])
        #expect(catalog.profile(forState: "99") == nil, "the future entry is skipped")
        #expect(catalog.profile(forState: "42") != nil, "its neighbour still loads")
    }

    @Test("A catalog may only point the app at HTTPS")
    func plaintextEntryRejected() {
        var insecure = CoverageProfile(id: "bad", displayName: "Bad", adapter: .flatInventory)
        insecure.service = "http://example.org/arcgis/rest/services/X/MapServer"
        let catalog = CoverageCatalog(schemaVersion: 1, catalogVersion: 2, capturedOn: "2026-09-07",
                                      states: ["99": insecure], counties: [:])
        // The catalog decides which hosts the app calls; a plaintext URL is a redirect
        // primitive, not a typo.
        #expect(catalog.profile(forState: "99") == nil)
    }

    @Test("A stale download never displaces a newer bundled catalog")
    func bundledWinsWhenNewer() {
        let bundled = CoverageCatalog(schemaVersion: 1, catalogVersion: 5, capturedOn: "2026-09-07",
                                      states: [:], counties: [:])
        let stale = CoverageCatalog(schemaVersion: 1, catalogVersion: 4, capturedOn: "2026-01-01",
                                    states: [:], counties: [:])
        let fresh = CoverageCatalog(schemaVersion: 1, catalogVersion: 6, capturedOn: "2026-10-01",
                                    states: [:], counties: [:])
        #expect(CoverageCatalog.newer(stale, than: bundled).catalogVersion == 5)
        #expect(CoverageCatalog.newer(fresh, than: bundled).catalogVersion == 6)
        #expect(CoverageCatalog.newer(nil, than: bundled).catalogVersion == 5)
    }

    @Test("Coverage levels order from thinnest to deepest")
    func levelOrdering() {
        #expect(CoverageLevel.national < CoverageLevel.state)
        #expect(CoverageLevel.state < CoverageLevel.county)
        #expect(CoverageLevel.allCases.max() == .county)
    }
}
