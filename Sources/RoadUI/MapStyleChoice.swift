import SwiftUI
import MapKit
import CoreLocation
import RoadCore

/// The map styles worth offering here.
///
/// Satellite is not decoration for this app: on imagery you can see the actual pavement, count
/// the lanes, and tell whether a street was cut as one piece of a subdivision — which is the
/// same story the plat and road-declaration records are telling in text.
public enum MapStyleChoice: String, CaseIterable, Identifiable, Sendable {
    case standard
    case hybrid
    case imagery

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .standard: "Standard"
        case .hybrid: "Hybrid"
        case .imagery: "Satellite"
        }
    }

    public var symbol: String {
        switch self {
        case .standard: "map"
        case .hybrid: "globe.americas"
        case .imagery: "photo"
        }
    }

    /// `.realistic` rather than `.flat` so the pitch control has something to tilt.
    public var mapStyle: MapStyle { mapStyle(reduced: false) }

    /// The driving version strips the map back to the road you are on.
    ///
    /// Terrain shading, points of interest and full-strength labels are all things to read
    /// while parked. At speed they are glare and clutter around the one line that matters, and
    /// realistic elevation costs GPU on a phone already running GPS on a hot dashboard. Worth
    /// doing in daylight too, not only at night.
    public func mapStyle(reduced: Bool) -> MapStyle {
        let elevation: MapStyle.Elevation = reduced ? .flat : .realistic
        switch self {
        case .standard:
            return .standard(elevation: elevation,
                             emphasis: reduced ? .muted : .automatic,
                             pointsOfInterest: reduced ? .excludingAll : .all)
        case .hybrid:
            return .hybrid(elevation: elevation,
                           pointsOfInterest: reduced ? .excludingAll : .all)
        case .imagery:
            return .imagery(elevation: elevation)
        }
    }
}

/// When drive mode goes dark.
///
/// Three states rather than a switch, because "auto" has to mean something better than the
/// system appearance: most people leave iOS on Light permanently, so keying off it leaves the
/// map blinding at 9 pm — the exact thing a night mode is for. Auto asks where the sun is.
public enum DriveAppearance: String, CaseIterable, Identifiable, Sendable {
    case auto, day, night

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .auto: "Auto"
        case .day: "Day"
        case .night: "Night"
        }
    }

    public var symbol: String {
        switch self {
        case .auto: "circle.lefthalf.filled"
        case .day: "sun.max"
        case .night: "moon"
        }
    }

    /// - Parameter wasNight: the current state, so `auto` can apply hysteresis and not flap
    ///   while the sun sits on the horizon.
    public func isNight(at coordinate: Coordinate?, now: Date = .now, wasNight: Bool) -> Bool {
        switch self {
        case .day: return false
        case .night: return true
        case .auto:
            // No fix yet is treated as daylight: a dark map on a bright morning is a worse
            // first impression than a bright one at dusk, and the next fix corrects it.
            guard let coordinate else { return false }
            return SolarPosition.isNight(at: coordinate, on: now, wasNight: wasNight)
        }
    }
}

/// Bridges the MapKit viewport type to the plain-numbers one the zoom arithmetic uses, so that
/// arithmetic can live in `RoadCore` and be tested without a map.
public extension MKCoordinateRegion {
    var mapSpan: MapSpan {
        MapSpan(latitudeDelta: span.latitudeDelta, longitudeDelta: span.longitudeDelta)
    }
}

public extension MapSpan {
    var coordinateSpan: MKCoordinateSpan {
        MKCoordinateSpan(latitudeDelta: latitudeDelta, longitudeDelta: longitudeDelta)
    }
}


public extension Coordinate {
    /// Bridge to MapKit at the drawing edge, so `RoadCore` stays free of MapKit.
    var clLocation: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
