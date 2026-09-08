import Foundation
import Testing
@testable import RoadCore

private func provenance() -> Provenance {
    Provenance(sourceID: "t", sourceName: "Test", url: URL(string: "https://example.test")!,
               fetchedAt: Date(timeIntervalSince1970: 1_757_000_000))
}

private var populatedRecord: RoadRecord {
    var record = RoadRecord(query: RoadQuery(latitude: 33.689441, longitude: -112.317668))
    record.segmentName = Attributed("Williams Dr", provenance: provenance())
    record.crossStreets = Attributed("El Mirage Rd to Deer Valley Rd", provenance: provenance())
    record.jurisdiction = Attributed("Unincorporated Maricopa County", provenance: provenance())
    record.owner = Attributed(.county(agency: "Maricopa County Department of Transportation"),
                              provenance: provenance())
    record.project = Attributed(ProjectReference(projectNumber: "TT0248", title: "Deer Valley Road"),
                                provenance: provenance())
    record.plat = Attributed(PlatReference(subdivisionName: "CROSSRIVER UNIT 8",
                                           recorderNumber: "706-34"), provenance: provenance())
    record.supervisorDistrict = Attributed(4, provenance: provenance())
    record.declaration = Attributed(
        RoadDeclaration(roadName: "CROSSRIVER UNIT 8", roadFileNumber: "RF 5819",
                        effectiveDate: Date(timeIntervalSince1970: 1_242_777_600)),
        provenance: provenance())
    record.maintenanceDistrict = Attributed("Northwest", provenance: provenance())
    record.coverage = Coverage(level: .county,
                               jurisdiction: Jurisdiction(stateFIPS: "04", countyFIPS: "04013",
                                                          countyName: "Maricopa County"))
    return record
}

@Suite("Public records request — the fallback that answers what no API will")
struct RecordsRequestTests {
    @Test("Routes each owner to the right agency, and admits when it cannot")
    func routing() {
        let directory = AgencyDirectory.bundled
        let AZ = "04"
        #expect(directory.agency(for: .county(agency: "x"), inState: AZ)?.id == "mcdot")
        // A courtesy-maintained road is still MCDOT's to ask.
        #expect(directory.agency(for: .countyCourtesy(agency: "x"), inState: AZ)?.id == "mcdot")
        // A state road routes on the agency's own name, not on the assumption that every
        // state road is Arizona's. Before the app went national this returned ADOT for any
        // state owner at all, which would hand a Pennsylvania driver Arizona's records office.
        #expect(directory.agency(for: .state(agency: "Arizona Department of Transportation"),
                                 inState: AZ)?.id == "adot")
        #expect(directory.agency(for: .state(agency: "Pennsylvania Department of Transportation"),
                                 inState: AZ) == nil)
        #expect(directory.agency(for: .municipality(name: "GOODYEAR", fullName: "City of Goodyear"),
                                 inState: AZ)?.id == "goodyear")
        // No bundled entry beats a wrong address.
        #expect(directory.agency(for: .municipality(name: "TOLLESON", fullName: "City of Tolleson"),
                                 inState: AZ) == nil)
        #expect(directory.agency(for: .undetermined, inState: AZ) == nil)
        #expect(directory.agency(for: .privateOwner, inState: AZ) == nil)
        // A name too short to be meaningful must not match by accident: "X" is inside
        // "CITY OF PHOENIX".
        #expect(directory.agency(for: .state(agency: "x"), inState: AZ) == nil)
    }

    @Test("The bundled directory loads and is dated")
    func directoryLoads() {
        #expect(!AgencyDirectory.bundled.agencies.isEmpty)
        #expect(AgencyDirectory.bundled.capturedOn > Date(timeIntervalSince1970: 1_700_000_000))
    }

    @Test("Quotes every identifier that would help a records officer find the file")
    func citesIdentifiers() {
        let draft = RecordsRequest.draft(for: populatedRecord,
                                         agency: AgencyDirectory.bundled.agency(
                                            for: .county(agency: "x"), inState: "04"))
        for expected in ["Williams Dr", "El Mirage Rd to Deer Valley Rd", "TT0248",
                         "CROSSRIVER UNIT 8", "706-34", "Northwest", "Board of Supervisors district", "33.689441", "RF 5819"] {
            #expect(draft.contains(expected), "draft should cite \(expected)")
        }
        #expect(draft.contains("A.R.S. § 39-121"), "an Arizona road cites Arizona's statute")
        #expect(draft.contains("Maricopa County Department of Transportation"))
        // The contractor and award are the whole point of sending it.
        #expect(draft.contains("contractor"))
        #expect(draft.contains("award"))
    }

    @Test("Still produces a usable request when almost nothing resolved")
    func degradesToACoordinate() {
        let sparse = RoadRecord(query: RoadQuery(latitude: 33.5, longitude: -112.4))
        let draft = RecordsRequest.draft(for: sparse, agency: nil)

        #expect(draft.contains("33.500000, -112.400000"))
        // No jurisdiction resolved, so no statute is known — and the letter cites none rather
        // than citing whichever state happened to be hard-coded.
        #expect(draft.contains("Under your state's public records law"))
        #expect(!draft.contains("A.R.S."))
        // No agency, so it must not name one.
        #expect(draft.contains("the agency responsible for this road"))
    }

    @Test("Cites the statute of the state the road is in, and never another state's")
    func statuteFollowsTheState() {
        // A single `static let` held Arizona's citation and printed it into every letter the
        // app drafted. Nineteen states are covered, so eighteen were being told Arizona law
        // obliged them to answer.
        #expect(RecordsRequest.statute(forState: "39") == "Ohio Rev. Code § 149.43")
        #expect(RecordsRequest.statute(forState: "48") == "Tex. Gov't Code § 552.021")
        #expect(RecordsRequest.statute(forState: "04") == "A.R.S. § 39-121")
        // A state this build does not cover cites nothing rather than somebody else's law.
        #expect(RecordsRequest.statute(forState: "06") == nil)
        #expect(RecordsRequest.statute(forState: nil) == nil)

        var ohio = RoadRecord(query: RoadQuery(latitude: 40.7329, longitude: -84.1050))
        ohio.coverage = Coverage(level: .state,
                                 jurisdiction: Jurisdiction(stateFIPS: "39", countyFIPS: "39003",
                                                            countyName: "Allen County"))
        let draft = RecordsRequest.draft(for: ohio, agency: nil)
        #expect(draft.contains("Ohio Rev. Code § 149.43"))
        #expect(!draft.contains("A.R.S."), "Arizona's statute must not reach an Ohio letter")
    }

    @Test("A same-named city in another state gets no agency at all")
    func doesNotCrossStateLines() {
        let directory = AgencyDirectory.bundled
        // Every bundled agency is Arizona's. Matching was a bidirectional substring test with
        // no idea where the pin was, so Phoenix, Oregon addressed its request to Phoenix,
        // Arizona — and a county owner returned MCDOT in all fifty states.
        let phoenix = RoadOwner.municipality(name: "PHOENIX", fullName: "City of Phoenix")
        #expect(directory.agency(for: phoenix, inState: "04")?.id == "phoenix")
        #expect(directory.agency(for: phoenix, inState: "41") == nil, "Phoenix, Oregon is not Phoenix, Arizona")
        #expect(directory.agency(for: .county(agency: "Franklin County"), inState: "39") == nil,
                "an Ohio county is not Maricopa County")
        #expect(directory.agency(for: .county(agency: "x"), inState: nil) == nil)
    }

    @Test("The letter carries its own caveat, because the screen's footer does not travel")
    func draftMarker() {
        let draft = RecordsRequest.draft(for: populatedRecord, agency: nil)
        #expect(draft.hasPrefix("[DRAFT"))
        // It must not assert the sender's own purpose: that is a statement about the user's
        // intent with fee consequences under many states' records laws, and the app cannot
        // know it.
        #expect(!draft.contains("non-commercial"))
    }
}

@Suite("An inferred owner says so, on every surface that shows it")
struct InferredOwnerTests {
    private func owned(_ owner: RoadOwner, _ confidence: MatchConfidence) -> Attributed<RoadOwner> {
        Attributed(owner,
                   provenance: Provenance(sourceID: "t", sourceName: "Test",
                                          url: URL(string: "https://example.test")!,
                                          fetchedAt: Date(timeIntervalSince1970: 1_757_000_000)),
                   confidence: confidence)
    }

    @Test("A derived owner is marked inferred; a read one is not")
    func marksOnlyWhatWasInferred() {
        // "Not publicly maintained" is reached from the *absence* of a maintenance record, and
        // the drive card, the drive log and the CSV all printed it as a flat assertion.
        #expect(owned(.notPubliclyMaintained, .derived).displayNameWithConfidence
                == "Not publicly maintained (inferred)")
        // Read straight out of an agency's own field, so nothing is added.
        #expect(owned(.privateOwner, .direct).displayNameWithConfidence == "Privately owned")
        #expect(owned(.county(agency: "Maricopa County Department of Transportation"), .spatial)
                .displayNameWithConfidence == "Maricopa County Department of Transportation")
    }

    @Test("The drive card and the CSV both carry the marker")
    func reachesTheExportSurfaces() {
        var record = RoadRecord(query: RoadQuery(latitude: 33.6, longitude: -112.3))
        record.segmentName = Attributed("Test Rd",
                                        provenance: Provenance(sourceID: "t", sourceName: "Test",
                                            url: URL(string: "https://example.test")!,
                                            fetchedAt: Date(timeIntervalSince1970: 1_757_000_000)))
        record.owner = owned(.notPubliclyMaintained, .derived)
        // DriveCardContent feeds the drive card, the Live Activity and the CSV export.
        #expect(DriveCardContent(record: record).owner == "Not publicly maintained (inferred)")
    }
}
