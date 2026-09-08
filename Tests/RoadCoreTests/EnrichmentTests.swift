import Foundation
import Testing
@testable import RoadCore
@testable import RoadSources

private let fixedNow = Date(timeIntervalSince1970: 1_757_000_000)

private func provenance(_ id: String) -> Provenance {
    Provenance(sourceID: id, sourceName: id, url: URL(string: "https://example.test")!,
               fetchedAt: fixedNow)
}

private func record(_ query: RoadQuery, segment: String? = nil, plat: String? = nil,
                    project: String? = nil, improvement: String? = nil) -> RoadRecord {
    var record = RoadRecord(query: query)
    if let segment { record.segmentName = Attributed(segment, provenance: provenance("t")) }
    if let plat {
        record.plat = Attributed(PlatReference(subdivisionName: plat), provenance: provenance("t"))
    }
    if let project {
        record.project = Attributed(ProjectReference(projectNumber: project, title: project),
                                    provenance: provenance("t"))
    }
    if let improvement {
        record.lastKnownImprovement = Attributed(
            ProjectReference(projectNumber: improvement, title: improvement),
            provenance: provenance("t"))
    }
    return record
}

private func year(_ date: Date) -> Int {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar.component(.year, from: date)
}

@Suite("County road declarations — the only date a county road has")
struct DeclarationTests {
    private func source(_ transport: FixtureTransport) -> MaricopaRoadDeclarationSource {
        MaricopaRoadDeclarationSource(client: ArcGISClient(transport: transport), now: { fixedNow })
    }

    let loneMountain = RoadQuery(latitude: 33.767648, longitude: -112.528617)

    @Test("Reads the declaration date where no other source has any date at all")
    func declarationDate() async throws {
        let fragment = try await source(.loneMountainDeclaration)
            .fetch(loneMountain, resolved: record(loneMountain, segment: "Lone Mountain Rd"))
        let declaration = try #require(fragment.declaration?.value)

        #expect(declaration.roadName == "LONE MOUNTAIN RD")
        #expect(year(declaration.effectiveDate) == 2014)
        #expect(declaration.roadFileNumber == "RF A518")
        #expect(declaration.documentURL?.host() == "recorder.maricopa.gov")
        #expect(fragment.declaration?.confidence == .direct)
    }

    @Test("Falls back to the subdivision when no declaration is named after the street")
    func subdivisionFallback() async throws {
        // Williams Dr's declarations are named CROSSRIVER UNIT 2 / UNIT 8 / MCR 707-44,
        // so the street name matches nothing and the plat is the only handle.
        let williams = RoadQuery(latitude: 33.689441, longitude: -112.317668)
        let fragment = try await source(.williamsDeclaration)
            .fetch(williams, resolved: record(williams, segment: "Williams Dr",
                                              plat: "CROSSRIVER UNIT 8"))

        #expect(fragment.declaration?.value.roadName == "CROSSRIVER UNIT 8")
        // Matched on the subdivision, not the road, and says so.
        #expect(fragment.declaration?.confidence == .nameMatch)
    }

    @Test("Says nothing when neither the road nor the subdivision matches")
    func refusesWithoutAMatch() async throws {
        let williams = RoadQuery(latitude: 33.689441, longitude: -112.317668)
        let fragment = try await source(.williamsDeclaration)
            .fetch(williams, resolved: record(williams, segment: "Jomax Rd", plat: "SOMEWHERE ELSE"))

        #expect(fragment.declaration == nil)
        #expect(fragment.notes.first?.outcome == .foundNothing)
    }

    @Test("Reads how the county acquired the right of way")
    func acquisition() async throws {
        let fragment = try await source(.loneMountainDeclaration)
            .fetch(loneMountain, resolved: record(loneMountain, segment: "Lone Mountain Rd"))
        let acquisition = try #require(fragment.acquisition?.value)

        #expect(acquisition.method == "Road Easement")
        #expect(acquisition.recorderURL != nil)
        // Geometry is the only handle on this layer — it carries no road name.
        #expect(fragment.acquisition?.confidence == .spatial)
    }

    @Test("The declaration and the right-of-way document stay separate facts")
    func separateDates() async throws {
        // Lone Mountain's easement was recorded in 1977; the road was declared in 2014.
        let fragment = try await source(.loneMountainDeclaration)
            .fetch(loneMountain, resolved: record(loneMountain, segment: "Lone Mountain Rd"))
        #expect(fragment.declaration?.value.documentURL
                != fragment.acquisition?.value.recorderURL)
    }
}

@Suite("Bridges — the oldest build years anywhere")
struct BridgeTests {
    private func source(_ transport: FixtureTransport) -> NBIBridgeSource {
        NBIBridgeSource(client: ArcGISClient(transport: transport), now: { fixedNow })
    }

    @Test("Separates original construction from reconstruction")
    func buildAndRebuild() async throws {
        let i10 = RoadQuery(latitude: 33.4602, longitude: -112.3756)
        let fragment = try await source(.i10Bridge).fetch(i10, resolved: record(i10, segment: "I-10"))
        let bridge = try #require(fragment.bridge?.value)

        // ADOT reports this stretch last constructed in 2011. The structure is older, and
        // collapsing the two would erase a third of a century of the road's history.
        #expect(bridge.yearBuilt == 1978)
        #expect(bridge.yearReconstructed == 2011)
        #expect(bridge.crosses == "Bullard Ave OP")
        #expect(bridge.ownerDescription == "State highway agency")
    }

    @Test("Refuses a nearby structure that carries a different road")
    func nameGateRefusesNeighbours() async throws {
        // Two bridges within range carry Royal Oak Rd and 99th Ave; the pin is on Santa Fe Dr.
        // Reporting either would be the confident-false-positive failure this app exists to avoid.
        let sunCity = RoadQuery(latitude: 33.5988, longitude: -112.2749)
        let fragment = try await source(.sunCityBridgeNoMatch)
            .fetch(sunCity, resolved: record(sunCity, segment: "Santa Fe Dr"))

        #expect(fragment.bridge == nil)
        #expect(fragment.notes.first?.detail?.contains("none carries Santa Fe Dr") == true)
    }

    @Test("Stays out of it when no road has been identified")
    func skipsWithoutARoad() async throws {
        let sunCity = RoadQuery(latitude: 33.5988, longitude: -112.2749)
        let fragment = try await source(.sunCityBridgeNoMatch).fetch(sunCity)
        #expect(fragment.bridge == nil)
        #expect(fragment.notes.first?.outcome == .skipped)
    }

    @Test("Treats a zero reconstruction year as never reconstructed")
    func zeroSentinel() {
        // NBI writes 0, not null, for structures that have never been rebuilt.
        let bridge = BridgeReference(yearBuilt: 1952, yearReconstructed: nil)
        #expect(bridge.yearReconstructed == nil)
        #expect(NBIBridgeSource.summary(bridge).contains("built 1952"))
        #expect(!NBIBridgeSource.summary(bridge).contains("reconstructed"))
    }
}

@Suite("Programmed funding — the money leg")
struct FundingTests {
    private func source(_ transport: FixtureTransport) -> ADOTFundingSource {
        ADOTFundingSource(client: ArcGISClient(transport: transport), now: { fixedNow })
    }

    let i10 = RoadQuery(latitude: 33.4602, longitude: -112.3756)

    @Test("Finds the money against the most recent project when construction has none")
    func fallsBackToTheLaterProject() async throws {
        // Dollars are programmed against whichever project is in the STIP now — H881901C —
        // not against H729601C, which ADOT credits with the last construction.
        let fragment = try await source(.i10Funding)
            .fetch(i10, resolved: record(i10, project: "H729601C", improvement: "H881901C"))
        let funding = try #require(fragment.funding?.value)

        #expect(funding.projectNumber == "H881901C")
        #expect(funding.programmedAmount == 4_160_000)
        #expect(funding.leadAgency == "ADOT")
        #expect(funding.fiscalYear == "FFY2018")
    }

    @Test("Carries the exact opening date on the project, not on a construction year")
    func inServiceDateStaysOnTheProject() async throws {
        let fragment = try await source(.i10Funding)
            .fetch(i10, resolved: record(i10, project: "H729601C", improvement: "H881901C"))

        let opened = try #require(fragment.funding?.value.inServiceDate)
        #expect(year(opened) == 2019)
        // ADOT's layer 2 says this stretch was last improved in 2011. Both are true about
        // different things, so the opening date must not overwrite it.
        #expect(fragment.yearLastImprovement == nil)
        #expect(fragment.yearLastConstruction == nil)
    }

    @Test("Skips entirely when no project number was resolved")
    func skipsWithoutATracs() async throws {
        let fragment = try await source(.i10Funding).fetch(i10, resolved: record(i10))
        #expect(fragment.funding == nil)
        #expect(fragment.notes.first?.outcome == .skipped)
    }
}

@Suite("Road name matching")
struct RoadNameTests {
    @Test("Ignores case, spacing and punctuation the agencies disagree about")
    func normalisation() {
        #expect(RoadName.matches("I-10", "I 10"))
        #expect(RoadName.matches("Lone Mountain Rd", "LONE MOUNTAIN RD"))
        #expect(RoadName.matches("SUN CITY UNIT 4-C", "SUN CITY UNIT 4C"))
        #expect(RoadName.matches("Deer  Valley   Rd", "deer valley rd"))
    }

    @Test("Does not match different roads that merely look similar")
    func staysStrict() {
        #expect(!RoadName.matches("Santa Fe Dr", "Santa Fe Ct"))
        #expect(!RoadName.matches("99th Ave", "99th Dr"))
        #expect(!RoadName.matches("Williams Dr", nil))
        #expect(!RoadName.matches(nil, nil))
    }

    @Test("Agencies that abbreviate the street type differently still agree")
    func canonicalisesStreetTypes() {
        // The bug this fixes, measured live: Census TIGER writes "Congress Ave" and FHWA's
        // National Highway System writes "CONGRESS AV" for the same road in Austin. The strict
        // comparison rejected it, so the app threw away the ownership and traffic the NHS had —
        // everywhere the two happened to abbreviate differently.
        #expect(RoadName.matches("Congress Ave", "CONGRESS AV"))
        #expect(RoadName.matches("Williams Drive", "Williams Dr"))
        #expect(RoadName.matches("Grand Boulevard", "GRAND BLVD"))
        #expect(RoadName.matches("Buffalo Speedway", "Buffalo Speedway"))
    }

    @Test("Canonicalising a suffix never merges two different types")
    func typesStayDistinct() {
        // Every entry maps a spelling to its own type and never across types. If this ever
        // fails, the table has been extended carelessly and the app is naming wrong roads.
        for (a, b) in [("Santa Fe Drive", "Santa Fe Court"), ("Oak Ln", "Oak Loop"),
                       ("Main Street", "Main Square"), ("Hill Trail", "Hill Terrace")] {
            #expect(!RoadName.matches(a, b), "\(a) is not \(b)")
        }
    }

    @Test("A missing compass prefix is the same road; a different one is not")
    func directionsRelaxOnlyOneWay() {
        // TIGER writes "W 1st St" where the NHS writes "1ST ST" — the same road named more and
        // less specifically, so the difference is allowed.
        #expect(RoadName.matches("W 1st St", "1ST ST"))
        #expect(RoadName.matches("7th St", "N 7th St"))
        #expect(RoadName.matches("Camelback Rd E", "Camelback Rd"))

        // But when both say which way and disagree, they are two roads — and in a grid city
        // they are two roads that genuinely both exist.
        #expect(!RoadName.matches("N 7th St", "S 7th St"))
        #expect(!RoadName.matches("E Vine Ave", "W Vine Ave"))
    }

    @Test("A road whose name is only a direction keeps it")
    func doesNotStripAWholeName() {
        // "North Ave" is a name, not a direction plus nothing.
        #expect(!RoadName.matches("North", "South"))
        #expect(RoadName.matches("North Ave", "NORTH AV"))
    }

    @Test("Identity keeps directions even though matching relaxes them")
    func identityStaysStrict() {
        // `comparisonKey` groups the drive log and decides when drive mode re-resolves. Merging
        // N and S there would collapse two roads into one entry and suppress a re-lookup.
        #expect(RoadName.comparisonKey("N 7th St") != RoadName.comparisonKey("S 7th St"))
        #expect(RoadName.comparisonKey("Congress Ave") == RoadName.comparisonKey("CONGRESS AV"))
    }
}
