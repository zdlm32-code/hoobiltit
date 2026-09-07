import Foundation
import Testing
@testable import RoadCore

/// Decodes a recorded agency response straight into a feature set, so these tests run against
/// the same bytes the live services returned rather than an invented shape.
private func featureSet(_ name: String) throws -> ArcGISFeatureSet {
    let url = Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: "json")!
    return try JSONDecoder().decode(ArcGISFeatureSet.self, from: Data(contentsOf: url))
}

/// The I-10 pin the ADOT fixtures were captured at.
private let interstate10 = Coordinate(latitude: 33.4602, longitude: -112.3756)

@Suite("LRS event join")
struct LRSJoinTests {
    // MARK: Route id is a filter, never a selector

    @Test("Events on another route are excluded outright")
    func excludesOtherRoutes() throws {
        // Louisiana's Last Construction layer answers a residential envelope with a single
        // row belonging to a route none of the streets in the box are on. Reporting its year
        // would date a street from its neighbour.
        let events = try featureSet("atis_2_i10")
        let found = LRSJoin.candidates(in: events, routeID: "no-such-route", near: interstate10)
        #expect(found.isEmpty)
    }

    @Test("Route ids are compared raw, so padding is never normalised away")
    func matchesRouteIDExactly() throws {
        // ATIS pads to a fixed width. Trimming would fuse "  I 010" with "07  I 10", the
        // local mirror ADOTStateRouteSource works hard to tell apart.
        let events = try featureSet("atis_24_i10")
        let padded = LRSJoin.candidates(in: events, routeID: "  I 010                         ",
                                        near: interstate10)
        let trimmed = LRSJoin.candidates(in: events, routeID: "I 010", near: interstate10)
        #expect(padded.count == 13)
        #expect(trimmed.isEmpty)
    }

    // MARK: The bug this type exists to fix

    @Test("Picks one improvement date out of five on the same ramp, by geometry")
    func picksNearestOfSeveralEventsOnOneRoute() throws {
        // Ramp I 010127E carries five improvement events with three different years across
        // disjoint measure ranges. `.first` picked whichever the agency listed first.
        let events = try featureSet("atis_2_i10")
        let ramp = "  I 010127E                     "
        let all = LRSJoin.candidates(in: events, routeID: ramp, near: interstate10)
        #expect(all.count == 5)

        let distances = all.compactMap { $0.distance(from: interstate10) }
        #expect(distances.count == all.count, "every event carries geometry to rank on")
        #expect(distances == distances.sorted(), "nearest first")

        let best = try #require(LRSJoin.best(in: events, routeID: ramp, near: interstate10))
        let nearest = try #require(all.min { ($0.distance(from: interstate10) ?? .infinity)
                                             < ($1.distance(from: interstate10) ?? .infinity) })
        #expect(best["YearLastImprovement"].rawString == nearest["YearLastImprovement"].rawString)
    }

    @Test("Picks one project out of thirteen on I-10")
    func picksAmongManyProjects() throws {
        let events = try featureSet("atis_24_i10")
        let route = "  I 010                         "
        let best = try #require(LRSJoin.best(in: events, routeID: route, near: interstate10))
        let tracs = try #require(best["TracsNumber"].text)
        // Not an assertion about which project is correct — only that the choice is made by
        // proximity and is reproducible, where before it depended on row order.
        #expect(!tracs.isEmpty)
        let repeated = try #require(LRSJoin.best(in: events, routeID: route, near: interstate10))
        #expect(repeated["TracsNumber"].text == tracs)
    }

    // MARK: Measures

    @Test("Measure ranges survive both encodings and descending order")
    func readsMeasures() throws {
        // ADOT ships measures as strings, Louisiana as numbers.
        let events = try featureSet("atis_24_i10")
        let withMeasures = events.features.compactMap { LRSJoin.measureRange(of: $0) }
        #expect(withMeasures.count == events.features.count)

        let descending = LRSJoin.MeasureRange(from: 9, to: 4)
        #expect(descending.lower == 4)
        #expect(descending.upper == 9)
        #expect(descending.length == 5)
    }

    @Test("Abutting events do not count as overlapping")
    func abuttingRangesDoNotOverlap() {
        // Esri writes a measure that ought to be zero as -3e-8, so a bare > would fuse two
        // events that merely touch.
        let a = LRSJoin.MeasureRange(from: 0.104149, to: 0.1268726)
        let b = LRSJoin.MeasureRange(from: 0.1268726, to: 0.1348808)
        #expect(!a.overlaps(b))
        #expect(a.overlaps(LRSJoin.MeasureRange(from: 0.12, to: 0.13)))
        #expect(LRSJoin.MeasureRange(from: -3e-8, to: 0.0324).overlaps(
                LRSJoin.MeasureRange(from: 0.01, to: 0.02)))
    }

    @Test("A route span filters out events that do not cover it")
    func measureRangeFilters() throws {
        let events = try featureSet("atis_2_i10")
        let ramp = "  I 010127E                     "
        let onRoute = LRSJoin.candidates(in: events, routeID: ramp, near: interstate10)
        #expect(onRoute.count == 5)

        // The pin's span covers only the first of the five disjoint events.
        let span = LRSJoin.MeasureRange(from: 0.10, to: 0.13)
        let narrowed = LRSJoin.candidates(in: events, routeID: ramp, near: interstate10, within: span)
        #expect(narrowed.count == 1)
        #expect(LRSJoin.measureRange(of: narrowed[0])?.lower == 0.09666746)
    }

    @Test("An event with no measures is kept when a span is supplied")
    func keepsUnmeasuredEvents() throws {
        // Arizona's route layer publishes no measures at all. Dropping unmeasurable events
        // would discard answers that may well apply.
        let routes = try featureSet("atis_1_i10")
        let unmeasured = routes.features.filter { LRSJoin.measureRange(of: $0) == nil }
        #expect(!unmeasured.isEmpty)

        let id = try #require(routes.features.first?["RouteId"].rawString)
        let span = LRSJoin.MeasureRange(from: 0, to: 1)
        let kept = LRSJoin.candidates(in: routes, routeID: id, near: interstate10, within: span)
        #expect(!kept.isEmpty)
    }

    @Test("Ordering is stable when nothing distinguishes two events")
    func stableWithoutGeometryOrMeasures() throws {
        let events = try featureSet("atis_24_i10")
        let route = "  I 010                         "
        let a = LRSJoin.candidates(in: events, routeID: route).map { $0["TracsNumber"].rawString }
        let b = LRSJoin.candidates(in: events, routeID: route).map { $0["TracsNumber"].rawString }
        #expect(a == b)
    }
}
