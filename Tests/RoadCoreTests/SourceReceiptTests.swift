import Foundation
import Testing
@testable import RoadCore

private func provenance(_ id: String, _ name: String, at seconds: TimeInterval = 0,
                        bundled: Bool = false, path: String = "/q") -> Provenance {
    Provenance(sourceID: id, sourceName: name,
               url: URL(string: "https://example.org\(path)")!,
               fetchedAt: Date(timeIntervalSince1970: 1_757_000_000 + seconds),
               isBundled: bundled)
}

private func note(_ id: String, _ name: String, _ outcome: SourceNote.Outcome,
                  _ detail: String? = nil) -> SourceNote {
    SourceNote(sourceID: id, sourceName: name, outcome: outcome, detail: detail)
}

@Suite("Receipts — what each source actually gave")
struct SourceReceiptTests {
    private func maricopaRecord() -> RoadRecord {
        var record = RoadRecord(query: RoadQuery(latitude: 33.689441, longitude: -112.317668))
        let mcdot = provenance("mcdot.rit", "MCDOT Road Information Tool", path: "/rit/2")
        record.segmentName = Attributed("Williams Dr", provenance: mcdot, confidence: .direct)
        record.classification = Attributed("Principal Arterial", provenance: mcdot, confidence: .direct)
        record.owner = Attributed(.county(agency: "Maricopa County DOT"),
                                  provenance: mcdot, confidence: .derived)
        record.project = Attributed(ProjectReference(projectNumber: "TT0248", title: "Deer Valley Rd"),
                                    provenance: provenance("mcdot.projects", "MCDOT programmes"),
                                    confidence: .direct)
        record.notes = [
            note("adot.atis", "ADOT ATIS", .foundNothing, "No ADOT route at this location."),
            note("mcdot.rit", "MCDOT Road Information Tool", .contributed, "County-maintained."),
            note("mcdot.projects", "MCDOT programmes", .contributed, "Capital project TT0248."),
            note("mcassessor.parcels", "Maricopa County Assessor", .failed, "timed out"),
        ]
        return record
    }

    @Test("Fields are grouped by the source that supplied them")
    func groupsBySource() {
        let receipts = maricopaRecord().receipts
        let mcdot = receipts.first { $0.sourceID == "mcdot.rit" }
        #expect(mcdot?.fieldCount == 3, "name, classification and owner all came from MCDOT")
        #expect(receipts.first { $0.sourceID == "mcdot.projects" }?.fieldCount == 1)
    }

    @Test("How a source matched is carried, not flattened to one value")
    func keepsEveryConfidence() {
        // MCDOT reads the name straight off the layer and *concludes* ownership. Reporting one
        // confidence for the source would overstate the weaker of the two.
        let mcdot = maricopaRecord().receipts.first { $0.sourceID == "mcdot.rit" }
        #expect(mcdot?.confidences == [.direct, .derived])
    }

    @Test("A source that found nothing is still listed")
    func listsSilentSources() {
        // An empty MCDOT response is how the app learns a city maintains the road. Hiding the
        // sources that had nothing to say would hide that reasoning.
        let receipts = maricopaRecord().receipts
        let adot = receipts.first { $0.sourceID == "adot.atis" }
        #expect(adot != nil)
        #expect(adot?.fieldCount == 0)
        #expect(adot?.outcome == .foundNothing)
        #expect(adot?.url == nil, "it produced no query worth re-running")
    }

    @Test("A failure is reported as a failure, not as an absence")
    func surfacesFailures() {
        let parcels = maricopaRecord().receipts.first { $0.sourceID == "mcassessor.parcels" }
        #expect(parcels?.outcome == .failed)
        #expect(parcels?.detail == "timed out")
    }

    @Test("Contributors come first, in pipeline order")
    func ordersByContribution() {
        let ids = maricopaRecord().receipts.map(\.sourceID)
        #expect(ids.prefix(2) == ["mcdot.rit", "mcdot.projects"])
        #expect(Set(ids.suffix(2)) == ["adot.atis", "mcassessor.parcels"])
    }

    @Test("The receipt kept is the most recent query from that source")
    func keepsTheLatestQuery() {
        // A source queried several layers leaves several receipts; the newest is the one worth
        // re-running.
        var record = RoadRecord(query: RoadQuery(latitude: 33.68, longitude: -112.31))
        record.segmentName = Attributed("A", provenance: provenance("s", "S", at: 0, path: "/old"))
        record.classification = Attributed("B", provenance: provenance("s", "S", at: 500, path: "/new"))
        record.notes = [note("s", "S", .contributed)]
        let receipt = record.receipts.first
        #expect(receipt?.url?.path() == "/new")
        #expect(receipt?.fieldCount == 2)
    }

    @Test("A bundled snapshot is disclosed")
    func flagsBundled() {
        var record = RoadRecord(query: RoadQuery(latitude: 33.68, longitude: -112.31))
        record.owner = Attributed(.undetermined,
                                  provenance: provenance("b", "Bundled", bundled: true))
        record.notes = [note("b", "Bundled", .contributed)]
        #expect(record.receipts.first?.isBundled == true)
    }

    @Test("A record nobody answered yields nothing to show")
    func emptyRecord() {
        let record = RoadRecord(query: RoadQuery(latitude: 33.68, longitude: -112.31))
        #expect(record.receipts.isEmpty)
    }
}
