import Foundation
import Testing
@testable import RoadCore

private let provenance = Provenance(sourceID: "t", sourceName: "Test",
                                    url: URL(string: "https://example.org")!, fetchedAt: Date())

private func road(_ name: String?, owner: RoadOwner? = nil, built: Int? = nil,
                  failed: Bool = false) -> RoadRecord {
    var record = RoadRecord(query: RoadQuery(latitude: 33.68, longitude: -112.31))
    if let name { record.segmentName = Attributed(name, provenance: provenance) }
    if let owner { record.owner = Attributed(owner, provenance: provenance) }
    if let built {
        record.yearLastConstruction = Attributed(CalendarDate.januaryFirst(ofYear: built)!,
                                                 provenance: provenance)
    }
    if failed {
        record.notes = [SourceNote(sourceID: "mcdot.rit", sourceName: "MCDOT",
                                   outcome: .failed, detail: "timed out")]
    }
    return record
}

private let rich = road("Williams Dr", owner: .county(agency: "MCDOT"), built: 2009)

@Suite("A refresh never makes the card worse")
struct DriveAnswerTests {
    @Test("A blip that loses half the record is ignored")
    func thinnerAfterAFailureIsRejected() {
        // The card no longer blanks, but assigning unconditionally meant one timed-out
        // endpoint emptied the owner and year rows and shrank the card — the same complaint
        // in a different costume.
        let blip = road("Williams Dr", failed: true)
        #expect(!DriveAnswer.shouldAdopt(new: blip, over: rich, probedRoadChanged: false))
    }

    @Test("Genuinely leaving coverage is believed")
    func thinnerWithoutFailureIsAccepted() {
        // Every source answered and there is simply less to know here — crossing out of a
        // mapped county, say. Holding the old record would be the confident lie.
        let thin = road("Williams Dr", owner: .county(agency: "MCDOT"))
        #expect(DriveAnswer.shouldAdopt(new: thin, over: rich, probedRoadChanged: false))
    }

    @Test("A new road always wins, however little is known about it")
    func roadChangeAlwaysAdopts() {
        // The half that is easy to forget: a guard that only kept richer records would leave
        // the previous road's data on screen after a turn.
        let bare = road("Bullard Ave")
        #expect(DriveAnswer.shouldAdopt(new: bare, over: rich, probedRoadChanged: true))
        let alsoFailed = road("Bullard Ave", failed: true)
        #expect(DriveAnswer.shouldAdopt(new: alsoFailed, over: rich, probedRoadChanged: true))
    }

    @Test("A richer answer is always taken")
    func richerAdopts() {
        let richer = road("Williams Dr", owner: .county(agency: "MCDOT"), built: 2009)
        let poorer = road("Williams Dr", owner: .county(agency: "MCDOT"))
        #expect(DriveAnswer.shouldAdopt(new: richer, over: poorer, probedRoadChanged: false))
        // Equal counts adopt too, so a genuinely changed fact of the same shape still lands.
        #expect(DriveAnswer.shouldAdopt(new: richer, over: richer, probedRoadChanged: false))
    }

    @Test("With nothing on screen, anything is an improvement")
    func noStandingAnswer() {
        #expect(DriveAnswer.shouldAdopt(new: road("Williams Dr"), over: nil,
                                        probedRoadChanged: false))
        // A record that never named a road is not worth protecting either.
        #expect(DriveAnswer.shouldAdopt(new: road("Williams Dr", failed: true),
                                        over: road(nil), probedRoadChanged: false))
    }
}
