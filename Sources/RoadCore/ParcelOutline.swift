import Foundation

/// A parcel boundary for drawing. Geometry only.
///
/// Kept apart from `ParcelReference` on purpose: that one is a *fact about a road* and rides in
/// the cached `RoadFragment`, and polygons have no business bloating that cache. This exists
/// for as long as the map is looking at a place, and no longer.
public struct ParcelOutline: Sendable, Hashable, Identifiable {
    public let apn: String
    /// Closed rings in drawing order. The first is the outer boundary.
    public let rings: [[Coordinate]]

    public var id: String { apn }

    public init(apn: String, rings: [[Coordinate]]) {
        self.apn = apn
        self.rings = rings
    }

    /// Metres from a point to this lot — zero when the point is inside it.
    public func distance(from point: Coordinate) -> Double {
        if contains(point) { return 0 }
        // A ring is a closed path, so the polyline measurement applies directly.
        return Geo.distance(from: point, toPolyline: rings) ?? .infinity
    }

    /// How far from the pin a lot can be and still be one of the lots facing it.
    ///
    /// A suburban lot is 20-30 m wide, so this reaches the ones either side of the point on
    /// the street without sweeping in the whole block.
    public static let frontingMeters: Double = 32
    /// A street corner can put four lots in range; beyond that the highlight stops meaning
    /// "the lots you are looking at".
    public static let frontingLimit = 4

    /// The lots facing a point, nearest first.
    ///
    /// The parcel *source* deliberately reports a single APN — an address is one lot. But the
    /// map was highlighting only that one, and standing in a street you are plainly looking at
    /// the lots on both sides of it. Highlighting one of them and dashing its neighbour implies
    /// a distinction the data does not make.
    public static func fronting(_ outlines: [ParcelOutline], at point: Coordinate,
                                limit: Int = frontingLimit) -> [ParcelOutline] {
        outlines
            .map { ($0, $0.distance(from: point)) }
            .filter { $0.1 <= frontingMeters }
            .sorted { $0.1 < $1.1 }
            .prefix(limit)
            .map(\.0)
    }

    /// True when the point falls in the outer ring.
    public func contains(_ point: Coordinate) -> Bool {
        guard let outer = rings.first else { return false }
        return Geo.ring(outer, contains: point)
    }

    /// Where to hang a label. Nil for a degenerate outline.
    public var labelAnchor: Coordinate? {
        rings.first.flatMap(Geo.centroid(of:))
    }
}

public extension Geo {
    /// Ray casting. True when the point falls inside the ring.
    ///
    /// Used to decide which parcel a tap landed on, which has to happen on the device: the
    /// boundaries are already drawn, and asking the server again just to identify one of them
    /// would be a request for something the app is looking at.
    static func ring(_ ring: [Coordinate], contains point: Coordinate) -> Bool {
        guard ring.count >= 3 else { return false }
        var inside = false
        var j = ring.count - 1
        for i in 0..<ring.count {
            let a = ring[i], b = ring[j]
            if (a.latitude > point.latitude) != (b.latitude > point.latitude) {
                let slope = (b.longitude - a.longitude) / (b.latitude - a.latitude)
                let crossing = a.longitude + (point.latitude - a.latitude) * slope
                if point.longitude < crossing { inside.toggle() }
            }
            j = i
        }
        return inside
    }

    /// Vertex average of a ring — not the true area centroid, but for a roughly convex parcel
    /// it lands inside the shape, which is all a label needs.
    static func centroid(of ring: [Coordinate]) -> Coordinate? {
        guard !ring.isEmpty else { return nil }
        var latitude = 0.0, longitude = 0.0
        for point in ring {
            latitude += point.latitude
            longitude += point.longitude
        }
        return Coordinate(latitude: latitude / Double(ring.count),
                          longitude: longitude / Double(ring.count))
    }

    /// Widest viewport at which parcel boundaries are worth drawing, about 1 km tall.
    ///
    /// This is a correctness gate, not a performance one. The Assessor layer caps a response at
    /// 1,000 features and says nothing when it truncates, so a wider query returns a *partial*
    /// cadastre that looks exactly like a complete one. Measured at Williams Dr, a 1 km *radius*
    /// hits that cap while a 500 m radius (≈0.009° of span) returns 678 — so this sits just
    /// under the measured safe point.
    ///
    /// It also has to clear the zoom the app itself lands on. MapKit inflates a requested span
    /// to fit the view's aspect ratio: asking for 0.004° yields 0.0058–0.0063° in practice, and
    /// an earlier 0.006 threshold sat exactly in that range, so the overlay flickered on and
    /// off at the app's own default zoom.
    static let parcelOverlayMaxSpanDegrees = 0.009

    static func parcelsWorthDrawing(at span: MapSpan) -> Bool {
        span.latitudeDelta <= parcelOverlayMaxSpanDegrees
    }

    /// Geometry simplification tolerance for the current viewport, in degrees.
    ///
    /// Halves the payload for boundaries that are visually identical at phone zoom, and scales
    /// with the span so it stays proportional to what a pixel is worth.
    static func simplificationTolerance(for span: MapSpan) -> Double {
        max(0.000002, span.latitudeDelta / 2000)
    }
}

public extension Envelope {
    /// True when `other` lies entirely inside this envelope, so a fetch can be skipped.
    func contains(_ other: Envelope) -> Bool {
        other.xmin >= xmin && other.xmax <= xmax && other.ymin >= ymin && other.ymax <= ymax
    }

    /// Grown by a fraction of its own size, so a small pan does not immediately fall outside
    /// what was fetched.
    func expanded(by factor: Double) -> Envelope {
        let dx = (xmax - xmin) * factor, dy = (ymax - ymin) * factor
        return Envelope(xmin: xmin - dx, ymin: ymin - dy, xmax: xmax + dx, ymax: ymax + dy)
    }
}
