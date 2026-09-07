import Foundation

public struct Coordinate: Sendable, Hashable, Codable {
    public let latitude: Double
    public let longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

/// A WGS84 bounding box. Every spatial query in this app uses one.
///
/// Not a preference: `distance` + `units` point-buffering silently returns zero features on
/// the county's on-prem ArcGIS Server — no error, just an empty set (docs/ENDPOINTS.md §4).
/// Envelopes work on every host, so the client only knows how to build envelopes.
public struct Envelope: Sendable, Hashable {
    public let xmin, ymin, xmax, ymax: Double

    public init(xmin: Double, ymin: Double, xmax: Double, ymax: Double) {
        self.xmin = xmin; self.ymin = ymin; self.xmax = xmax; self.ymax = ymax
    }

    /// Esri's comma-delimited envelope form.
    public var queryValue: String { "\(xmin),\(ymin),\(xmax),\(ymax)" }
}

public enum Geo {
    static let metersPerDegreeLatitude = 111_320.0

    /// A square envelope around a point, sized in metres. Longitude degrees shrink with
    /// latitude, so the two axes scale differently.
    public static func envelope(around c: Coordinate, radiusMeters: Double) -> Envelope {
        let dLat = radiusMeters / metersPerDegreeLatitude
        let dLon = radiusMeters / (metersPerDegreeLatitude * max(cos(c.latitude * .pi / 180), 0.000001))
        return Envelope(xmin: c.longitude - dLon, ymin: c.latitude - dLat,
                        xmax: c.longitude + dLon, ymax: c.latitude + dLat)
    }

    /// Metres between two coordinates, equirectangular. Accurate well past county scale and
    /// dependency-free, so the resolver tests run on macOS without CoreLocation.
    public static func distance(_ a: Coordinate, _ b: Coordinate) -> Double {
        let (x, y) = project(b, relativeTo: a)
        return (x * x + y * y).squareRoot()
    }

    /// Metres from `point` to the nearest place on a polyline, measured perpendicular to
    /// whichever segment is closest — not to the nearest vertex.
    ///
    /// An envelope query returns every street crossing the box, so choosing the road the
    /// user actually meant happens here, on the client (docs/ENDPOINTS.md §4).
    public static func distance(from point: Coordinate, toPolyline paths: [[Coordinate]]) -> Double? {
        var best: Double?
        for path in paths {
            guard let first = path.first else { continue }
            if path.count == 1 {
                best = min(best ?? .infinity, distance(point, first))
                continue
            }
            for i in 0..<(path.count - 1) {
                let d = distance(from: point, toSegment: (path[i], path[i + 1]))
                best = min(best ?? .infinity, d)
            }
        }
        return best
    }

    /// Perpendicular distance in metres to a single two-point segment, clamped to its ends.
    static func distance(from point: Coordinate, toSegment seg: (Coordinate, Coordinate)) -> Double {
        let (ax, ay) = project(seg.0, relativeTo: point)
        let (bx, by) = project(seg.1, relativeTo: point)
        let dx = bx - ax, dy = by - ay
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return (ax * ax + ay * ay).squareRoot() }

        // Project the origin (the pin) onto AB, clamped to the segment.
        let t = max(0, min(1, -(ax * dx + ay * dy) / lengthSquared))
        let cx = ax + t * dx, cy = ay + t * dy
        return (cx * cx + cy * cy).squareRoot()
    }

    /// Local planar metres of `c` relative to `origin`.
    private static func project(_ c: Coordinate, relativeTo origin: Coordinate) -> (x: Double, y: Double) {
        let latRadians = origin.latitude * .pi / 180
        let x = (c.longitude - origin.longitude) * metersPerDegreeLatitude * cos(latRadians)
        let y = (c.latitude - origin.latitude) * metersPerDegreeLatitude
        return (x, y)
    }
}

/// A map viewport's extent in degrees. Mirrors `MKCoordinateSpan` without depending on MapKit,
/// so the zoom arithmetic can be tested without a map.
public struct MapSpan: Sendable, Hashable {
    public let latitudeDelta: Double
    public let longitudeDelta: Double

    public init(latitudeDelta: Double, longitudeDelta: Double) {
        self.latitudeDelta = latitudeDelta
        self.longitudeDelta = longitudeDelta
    }
}

public extension Geo {
    /// About 55 m across. Tighter than this and the map is inside the road, with no context.
    static let minimumSpanDegrees = 0.0005
    /// About the width of the continental United States.
    ///
    /// Was 2.0 — roughly one county — on the reasoning that "wider and every pin is a guess".
    /// That conflated navigating with pinning: the lookup radius is 150 m however far out the
    /// map is zoomed, and a driver crossing states could not zoom out far enough to see where
    /// they were going.
    static let maximumSpanDegrees = 45.0

    /// Scales a viewport for a zoom button, keeping its aspect ratio and staying inside the
    /// useful range.
    ///
    /// Both deltas are driven by a single clamped factor rather than clamped independently:
    /// clamping each on its own squashes the viewport out of shape as soon as one axis hits a
    /// limit, which shows up as the map visibly distorting at maximum zoom.
    static func scaledSpan(_ span: MapSpan, by factor: Double) -> MapSpan {
        guard factor > 0, span.latitudeDelta > 0, span.longitudeDelta > 0 else { return span }

        var allowed = factor
        let scaledLatitude = span.latitudeDelta * factor
        if scaledLatitude < minimumSpanDegrees {
            allowed = minimumSpanDegrees / span.latitudeDelta
        } else if scaledLatitude > maximumSpanDegrees {
            allowed = maximumSpanDegrees / span.latitudeDelta
        }
        // A viewport already outside the range must not be dragged further out by a clamp
        // that points the wrong way.
        if (factor < 1 && allowed > 1) || (factor > 1 && allowed < 1) { return span }

        return MapSpan(latitudeDelta: span.latitudeDelta * allowed,
                       longitudeDelta: span.longitudeDelta * allowed)
    }

    /// True when zooming further in would do nothing, so the button can disable itself.
    static func canZoomIn(_ span: MapSpan) -> Bool {
        span.latitudeDelta > minimumSpanDegrees * 1.0001
    }

    static func canZoomOut(_ span: MapSpan) -> Bool {
        span.latitudeDelta < maximumSpanDegrees * 0.9999
    }
}

/// What moved the map camera.
///
/// A camera change carries no indication of who caused it, and a follow-the-device update
/// looks identical to a user pan. Distinguishing them by "how far the centre drifted from the
/// device" needed an allowance so generous — 226 m at the follow zoom — that panning to aim at
/// a nearby road no longer ended the follow, and the next fix quietly snapped the camera back.
public enum CameraChange: Equatable {
    /// The user moved the centre. Following should stop.
    case panned
    /// The user changed the zoom without moving off target. Following continues.
    case zoomed
    /// Nothing meaningful changed.
    case negligible
}

public extension Geo {
    /// Centre movement below this is not a pan — it is float noise or a settling animation.
    static let panThresholdMeters = 12.0
    /// Fractional span change below this is not a zoom.
    static let zoomThresholdFraction = 0.02
    /// Camera changes arriving within this of a programmatic move are the app's own.
    static let programmaticSettleWindow: TimeInterval = 1.2

    /// Bounds for the follow camera's distance, in metres.
    ///
    /// A zoom while merely looking around must never become the follow distance: on launch the
    /// camera sits at the wide fallback, and adopting *that* distance sent the follow camera
    /// to 337 km — the map stayed on the whole county while the road under the device was
    /// identified perfectly well.
    ///
    /// The real guard against that is `hasFollowedOnce`, which refuses to adopt any distance
    /// until the camera has actually followed the device at least once. This range is the
    /// backstop, and its ceiling used to be 4 km — close enough that zooming out to see where
    /// you were *going* hit the wall almost at once, and the next GPS fix yanked the camera
    /// back in. 250 km is a whole-region view, past any real driving need, and still well
    /// below the 337 km failure it exists to catch.
    static let followDistanceRange: ClosedRange<Double> = 120...250_000

    static func clampFollowDistance(_ metres: Double) -> Double {
        min(max(metres, followDistanceRange.lowerBound), followDistanceRange.upperBound)
    }

    /// Fraction by which the camera's distance must differ from the one the app asked for
    /// before it counts as the user having zoomed. Covers animation overshoot and the small
    /// distance drift MapKit introduces when it recentres.
    static let zoomAdoptionFraction = 0.05

    /// Did this camera distance come from the user rather than from us?
    ///
    /// Timing cannot answer this while driving. The programmatic-settle window exists to stop
    /// the app's own recentring being read as a gesture, but the location provider delivers a
    /// fix every 25 m — about every 1.2 s at 45 mph — and the settle window is 1.2 s, so while
    /// moving the window is *always* open and every user gesture was being discarded. That is
    /// why zooming out while driving did not stick: the zoom was never adopted, and the next
    /// fix reset the camera to the old distance.
    ///
    /// Identity answers it. The follow camera is always set to exactly `followDistance`, so a
    /// distance materially different from the one requested cannot have come from the app.
    /// Centre is not usable this way — the app moves it on every fix — but distance is.
    static func userChangedZoom(observed: Double, expected: Double) -> Bool {
        guard expected > 0, observed > 0, observed.isFinite, expected.isFinite else { return false }
        return abs(observed - expected) / expected > zoomAdoptionFraction
    }

    /// How long after a user zoom the app leaves the camera alone.
    ///
    /// A pinch emits a stream of camera changes; recentring on a GPS fix in the middle of one
    /// fights the gesture and the zoom never lands where the user let go. Each change refreshes
    /// the window, so the app stays out of the way until the fingers lift.
    static let userZoomGraceWindow: TimeInterval = 0.9

    /// Classifies a camera change the app did **not** make.
    ///
    /// Whether a change was the app's own is decided by the caller on timing, not geometry: an
    /// animated programmatic move emits intermediate changes that do not match the requested
    /// centre, and treating those as user pans turned follow-on-launch off before the camera
    /// ever arrived.
    static func classifyCameraChange(from previous: MapSpan,
                                     previousCentre: Coordinate,
                                     to current: MapSpan,
                                     currentCentre: Coordinate) -> CameraChange {
        let moved = distance(previousCentre, currentCentre)
        let spanDelta = previous.latitudeDelta > 0
            ? abs(current.latitudeDelta - previous.latitudeDelta) / previous.latitudeDelta
            : 0

        if moved > panThresholdMeters { return .panned }
        if spanDelta > zoomThresholdFraction { return .zoomed }
        return .negligible
    }

    /// A round distance for a scale bar, and its label.
    ///
    /// Picks from 1/2/5 × 10ⁿ so the bar reads as a real measurement rather than "417 ft".
    /// Imperial, because the county publishes road widths and depths in feet.
    static func scaleBarDistance(fitting metres: Double) -> (metres: Double, label: String) {
        let feetPerMetre = 3.280839895
        let metresPerMile = 1609.344
        let candidatesFeet: [Double] = [10, 20, 50, 100, 200, 500, 1000, 2000]
        let candidatesMiles: [Double] = [0.5, 1, 2, 5, 10, 20, 50, 100]

        let feet = metres * feetPerMetre
        if feet < 2640 {                                   // under half a mile: feet
            let pick = candidatesFeet.last { $0 <= feet } ?? candidatesFeet[0]
            return (pick / feetPerMetre, "\(Int(pick)) ft")
        }
        let miles = metres / metresPerMile
        let pick = candidatesMiles.last { $0 <= miles } ?? candidatesMiles[0]
        let label = pick < 1 ? "½ mi" : "\(Int(pick)) mi"
        return (pick * metresPerMile, label)
    }
}
