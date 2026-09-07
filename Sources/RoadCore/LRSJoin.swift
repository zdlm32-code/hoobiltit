import Foundation

/// Picks the linear-referencing *event* that actually applies to a dropped pin.
///
/// Every state LRS publishes attributes as separate "event" tables keyed by a route id and a
/// measure range along that route, so one envelope query returns every event the corridor
/// touches — not the one the pin is standing on. Two things go wrong if you skip this step:
///
/// 1. **Events from a different road.** In a residential box in Baton Rouge, Louisiana's
///    `Last Construction` layer returns exactly one row, and it belongs to a route none of the
///    sixteen streets in the box are on. Taking the first event in the envelope reports
///    *built 1971* for a street built at some entirely unknown date.
/// 2. **The wrong event on the right road.** This one is subtler and it is live in Arizona
///    today. On I-10 the improvement layer returns five events for ramp `I 010127E` with
///    `YearLastImprovement` of 2008, 2009 and 2011 across disjoint measure ranges, and the
///    project layer returns *thirteen* TRACS numbers for `I 010`. Matching on route id alone
///    and taking `.first` picks arbitrarily among genuinely different answers.
///
/// So the route id is a filter, never a selector. What actually locates the pin is geometry:
/// the event whose line passes nearest the coordinate. Measures narrow the field further where
/// the route layer publishes them — Arizona's does not, Louisiana's does — but they are a
/// filter and a fallback, not the primary ranking. The pin has a position; the nearest line to
/// it is the most direct evidence available of which event applies.
public enum LRSJoin {
    /// A span along a route. Stored as published and normalised on read, because measures
    /// sometimes descend (`ToMeasure` < `FromMeasure`) on reverse-cardinality routes.
    public struct MeasureRange: Sendable, Hashable {
        public let from: Double
        public let to: Double

        public init(from: Double, to: Double) {
            self.from = from
            self.to = to
        }

        public var lower: Double { min(from, to) }
        public var upper: Double { max(from, to) }
        public var length: Double { upper - lower }

        /// Shared length, zero when they merely touch.
        public func overlap(with other: MeasureRange) -> Double {
            max(0, min(upper, other.upper) - max(lower, other.lower))
        }

        /// Esri publishes measures that ought to be zero as `-3e-8`, so a bare `>` would call
        /// two abutting events overlapping. The epsilon is in route miles: 1e-6 is about 1.6 mm.
        public func overlaps(_ other: MeasureRange, epsilon: Double = 1e-6) -> Bool {
            overlap(with: other) > epsilon
        }
    }

    /// The span an event covers, or nil when the layer publishes no measures.
    ///
    /// ADOT ships measures as strings and Louisiana as numbers; `AttributeValue.double`
    /// already absorbs that difference.
    public static func measureRange(of feature: ArcGISFeature,
                                    fromField: String = "FromMeasure",
                                    toField: String = "ToMeasure") -> MeasureRange? {
        guard let from = feature[fromField].double, let to = feature[toField].double,
              from.isFinite, to.isFinite
        else { return nil }
        return MeasureRange(from: from, to: to)
    }

    /// Events on `routeID` that could apply at `point`, best first.
    ///
    /// - Parameters:
    ///   - routeID: compared **raw and exactly**. Route id formats share nothing across states
    ///     — Arizona space-pads to a fixed width (`"  I 010                         "`),
    ///     Louisiana runs two namespaces in one layer (`"013-04-1-010"` for control sections,
    ///     `"033900412201591020"` for local roads). Every LRS is internally consistent, and
    ///     this app never joins across services, so exact match is both sufficient and the
    ///     only thing that cannot manufacture a false join. Do not normalise.
    ///   - within: the pin's span on the route, when the route layer publishes one. Events
    ///     that do not overlap it are dropped.
    public static func candidates(in features: ArcGISFeatureSet,
                                  routeID: String,
                                  routeIDField: String = "RouteId",
                                  near point: Coordinate? = nil,
                                  within range: MeasureRange? = nil,
                                  fromField: String = "FromMeasure",
                                  toField: String = "ToMeasure") -> [ArcGISFeature] {
        let onRoute = features.features.filter { $0[routeIDField].rawString == routeID }

        let inRange: [ArcGISFeature]
        if let range {
            // A layer with no measures cannot be filtered by them; keeping such features is
            // right, because the alternative is discarding an event that may well apply.
            inRange = onRoute.filter { feature in
                guard let span = measureRange(of: feature, fromField: fromField, toField: toField)
                else { return true }
                return span.overlaps(range)
            }
        } else {
            inRange = onRoute
        }

        return rank(inRange, near: point, within: range, fromField: fromField, toField: toField)
    }

    /// The single event that applies, or nil.
    public static func best(in features: ArcGISFeatureSet,
                            routeID: String,
                            routeIDField: String = "RouteId",
                            near point: Coordinate? = nil,
                            within range: MeasureRange? = nil,
                            fromField: String = "FromMeasure",
                            toField: String = "ToMeasure") -> ArcGISFeature? {
        candidates(in: features, routeID: routeID, routeIDField: routeIDField, near: point,
                   within: range, fromField: fromField, toField: toField).first
    }

    /// Nearest line wins. Where geometry is missing the measure overlap decides, and where
    /// neither is available the agency's own order is preserved rather than invented.
    private static func rank(_ features: [ArcGISFeature],
                             near point: Coordinate?,
                             within range: MeasureRange?,
                             fromField: String,
                             toField: String) -> [ArcGISFeature] {
        // `enumerated` keeps the sort stable: `sorted(by:)` is not, and an unstable sort here
        // would make the answer depend on the agency's row order in a way tests cannot pin.
        let scored = features.enumerated().map { index, feature -> (Int, ArcGISFeature, Double?, Double) in
            let distance = point.flatMap { feature.distance(from: $0) }
            let span = measureRange(of: feature, fromField: fromField, toField: toField)
            let overlap = range.flatMap { r in span.map { $0.overlap(with: r) } } ?? 0
            return (index, feature, distance, overlap)
        }

        return scored.sorted { lhs, rhs in
            switch (lhs.2, rhs.2) {
            case let (l?, r?) where l != r: return l < r
            case (nil, _?): return false      // no geometry sorts after geometry
            case (_?, nil): return true
            default: break
            }
            if lhs.3 != rhs.3 { return lhs.3 > rhs.3 }   // more overlap wins
            return lhs.0 < rhs.0
        }.map(\.1)
    }
}
