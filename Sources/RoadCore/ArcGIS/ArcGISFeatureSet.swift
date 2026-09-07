import Foundation

/// One attribute value out of an Esri JSON `attributes` object.
///
/// The accessors are where the county's and ADOT's string handling gets cleaned up, once,
/// rather than at every call site: names arrive space-padded with a trailing route suffix
/// (`"Williams Dr                             01"`), and ADOT ships every measure and date as
/// a string (docs/ENDPOINTS.md §5.3).
public enum AttributeValue: Sendable, Hashable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    /// Raw string, untouched.
    public var rawString: String? {
        switch self {
        case .string(let s): s
        case .number(let d): d == d.rounded() ? String(Int(d)) : String(d)
        case .bool(let b): String(b)
        case .null: nil
        }
    }

    /// Trimmed and whitespace-collapsed, with empty and whitespace-only mapped to nil.
    /// This is the accessor to reach for; `rawString` is for round-tripping.
    ///
    /// It deliberately does **not** strip trailing route suffixes — see `roadName`. The
    /// maintained-roads layer carries genuine names ending in numbers (`MC 85`, `Old US 80`,
    /// `Old SR 87`, `FR 206`) and stripping here would mangle them.
    public var text: String? {
        guard let raw = rawString else { return nil }
        let collapsed = raw.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
        let cleaned = collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }

    /// `text`, plus removal of the padded route-segment ordinal that the *county project*
    /// layers append to road names: `"Deer Valley Rd                          01"`.
    ///
    /// Use this only for `OnRoadName`/`FromRefName`/`ToRefName` on BOS/Transportation. The
    /// ordinal is not always `01` (02, 03, 04, 10, 14, 1001 … all occur), so it is
    /// identified by its padding — two or more spaces — rather than by value. Requiring the
    /// padding is what keeps `MC 85` intact.
    ///
    /// The ordinal is sometimes followed by a jurisdiction — `"52nd Pl        01 Mesa"`,
    /// `"Buttonwood Dr        01 Maricopa County"` — on 68 of 438 distinct values in layer
    /// 770, so everything from the padded ordinal onward is dropped. Nothing but a
    /// jurisdiction or a repeated ordinal was ever observed after it, and the app resolves
    /// jurisdiction authoritatively from the municipality polygon anyway.
    ///
    /// One row in layer 770 is stored as `"Lower Buckeye Rd 01"` with a single space, a
    /// duplicate of the correctly-padded `"Lower Buckeye Rd                        01"`. It
    /// keeps its suffix, which is a cosmetic miss on one value and a deliberate trade
    /// against corrupting real road names.
    public var roadName: String? {
        guard let raw = rawString else { return nil }
        let stripped = raw.replacing(#/\s{2,}\d{1,4}\b.*$/#, with: "")
        let collapsed = stripped.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
        let cleaned = collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }

    public var double: Double? {
        switch self {
        case .number(let d): d
        case .string(let s): Double(s.trimmingCharacters(in: .whitespaces))
        case .bool, .null: nil
        }
    }

    public var int: Int? {
        guard let d = double, d.isFinite else { return nil }
        return Int(d)
    }

    /// Esri epoch milliseconds. `-2208988800000` (1900-01-01) is the county's null sentinel
    /// and is treated as absent.
    public var epochMillisecondsDate: Date? {
        guard let ms = double, ms != -2_208_988_800_000 else { return nil }
        return Date(timeIntervalSince1970: ms / 1000)
    }

    /// ADOT ships dates as strings: `"20110130"` or `"20160624070000"` (§5.3).
    public var compactStringDate: Date? {
        guard let s = rawString?.trimmingCharacters(in: .whitespaces), s.count >= 8,
              let year = Int(s.prefix(4)), let month = Int(s.dropFirst(4).prefix(2)),
              let day = Int(s.dropFirst(6).prefix(2)),
              (1...12).contains(month), (1...31).contains(day), year > 1900
        else { return nil }
        var components = DateComponents()
        components.year = year; components.month = month; components.day = day
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: components)
    }

    public var url: URL? { text.flatMap(URL.init(string:)) }
}

extension AttributeValue: Decodable {
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let d = try? c.decode(Double.self) { self = .number(d) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else { self = .null }
    }
}

/// Esri geometry. The app never draws from these, it measures with them, so only the shapes
/// that carry position are read: `paths` (polyline), `rings` (polygon), and bare `x`/`y`
/// (point — the county's spot-improvement layers are points, and omitting this would drop
/// them silently rather than visibly).
public struct ArcGISGeometry: Sendable, Decodable {
    public let paths: [[[Double]]]?
    public let rings: [[[Double]]]?
    public let x: Double?
    public let y: Double?

    /// Every vertex as coordinates. Esri orders pairs `[x, y]`, i.e. longitude first, and a
    /// point becomes a single-vertex path so distance measurement has one code path.
    public var coordinatePaths: [[Coordinate]] {
        if let x, let y {
            return [[Coordinate(latitude: y, longitude: x)]]
        }
        return (paths ?? rings ?? []).map { path in
            path.compactMap { pair in
                pair.count >= 2 ? Coordinate(latitude: pair[1], longitude: pair[0]) : nil
            }
        }
    }
}

public struct ArcGISFeature: Sendable, Decodable {
    public let attributes: [String: AttributeValue]
    public let geometry: ArcGISGeometry?

    public subscript(_ field: String) -> AttributeValue {
        attributes[field] ?? .null
    }

    /// Metres from the pin to this feature, or nil when the feature carried no geometry.
    public func distance(from point: Coordinate) -> Double? {
        guard let paths = geometry?.coordinatePaths, !paths.isEmpty else { return nil }
        return Geo.distance(from: point, toPolyline: paths)
    }
}

/// An ArcGIS error response. The service returns HTTP 200 with this body, so it has to be
/// checked explicitly rather than left to the status code.
public struct ArcGISErrorPayload: Sendable, Decodable {
    public struct Body: Sendable, Decodable {
        public let code: Int?
        public let message: String?
        public let details: [String]?
    }
    public let error: Body
}

public struct ArcGISFeatureSet: Sendable, Decodable {
    public let features: [ArcGISFeature]

    public var isEmpty: Bool { features.isEmpty }

    /// The feature whose geometry is nearest the pin. Envelope queries return everything
    /// crossing the box, so this is how the road the user meant gets chosen.
    ///
    /// Features without geometry sort last but are still eligible, so a layer queried with
    /// `returnGeometry=false` still yields a result.
    public func nearest(to point: Coordinate) -> ArcGISFeature? {
        features.min { lhs, rhs in
            (lhs.distance(from: point) ?? .infinity) < (rhs.distance(from: point) ?? .infinity)
        }
    }
}
