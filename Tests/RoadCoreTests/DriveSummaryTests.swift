import Foundation
import Testing
@testable import RoadCore
@testable import RoadUI

private let provenance = Provenance(sourceID: "t", sourceName: "Test",
                                    url: URL(string: "https://example.org")!,
                                    fetchedAt: Date(timeIntervalSince1970: 1_757_000_000))

private func record(_ build: (inout RoadRecord) -> Void) -> RoadRecord {
    var record = RoadRecord(query: RoadQuery(latitude: 33.689441, longitude: -112.317668))
    build(&record)
    return record
}

@MainActor
private func card(_ record: RoadRecord?, resolving: Bool = false) -> DriveSummary {
    DriveSummary(record: record, isResolving: resolving, logCount: 0)
}

// The card is a SwiftUI view, so building one has to happen on the main actor.
@MainActor
@Suite("What the card says at the wheel")
struct DriveSummaryTests {
    @Test("Construction and resurfacing are both shown, never fused")
    func bothYears() {
        // Laying a road is not repaving it. Showing one silently hides half its history, and
        // Pennsylvania publishes the pair on the same row — VINE ST built 1959, resurfaced 2017.
        let vineStreet = record {
            $0.segmentName = Attributed("VINE ST", provenance: provenance)
            $0.yearLastConstruction = Attributed(CalendarDate.januaryFirst(ofYear: 1959)!,
                                                 provenance: provenance)
            $0.yearLastImprovement = Attributed(CalendarDate.januaryFirst(ofYear: 2017)!,
                                                provenance: provenance)
        }
        #expect(card(vineStreet).years == ["Built 1959", "Resurfaced 2017"])
    }

    @Test("A bridge dates the road when nothing else can")
    func bridgeYearIsAFallback() {
        // Houston: no local profile, so the only dated fact available is the structure you
        // are driving over. That is exactly why the bar accepts a date from any source.
        let overTheBayou = record {
            $0.segmentName = Attributed("Bagby St", provenance: provenance)
            $0.bridge = Attributed(BridgeReference(carries: "Bagby St", crosses: "BUFFALO BAYOU",
                                                   yearBuilt: 1959, yearReconstructed: 1990),
                                   provenance: provenance)
        }
        #expect(card(overTheBayou).years == ["Bridge built 1959", "Rebuilt 1990"])
    }

    @Test("A never-rebuilt bridge does not claim it was rebuilt in year zero")
    func reconstructionSentinel() {
        // NBI writes 0, not null, for "never rebuilt".
        let neverRebuilt = record {
            $0.bridge = Attributed(BridgeReference(yearBuilt: 1927, yearReconstructed: 0),
                                   provenance: provenance)
        }
        #expect(card(neverRebuilt).years == ["Bridge built 1927"])
    }

    @Test("The word frontage never reaches the card")
    func neverSaysFrontage() {
        // Reported from the road: "Frontage built 2010" reads as a statement about the *kind*
        // of road you are on. It is the year the buildings alongside it went up.
        let alongside = record {
            $0.segmentName = Attributed("Williams Dr", provenance: provenance)
            $0.parcel = Attributed(ParcelReference(apn: "503-88-286",
                                                   constructionYearRange: 2008...2009,
                                                   containsPin: false),
                                   provenance: provenance)
        }
        let years = card(alongside).years
        #expect(years == ["Buildings built 2008\u{2013}2009"])
        for line in years + card(alongside).details {
            #expect(!line.lowercased().contains("frontage"))
        }
    }

    @Test("Detail reads in the order a driver cares about")
    func detailOrder() {
        let williams = record {
            $0.classification = Attributed("Principal Arterial", provenance: provenance)
            $0.surface = Attributed(SurfaceDescription(type: "Asphaltic Concrete", laneCount: 4,
                                                       conditionRating: "Very Good"),
                                    provenance: provenance)
            $0.trafficCount = Attributed(10_286, provenance: provenance)
        }
        #expect(card(williams).details
                == ["Principal Arterial", "4 lanes", "condition very good", "10,286 vehicles a day"])
    }

    @Test("The tier badge names the place, not the jargon")
    func tierBadge() {
        // "Harris County" means something to a driver; "national" does not.
        let covered = record {
            $0.coverage = Coverage(level: .state,
                                   jurisdiction: Jurisdiction(stateFIPS: "42", countyFIPS: "42101",
                                                              countyName: "Philadelphia County",
                                                              placeName: "Philadelphia city"))
        }
        #expect(card(covered).coverageTier == "Philadelphia city")

        let thin = record {
            $0.coverage = Coverage(level: .national,
                                   jurisdiction: Jurisdiction(stateFIPS: "48", countyFIPS: "48201",
                                                              countyName: "Harris County"))
        }
        #expect(card(thin).coverageTier == "Name only")
    }

    @Test("A missing year is explained, never left as a hole")
    func dateNoteFillsTheGap() {
        // A Phoenix city street: named and owned, but no agency publishes a build year for it.
        // The row used to vanish, which reads as a broken app rather than as the edge of what
        // is published.
        let phoenixStreet = record {
            $0.segmentName = Attributed("N 7th St", provenance: provenance)
            $0.owner = Attributed(.municipality(name: "Phoenix", fullName: "City of Phoenix"),
                                  provenance: provenance)
            $0.coverage = Coverage(level: .county,
                                   jurisdiction: Jurisdiction(stateFIPS: "04", countyFIPS: "04013",
                                                              countyName: "Maricopa County",
                                                              placeName: "Phoenix city"))
        }
        #expect(card(phoenixStreet).years.isEmpty)
        #expect(card(phoenixStreet).dateNote == "No construction date published")
    }

    @Test("A state that says why gets to say it in its own words")
    func dateNoteUsesTheProfileCaveat() {
        let pennsylvania = record {
            $0.segmentName = Attributed("SIXTEENTH ST", provenance: provenance)
            $0.coverage = Coverage(
                level: .state,
                jurisdiction: Jurisdiction(stateFIPS: "42", countyFIPS: "42101",
                                           countyName: "Philadelphia County"),
                dateCaveats: ["PennDOT publishes a construction year only for roads it maintains itself."])
        }
        let note = try? #require(card(pennsylvania).dateNote)
        #expect(note?.contains("PennDOT") == true)
        // One line at 22pt on a phone: the paragraph version stays on the result screen.
        #expect((note?.count ?? 0) <= 56)
    }

    @Test("An unmapped county says so rather than blaming the road")
    func dateNoteAtTheNationalTier() {
        let houston = record {
            $0.segmentName = Attributed("Bagby St", provenance: provenance)
            $0.coverage = Coverage(level: .national,
                                   jurisdiction: Jurisdiction(stateFIPS: "48", countyFIPS: "48201",
                                                              countyName: "Harris County"))
        }
        #expect(card(houston).dateNote == "No local road source mapped here")
    }

    @Test("A road with a year shows the year, not a note about not having one")
    func noNoteWhenDated() {
        let dated = record {
            $0.segmentName = Attributed("Williams Dr", provenance: provenance)
            $0.yearLastConstruction = Attributed(CalendarDate.januaryFirst(ofYear: 2009)!,
                                                 provenance: provenance)
            $0.coverage = Coverage(level: .county, jurisdiction: nil)
        }
        #expect(card(dated).years == ["Built 2009"])
        #expect(card(dated).dateNote == nil)
    }

    @Test("Looking… only while something is running")
    func headlineStates() {
        // An indefinite "Looking…" is indistinguishable from a hang, which is how this failed
        // on the road once already.
        #expect(card(nil).headline == "Waiting for a fix\u{2026}")
        #expect(card(nil, resolving: true).headline == "Looking\u{2026}")
        #expect(card(record { _ in }).headline == "No road identified here")
        #expect(card(record { $0.segmentName = Attributed("Williams Dr", provenance: provenance) })
                .headline == "Williams Dr")
    }
}

@Suite("A source may not name a road it is merely near")
struct RoadProximityTests {
    @Test("A road a block away is not the road here")
    func rejectsTheNeighbouringStreet() {
        // The reported failure: a pin on E Athena Ave in Gilbert was named E Germann Rd. The
        // county's countywide centreline does not contain Athena Ave at all, so it answered
        // with the nearest road it *did* hold — the arterial 76 m away — and being earlier in
        // the pipeline it won. Census TIGER has Athena Ave 5.9 m from the same pin.
        #expect(!RoadProximity.isOnRoad(76))
        #expect(RoadProximity.isOnRoad(5.9))
    }

    @Test("Ordinary aiming and GPS error still resolve")
    func acceptsRealisticError() {
        // A hand-placed crosshair lands within a few metres; a GPS fix on a wide arterial can
        // be a few tens. The gate has to clear both without clearing the next street over.
        for metres in [0.0, 5, 15, 30, 59] { #expect(RoadProximity.isOnRoad(metres)) }
        for metres in [61.0, 104, 200] { #expect(!RoadProximity.isOnRoad(metres)) }
    }

    @Test("A feature with no geometry cannot claim to be nearby")
    func missingDistanceIsNotOnRoad() {
        // `distance(from:)` returns nil when a layer was queried without geometry. Treating
        // that as "close" would reinstate the bug wherever geometry is absent.
        #expect(!RoadProximity.isOnRoad(nil))
        #expect(!RoadProximity.isOnRoad(.nan))
        #expect(!RoadProximity.isOnRoad(.infinity))
    }

    @Test("Drive mode and the naming sources agree on what counts as on the road")
    func oneSharedThreshold() {
        #expect(DriveTrigger.onRoadMeters == RoadProximity.onRoadMeters)
    }
}
