import Foundation
import Testing
@testable import RoadCore

private let provenance = Provenance(sourceID: "t", sourceName: "Test",
                                    url: URL(string: "https://example.org")!, fetchedAt: Date())

private func record(_ build: (inout RoadRecord) -> Void) -> RoadRecord {
    var record = RoadRecord(query: RoadQuery(latitude: 33.68, longitude: -112.31))
    build(&record)
    return record
}

private let williams = record {
    $0.segmentName = Attributed("Williams Dr", provenance: provenance)
    $0.owner = Attributed(.county(agency: "Maricopa County DOT"), provenance: provenance)
    $0.yearLastConstruction = Attributed(CalendarDate.januaryFirst(ofYear: 2009)!,
                                         provenance: provenance)
    $0.classification = Attributed("Principal Arterial", provenance: provenance)
    $0.trafficCount = Attributed(10_286, provenance: provenance)
}

@Suite("The content the card and the lock screen share")
struct DriveCardContentTests {
    @Test("A slot one lookup could not fill does not blink out")
    func stickyCarriesForward() {
        // Sources fail independently, so between two refreshes on one road the assessor may
        // answer and the traffic count may not. A row that vanishes and returns is the same
        // flicker complaint at field level.
        let full = DriveCardContent(record: williams)
        let partial = DriveCardContent(record: record {
            $0.segmentName = Attributed("Williams Dr", provenance: provenance)
        })
        let merged = partial.sticking(to: full)
        #expect(merged.owner == "Maricopa County DOT")
        #expect(merged.years == ["Built 2009"])
        #expect(merged.details == full.details)
    }

    @Test("A different road resets every slot")
    func stickyDoesNotBleedAcrossRoads() {
        // The half that matters more: carrying forward onto a *new* road would attribute one
        // road's owner, year and traffic to another.
        let full = DriveCardContent(record: williams)
        let nextStreet = DriveCardContent(record: record {
            $0.segmentName = Attributed("Bullard Ave", provenance: provenance)
        })
        let merged = nextStreet.sticking(to: full)
        #expect(merged.roadName == "Bullard Ave")
        #expect(merged.owner == nil)
        #expect(merged.years.isEmpty)
        #expect(merged.details.isEmpty)
    }

    @Test("Fresher facts win over carried-forward ones")
    func stickyPrefersTheNewReading() {
        let stale = DriveCardContent(record: williams)
        let corrected = DriveCardContent(record: record {
            $0.segmentName = Attributed("Williams Dr", provenance: provenance)
            $0.owner = Attributed(.municipality(name: "Goodyear", fullName: "City of Goodyear"),
                                  provenance: provenance)
        })
        #expect(corrected.sticking(to: stale).owner == "City of Goodyear")
    }
}

@Suite("What reaches the lock screen")
struct DriveActivityStateTests {
    @Test("The payload carries finished strings, with the years still separate")
    func payload() {
        let dated = record {
            $0.segmentName = Attributed("VINE ST", provenance: provenance)
            $0.yearLastConstruction = Attributed(CalendarDate.januaryFirst(ofYear: 1959)!,
                                                 provenance: provenance)
            $0.yearLastImprovement = Attributed(CalendarDate.januaryFirst(ofYear: 2017)!,
                                                provenance: provenance)
        }
        let state = DriveActivityState(card: DriveCardContent(record: dated))
        #expect(state.road == "VINE ST")
        // Construction and resurfacing stay distinguishable here too, not fused into one date.
        #expect(state.years?.contains("Built 1959") == true)
        #expect(state.years?.contains("Resurfaced 2017") == true)
        // The Dynamic Island's compact slot fits about four characters.
        #expect(state.compactYear == "1959")
    }

    @Test("An unchanged road produces an identical payload, so no update is sent")
    func identicalPayloadsCompareEqual() {
        // This is what makes the 250 m re-resolve cadence free for the lock screen: the
        // controller skips any update whose rendered text has not changed.
        let a = DriveActivityState(card: DriveCardContent(record: williams))
        let b = DriveActivityState(card: DriveCardContent(record: williams))
        #expect(a == b)
    }

    @Test("A road with no year shows why, not a blank")
    func carriesTheDateNote() {
        let phoenix = record {
            $0.segmentName = Attributed("N 7th St", provenance: provenance)
            $0.coverage = Coverage(level: .county,
                                   jurisdiction: Jurisdiction(stateFIPS: "04", countyFIPS: "04013",
                                                              countyName: "Maricopa County"))
        }
        let state = DriveActivityState(card: DriveCardContent(record: phoenix))
        #expect(state.years == "No construction date published")
    }

    @Test("A word where a year should be is not squeezed into the island")
    func compactYearIsOnlyEverDigits() {
        let plattedOnly = record {
            $0.segmentName = Attributed("Some Ln", provenance: provenance)
            $0.declaration = Attributed(RoadDeclaration(roadName: "Some Ln",
                                                        effectiveDate: Date(timeIntervalSince1970: 0)),
                                        provenance: provenance)
        }
        let state = DriveActivityState(card: DriveCardContent(record: plattedOnly))
        #expect(state.years?.hasPrefix("Public road since") == true)
        #expect(state.compactYear == "1970", "the trailing token is a year, so it is usable")
    }
}

@Suite("The years line earns its space")
struct DriveYearsTests {
    private let provenance = Provenance(sourceID: "t", sourceName: "Test",
                                        url: URL(string: "https://example.org")!, fetchedAt: Date())

    private func road(built: Int?, improved: Int?) -> RoadRecord {
        var record = RoadRecord(query: RoadQuery(latitude: 33.32, longitude: -111.89))
        record.segmentName = Attributed("SR-101", provenance: provenance)
        if let built {
            record.yearLastConstruction = Attributed(CalendarDate.januaryFirst(ofYear: built)!,
                                                     provenance: provenance)
        }
        if let improved {
            record.yearLastImprovement = Attributed(CalendarDate.januaryFirst(ofYear: improved)!,
                                                    provenance: provenance)
        }
        return record
    }

    @Test("One year, said once")
    func collapsesTheDuplicate() {
        // Loop 101 came back "Built 2004 · Resurfaced 2004" — a road built and surfaced in one
        // season. Two facts' worth of the card spent on one.
        #expect(DriveCardContent(record: road(built: 2004, improved: 2004)).years == ["Built 2004"])
    }

    @Test("A genuine resurfacing is still worth the room")
    func keepsRealImprovements() {
        #expect(DriveCardContent(record: road(built: 1959, improved: 2017)).years
                == ["Built 1959", "Resurfaced 2017"])
    }

    @Test("A resurfacing with no known build year stands alone")
    func improvementOnly() {
        #expect(DriveCardContent(record: road(built: nil, improved: 2017)).years
                == ["Resurfaced 2017"])
    }
}
