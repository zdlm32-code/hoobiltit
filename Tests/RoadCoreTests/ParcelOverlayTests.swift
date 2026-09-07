import Foundation
import Testing
@testable import RoadCore
@testable import RoadSources
@testable import RoadUI

@Suite("Parcel overlay — the zoom gate")
struct ParcelZoomGateTests {
    @Test("Draws when the viewport is a block, not when it is a city")
    func gate() {
        #expect(Geo.parcelsWorthDrawing(at: MapSpan(latitudeDelta: 0.003, longitudeDelta: 0.003)))
        #expect(!Geo.parcelsWorthDrawing(at: MapSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)))
    }

    @Test("The gate exists because the server truncates silently")
    func gateIsBelowTheServerCap() {
        // Measured: a 1 km radius already returns the layer's 1,000-feature cap with no
        // indication it withheld anything. The threshold is well inside that.
        #expect(Geo.parcelOverlayMaxSpanDegrees < 0.01)
        #expect(!Geo.parcelsWorthDrawing(at: MapSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)))
    }

    @Test("Simplification tracks the viewport and never reaches zero")
    func simplification() {
        let tight = Geo.simplificationTolerance(for: MapSpan(latitudeDelta: 0.001, longitudeDelta: 0.001))
        let loose = Geo.simplificationTolerance(for: MapSpan(latitudeDelta: 0.006, longitudeDelta: 0.006))
        #expect(loose > tight)
        #expect(tight > 0)
    }
}

@Suite("Parcel overlay — not fetching")
struct ParcelCacheTests {
    private let block = Envelope(xmin: -112.32, ymin: 33.688, xmax: -112.315, ymax: 33.691)

    @Test("A viewport inside what was fetched needs no new request")
    func containment() {
        let nudged = Envelope(xmin: -112.319, ymin: 33.6885, xmax: -112.316, ymax: 33.6905)
        #expect(block.contains(nudged))
        #expect(block.contains(block))
    }

    @Test("A viewport that has moved off the fetched area does need one")
    func escapes() {
        let movedAway = Envelope(xmin: -112.310, ymin: 33.688, xmax: -112.305, ymax: 33.691)
        #expect(!block.contains(movedAway))
    }

    @Test("Fetching wider than the screen buys room for small pans")
    func expansion() {
        let padded = block.expanded(by: 0.25)
        #expect(padded.contains(block))
        #expect(padded.xmin < block.xmin)
        #expect(padded.ymax > block.ymax)
    }
}

@Suite("Parcel outlines")
struct ParcelOutlineTests {
    @Test("Decodes rings and discards degenerate ones")
    func decoding() throws {
        let json = """
        {"features":[
          {"attributes":{"APN_DASH":"503-88-286"},
           "geometry":{"rings":[[[-112.3180,33.6890],[-112.3175,33.6890],
                                 [-112.3175,33.6895],[-112.3180,33.6895],[-112.3180,33.6890]]]}},
          {"attributes":{"APN_DASH":"503-88-287"},"geometry":{"rings":[[[-112.31,33.68]]]}},
          {"attributes":{"APN_DASH":"503-88-288"}}
        ]}
        """
        let set = try JSONDecoder().decode(ArcGISFeatureSet.self, from: Data(json.utf8))
        let outlines = set.features.compactMap(ParcelBoundaryService.outline(from:))

        // A two-vertex "ring" and a feature with no geometry cannot be drawn.
        #expect(outlines.count == 1)
        #expect(outlines[0].apn == "503-88-286")
        #expect(outlines[0].rings[0].count == 5)
    }

    @Test("Places a label inside the parcel")
    func labelAnchor() throws {
        let ring = [Coordinate(latitude: 33.6890, longitude: -112.3180),
                    Coordinate(latitude: 33.6890, longitude: -112.3175),
                    Coordinate(latitude: 33.6895, longitude: -112.3175),
                    Coordinate(latitude: 33.6895, longitude: -112.3180)]
        let anchor = try #require(ParcelOutline(apn: "x", rings: [ring]).labelAnchor)

        #expect(abs(anchor.latitude - 0.5 * (33.6890 + 33.6895)) < 1e-9)
        #expect(abs(anchor.longitude - 0.5 * (-112.3180 + -112.3175)) < 1e-9)
    }

    @Test("An empty ring yields no anchor rather than a bogus coordinate")
    func emptyRing() {
        #expect(ParcelOutline(apn: "x", rings: []).labelAnchor == nil)
        #expect(Geo.centroid(of: []) == nil)
    }
}

@Suite("Drive mode — deciding when to re-resolve")
struct RoadNameProbeTests {
    @Test("Picks the nearest named centreline, not the first returned")
    func nearest() throws {
        // Two streets in range; the pin is on the second.
        let json = """
        {"features":[
          {"attributes":{"FullStreetName":"W Candelaria Ct"},
           "geometry":{"paths":[[[-112.3200,33.6900],[-112.3190,33.6900]]]}},
          {"attributes":{"FullStreetName":"W Williams Dr"},
           "geometry":{"paths":[[[-112.3180,33.6894],[-112.3170,33.6894]]]}}
        ]}
        """
        let set = try JSONDecoder().decode(ArcGISFeatureSet.self, from: Data(json.utf8))
        let hit = try #require(RoadNameProbe.nearest(in: set,
                                                     to: Coordinate(latitude: 33.68944,
                                                                    longitude: -112.317668),
                                                     service: .maricopa))
        #expect(hit.name == "W Williams Dr")
        #expect(hit.metresAway < 60)
    }

    @Test("Ignores features with no name or no geometry")
    func skipsUnusable() throws {
        let json = """
        {"features":[
          {"attributes":{"FullStreetName":null},
           "geometry":{"paths":[[[-112.3180,33.6894],[-112.3170,33.6894]]]}},
          {"attributes":{"FullStreetName":"W Williams Dr"}}
        ]}
        """
        let set = try JSONDecoder().decode(ArcGISFeatureSet.self, from: Data(json.utf8))
        #expect(RoadNameProbe.nearest(in: set, to: Coordinate(latitude: 33.689, longitude: -112.317),
                                      service: .maricopa) == nil)
    }

    @Test("A renamed road is a change; the same road spelled differently is not")
    func changeDetection() {
        // The trigger compares normalized names, so casing and punctuation drift between
        // the probe layers cannot cause a needless six-source lookup.
        #expect(RoadName.comparisonKey("W Williams Dr") == RoadName.comparisonKey("w williams dr"))
        #expect(RoadName.comparisonKey("W Williams Dr") != RoadName.comparisonKey("W Candelaria Ct"))
    }
}

@Suite("Tapping a parcel")
struct ParcelHitTestTests {
    /// A rectangle around Williams Dr, wound counter-clockwise like a real Assessor ring.
    private let square = [
        Coordinate(latitude: 33.6890, longitude: -112.3180),
        Coordinate(latitude: 33.6890, longitude: -112.3170),
        Coordinate(latitude: 33.6900, longitude: -112.3170),
        Coordinate(latitude: 33.6900, longitude: -112.3180),
    ]

    @Test("Finds the parcel under the tap")
    func inside() {
        let outline = ParcelOutline(apn: "503-88-286", rings: [square])
        #expect(outline.contains(Coordinate(latitude: 33.6895, longitude: -112.3175)))
    }

    @Test("A tap outside every parcel selects nothing")
    func outside() {
        let outline = ParcelOutline(apn: "503-88-286", rings: [square])
        #expect(!outline.contains(Coordinate(latitude: 33.6910, longitude: -112.3175)))
        #expect(!outline.contains(Coordinate(latitude: 33.6895, longitude: -112.3200)))
    }

    @Test("A degenerate ring cannot be tapped")
    func degenerate() {
        #expect(!ParcelOutline(apn: "x", rings: []).contains(square[0]))
        #expect(!Geo.ring([square[0], square[1]], contains: square[0]))
    }

    @Test("Picks the containing parcel out of several drawn")
    func selectsAmongNeighbours() {
        let west = ParcelOutline(apn: "west", rings: [square])
        let east = ParcelOutline(apn: "east", rings: [[
            Coordinate(latitude: 33.6890, longitude: -112.3170),
            Coordinate(latitude: 33.6890, longitude: -112.3160),
            Coordinate(latitude: 33.6900, longitude: -112.3160),
            Coordinate(latitude: 33.6900, longitude: -112.3170),
        ]])
        let tap = Coordinate(latitude: 33.6895, longitude: -112.3165)
        #expect([west, east].first { $0.contains(tap) }?.apn == "east")
    }
}

@Suite("Driving detection")
struct MotionTests {
    @Test("Thresholds have hysteresis, so a stop light does not flip modes")
    func hysteresis() {
        // Entry is well above exit; without a gap, creeping in traffic would toggle the whole
        // mode on every fix.
        #expect(LocationProvider.drivingEntrySpeed > LocationProvider.drivingExitSpeed)
        // ~11 mph in, ~2 mph out.
        #expect(LocationProvider.drivingEntrySpeed >= 4.0)
        #expect(LocationProvider.drivingExitSpeed <= 1.5)
    }

    @Test("Stationary needs sustained stillness, not one slow fix")
    func stillnessIsSustained() {
        #expect(LocationProvider.stillnessBeforeStationary >= 30)
    }
}

@Suite("Naming a street inside a city")
struct StreetNameSourceTests {
    private let goodyear = RoadQuery(latitude: 33.4340, longitude: -112.4009)

    private func source(_ transport: FixtureTransport) -> MaricopaStreetNameSource {
        MaricopaStreetNameSource(probe: RoadNameProbe(service: .maricopa,
                                                     client: ArcGISClient(transport: transport)),
                                 now: { Date(timeIntervalSince1970: 1_757_000_000) })
    }

    @Test("Names a road that MCDOT's maintained layer does not cover")
    func namesCityStreet() async throws {
        // Inside a city the maintained-roads layer is empty, which left drive mode reporting
        // "No road identified here" on a perfectly ordinary named street.
        let fragment = try await source(.goodyearStreet).fetch(goodyear)
        #expect(fragment.segmentName?.value == "S 159th Dr")
        #expect(fragment.classification?.value == "Residential")
        // Nearest centreline, not an authoritative record for this point.
        #expect(fragment.segmentName?.confidence == .spatial)
    }

    @Test("Defers to a source that already named the road")
    func defersToBetterSources() async throws {
        var resolved = RoadRecord(query: goodyear)
        resolved.segmentName = Attributed(
            "Williams Dr",
            provenance: Provenance(sourceID: "mcdot.rit", sourceName: "MCDOT Road Information Tool",
                                   url: URL(string: "https://example.test")!,
                                   fetchedAt: Date(timeIntervalSince1970: 0)))

        let fragment = try await source(.goodyearStreet).fetch(goodyear, resolved: resolved)
        #expect(fragment.segmentName == nil)
        #expect(fragment.notes.first?.outcome == .skipped)
    }

    @Test("Claims only the name and class, never ownership")
    func staysInItsLane() async throws {
        // This layer is a centreline. It knows nothing about who maintains the road, and
        // ownership in a city has to keep coming from the municipality polygon.
        let fragment = try await source(.goodyearStreet).fetch(goodyear)
        #expect(fragment.owner == nil)
        #expect(fragment.jurisdiction == nil)
    }
}

@Suite("The lots facing the pin")
struct FrontingLotsTests {
    /// Two lots either side of a street running east-west, plus one a block away.
    private func lot(_ apn: String, southEdge: Double, northEdge: Double) -> ParcelOutline {
        ParcelOutline(apn: apn, rings: [[
            Coordinate(latitude: southEdge, longitude: -111.7262),
            Coordinate(latitude: southEdge, longitude: -111.7258),
            Coordinate(latitude: northEdge, longitude: -111.7258),
            Coordinate(latitude: northEdge, longitude: -111.7262),
            Coordinate(latitude: southEdge, longitude: -111.7262),
        ]])
    }

    /// On the street, between the two lots.
    private let pin = Coordinate(latitude: 33.27700, longitude: -111.7260)

    @Test("Both lots either side of the street are included")
    func bothSides() {
        // The reported complaint: only one lot was highlighted while two plainly face the
        // crosshair.
        let north = lot("north", southEdge: 33.27710, northEdge: 33.27760)
        let south = lot("south", southEdge: 33.27640, northEdge: 33.27690)
        let found = ParcelOutline.fronting([north, south], at: pin).map(\.apn)
        #expect(Set(found) == ["north", "south"])
    }

    @Test("A lot a block away is not facing the pin")
    func excludesTheNextBlock() {
        let near = lot("near", southEdge: 33.27710, northEdge: 33.27760)
        let far = lot("far", southEdge: 33.28000, northEdge: 33.28050)   // ~330 m north
        #expect(ParcelOutline.fronting([near, far], at: pin).map(\.apn) == ["near"])
    }

    @Test("Nearest first, and never more than a corner's worth")
    func orderedAndCapped() {
        let lots = (0..<8).map { i in
            lot("lot\(i)", southEdge: 33.27705 + Double(i) * 0.00004,
                northEdge: 33.27706 + Double(i) * 0.00004)
        }
        let found = ParcelOutline.fronting(lots, at: pin)
        #expect(found.count == ParcelOutline.frontingLimit)
        #expect(found.map(\.apn) == ["lot0", "lot1", "lot2", "lot3"], "nearest first")
    }

    @Test("A pin inside a lot is zero distance from it")
    func containmentIsZero() {
        let around = lot("around", southEdge: 33.27650, northEdge: 33.27750)
        #expect(around.distance(from: pin) == 0)
        #expect(ParcelOutline.fronting([around], at: pin).map(\.apn) == ["around"])
    }
}
