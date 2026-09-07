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
    return record
}

@Suite("Public records request — the fallback that answers what no API will")
struct RecordsRequestTests {
    @Test("Routes each owner to the right agency, and admits when it cannot")
    func routing() {
        let directory = AgencyDirectory.bundled
        #expect(directory.agency(for: .county(agency: "x"))?.id == "mcdot")
        // A courtesy-maintained road is still MCDOT's to ask.
        #expect(directory.agency(for: .countyCourtesy(agency: "x"))?.id == "mcdot")
        // A state road routes on the agency's own name, not on the assumption that every
        // state road is Arizona's. Before the app went national this returned ADOT for any
        // state owner at all, which would hand a Pennsylvania driver Arizona's records office.
        #expect(directory.agency(for: .state(agency: "Arizona Department of Transportation"))?.id == "adot")
        #expect(directory.agency(for: .state(agency: "Pennsylvania Department of Transportation")) == nil)
        #expect(directory.agency(for: .municipality(name: "GOODYEAR", fullName: "City of Goodyear"))?.id == "goodyear")
        // No bundled entry beats a wrong address.
        #expect(directory.agency(for: .municipality(name: "TOLLESON", fullName: "City of Tolleson")) == nil)
        #expect(directory.agency(for: .undetermined) == nil)
        #expect(directory.agency(for: .privateOwner) == nil)
        // A name too short to be meaningful must not match by accident: "X" is inside
        // "CITY OF PHOENIX".
        #expect(directory.agency(for: .state(agency: "x")) == nil)
    }

    @Test("The bundled directory loads and is dated")
    func directoryLoads() {
        #expect(!AgencyDirectory.bundled.agencies.isEmpty)
        #expect(AgencyDirectory.bundled.capturedOn > Date(timeIntervalSince1970: 1_700_000_000))
    }

    @Test("Quotes every identifier that would help a records officer find the file")
    func citesIdentifiers() {
        let draft = RecordsRequest.draft(for: populatedRecord,
                                         agency: AgencyDirectory.bundled.agency(for: .county(agency: "x")))
        for expected in ["Williams Dr", "El Mirage Rd to Deer Valley Rd", "TT0248",
                         "CROSSRIVER UNIT 8", "706-34", "Northwest", "Board of Supervisors district", "33.689441", "RF 5819"] {
            #expect(draft.contains(expected), "draft should cite \(expected)")
        }
        #expect(draft.contains(RecordsRequest.statute))
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
        #expect(draft.contains(RecordsRequest.statute))
        // No agency, so it must not name one.
        #expect(draft.contains("the agency responsible for this road"))
    }
}
