import Foundation
import Testing
@testable import RoadCore

private let provenance = Provenance(sourceID: "t", sourceName: "Test",
                                    url: URL(string: "https://example.org")!, fetchedAt: Date())

private func road(_ name: String?, owner: RoadOwner? = nil, built: Int? = nil,
                  project: String? = nil) -> RoadRecord {
    var record = RoadRecord(query: RoadQuery(latitude: 33.68, longitude: -112.31))
    if let name { record.segmentName = Attributed(name, provenance: provenance) }
    if let owner { record.owner = Attributed(owner, provenance: provenance) }
    if let built { record.yearLastConstruction = Attributed(CalendarDate.januaryFirst(ofYear: built)!,
                                                           provenance: provenance) }
    if let project {
        record.project = Attributed(ProjectReference(projectNumber: project, title: project),
                                    provenance: provenance)
    }
    return record
}

@Suite("The drive log counts roads, not lookups")
struct DriveLogTests {
    @Test("Driving one long road records it once")
    func collapsesConsecutiveLookups() {
        // Drive mode re-resolves about every 250 m whether or not the road changed, so a
        // five-mile arterial produces roughly thirty-two identical results. Logged unfiltered,
        // the card's "N roads" counter becomes meaningless.
        var log: [RoadRecord] = []
        for _ in 0..<32 { log = DriveLog.appending(road("Williams Dr"), to: log) }
        #expect(log.count == 1)
    }

    @Test("Turning onto another street adds an entry")
    func newRoadIsANewEntry() {
        var log: [RoadRecord] = []
        log = DriveLog.appending(road("Williams Dr"), to: log)
        log = DriveLog.appending(road("Bullard Ave"), to: log)
        log = DriveLog.appending(road("Williams Dr"), to: log)
        // Newest first, and coming back to a road later is genuinely a new leg of the drive.
        #expect(log.compactMap { $0.segmentName?.value }
                == ["Williams Dr", "Bullard Ave", "Williams Dr"])
    }

    @Test("Case and punctuation do not split one road in two")
    func matchesOnComparisonKey() {
        // `RoadName.comparisonKey` normalises case and drops separators, which is what one
        // source returning "W Williams Dr" and then "W. WILLIAMS DR." needs.
        var log = DriveLog.appending(road("W Williams Dr"), to: [])
        log = DriveLog.appending(road("W. WILLIAMS DR."), to: log)
        #expect(log.count == 1)
    }

    @Test("Two genuinely different roads are never merged")
    func doesNotOverMatch() {
        // The key is deliberately not fuzzy: it does not expand abbreviations, because
        // "Santa Fe Dr" and "Santa Fe Ct" are different roads and this app's value rests on
        // never confidently naming the wrong one.
        var log = DriveLog.appending(road("Santa Fe Dr"), to: [])
        log = DriveLog.appending(road("Santa Fe Ct"), to: log)
        #expect(log.count == 2)
    }

    @Test("Merging keeps whichever lookup knew more")
    func keepsTheRicherRecord() {
        // Sources fail independently and a dead endpoint is retried on the next pass, so a
        // later refresh can know more than the first — or less. Neither position wins by
        // default; the fuller record does.
        var log = DriveLog.appending(road("Williams Dr", owner: .county(agency: "MCDOT")), to: [])
        log = DriveLog.appending(
            road("Williams Dr", owner: .county(agency: "MCDOT"), built: 2009, project: "TT0248"),
            to: log)
        #expect(log.count == 1)
        #expect(log[0].yearLastConstruction != nil)
        #expect(log[0].project?.value.projectNumber == "TT0248")

        // And a thinner refresh must not erase what was already known.
        log = DriveLog.appending(road("Williams Dr"), to: log)
        #expect(log.count == 1)
        #expect(log[0].project?.value.projectNumber == "TT0248")
    }

    @Test("A lookup that named no road is not logged")
    func unnamedIsNotLogged() {
        #expect(DriveLog.appending(road(nil), to: []).isEmpty)
        // …and it does not disturb what is already there.
        let existing = DriveLog.appending(road("Williams Dr"), to: [])
        #expect(DriveLog.appending(road(nil), to: existing).count == 1)
    }

    @Test("A route designation identifies a road with no street name")
    func routeDesignationCounts() {
        var record = RoadRecord(query: RoadQuery(latitude: 33.46, longitude: -112.37))
        record.routeDesignation = Attributed("I-10", provenance: provenance)
        #expect(DriveLog.appending(record, to: []).count == 1)
    }
}
