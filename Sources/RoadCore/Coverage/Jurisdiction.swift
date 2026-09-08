import Foundation

/// Where a coordinate is, in the terms the coverage catalog is keyed on.
///
/// FIPS codes rather than names, because names are not unique or stable: there is a King
/// County in Washington and a King and Queen County in Virginia, and a search for one finds
/// the other. `04013` finds only Maricopa.
public struct Jurisdiction: Sendable, Hashable, Codable {
    /// Two digits, zero-padded. `"04"` is Arizona, `"42"` Pennsylvania, `"22"` Louisiana.
    public let stateFIPS: String
    /// Five digits: state then county. `"04013"` is Maricopa County, Arizona.
    public let countyFIPS: String
    /// The county's own name for itself.
    ///
    /// Rendered verbatim and never suffixed. Louisiana returns `"East Baton Rouge Parish"`,
    /// Alaska returns boroughs and census areas, and Virginia has independent cities that are
    /// county equivalents. Appending "County" would be wrong in four states and Puerto Rico.
    public let countyName: String
    /// The incorporated place, when the coordinate is inside one. Nil in unincorporated
    /// county — which is a real answer, not a lookup failure.
    public let placeName: String?
    public let placeGEOID: String?

    public init(stateFIPS: String, countyFIPS: String, countyName: String,
                placeName: String? = nil, placeGEOID: String? = nil) {
        self.stateFIPS = stateFIPS
        self.countyFIPS = countyFIPS
        self.countyName = countyName
        self.placeName = placeName
        self.placeGEOID = placeGEOID
    }

    /// "Maricopa County, Arizona" — for the card, when no better source named the place.
    public var description: String {
        let state = Self.stateNames[stateFIPS]
        return [countyName, state].compactMap { $0 }.joined(separator: ", ")
    }
}

/// Turns a coordinate into a `Jurisdiction`, cheaply enough to run on every GPS fix.
///
/// The naive shape — one Census request per fix — is unusable in drive mode: the location
/// provider's `distanceFilter` is 25 m, so that is a network round trip every 25 metres, on
/// battery, in a car.
///
/// Two things make it cheap. The lookup **memoises on a ~110 m grid**, which is smaller than
/// the app's own 150 m query radius and so cannot be more wrong than the query already is.
/// And on a hit it keeps the county's **simplified boundary polygon**, so "am I still in the
/// same county?" is answered locally by ray casting with no network at all. Measured, a
/// county boundary at `maxAllowableOffset=0.001` is 109-388 vertices and 2-8 KB: Philadelphia
/// 109, Suffolk MA 128, Maricopa 219, East Baton Rouge 269, King WA 388. One request per
/// county entered, zero while driving inside one.
///
/// Everything goes through `ArcGISClient`, so these queries are **envelopes** like every other
/// query in the app. TIGERweb accepts a point-plus-distance form too, but adopting it here
/// would put a second query shape into the app — and the envelope-only rule is what makes the
/// app immune to the Caltrans/WSDOT/FDOT bug where a point buffer returns zero features with
/// HTTP 200. Preserving that by construction beats preserving it by discipline.
public actor JurisdictionLocator {
    public static let service = "https://tigerweb.geo.census.gov/arcgis/rest/services/TIGERweb"
    /// Current-vintage counties. The service publishes 71 layers — repeated state/county
    /// pairs, one per vintage — and layer 1 is the current one.
    static let countyLayer = ArcGISLayer("\(service)/State_County/MapServer", layer: 1)!
    static let placeLayer = ArcGISLayer("\(service)/Places_CouSub_ConCity_SubMCD/MapServer", layer: 4)!

    /// Fine enough that the whole county is not generalised away at its edge, coarse enough
    /// to stay a few kilobytes.
    static let boundarySimplification = 0.001
    /// A degenerate envelope is rejected, so the point query is a very small box. 2 m is well
    /// under any boundary's resolution.
    static let pointRadiusMeters = 2.0
    /// ~110 m. Deliberately below the 150 m road-search radius.
    static let memoDecimalPlaces = 3.0
    /// How far the pin may drift from an *unincorporated* answer before the place is checked
    /// again. There is no polygon to test containment against when the answer was "no place",
    /// so this bounds how long the app can be wrong about having entered a city. Inside a
    /// place the boundary answers exactly and this never applies.
    static let placeRecheckMeters = 1_000.0

    private let client: ArcGISClient
    private var memo: [String: Jurisdiction] = [:]
    /// The county last resolved, with its boundary, so containment is answered locally.
    private var currentCounty: (jurisdiction: Jurisdiction, ring: [Coordinate])?
    /// The incorporated place last resolved, with its boundary. Nil when the last fix was in
    /// unincorporated county, which is a real answer and not a missing one.
    private var currentPlace: [Coordinate]?
    /// Where the place was last actually looked up. Only consulted when there is no place
    /// boundary to test against — see `locate`.
    private var placeResolvedAt: Coordinate?
    /// Counted so a test can prove drive mode is not issuing a request per fix.
    public private(set) var requestCount = 0

    public init(client: ArcGISClient = ArcGISClient()) {
        self.client = client
    }

    public func locate(_ coordinate: Coordinate) async -> Jurisdiction? {
        // 1. Still inside the county we already hold? No network, no memo, just geometry.
        if let current = currentCounty, Geo.ring(current.ring, contains: coordinate) {
            // The place can still change within a county, so keep the memo authoritative for
            // the finer-grained answer and only short-circuit when it agrees.
            if let remembered = memo[Self.memoKey(coordinate)] { return remembered }
            if placeStillHolds(at: coordinate) { return current.jurisdiction }
            // The city changed, or may have. Returning the held answer here is what made the
            // drive card name the place you were in when you first entered the county and keep
            // naming it for the rest of the drive.
            return await fetch(coordinate)
        }
        if let remembered = memo[Self.memoKey(coordinate)] { return remembered }
        return await fetch(coordinate)
    }

    /// Whether the place on the held jurisdiction is still the right one for this point.
    ///
    /// Inside a city the boundary answers exactly, and a long drive across one city costs no
    /// requests at all. Outside every city there is nothing to test, so the answer is trusted
    /// for `placeRecheckMeters` and then checked again — bounded staleness rather than the
    /// unbounded kind, and only in unincorporated county.
    private func placeStillHolds(at coordinate: Coordinate) -> Bool {
        if let ring = currentPlace { return Geo.ring(ring, contains: coordinate) }
        guard let origin = placeResolvedAt else { return false }
        return Geo.distance(origin, coordinate) < Self.placeRecheckMeters
    }

    private func fetch(_ coordinate: Coordinate) async -> Jurisdiction? {
        let envelope = Geo.envelope(around: coordinate, radiusMeters: Self.pointRadiusMeters)
        requestCount += 1

        async let countyResult = try? client.query(
            layer: Self.countyLayer, envelope: envelope,
            outFields: "GEOID,NAME,STATE,COUNTY", returnGeometry: true,
            maxAllowableOffset: Self.boundarySimplification)
        async let placeResult = try? client.query(
            layer: Self.placeLayer, envelope: envelope,
            outFields: "GEOID,NAME", returnGeometry: true,
            maxAllowableOffset: Self.boundarySimplification)

        guard let county = await countyResult?.features.features.first,
              let geoid = county["GEOID"].text, geoid.count == 5,
              let name = county["NAME"].text
        else { return nil }

        // A place miss is a normal answer — unincorporated county — not a failure.
        let place = await placeResult?.features.features.first

        let jurisdiction = Jurisdiction(
            stateFIPS: String(geoid.prefix(2)),
            countyFIPS: geoid,
            countyName: name,
            placeName: place?["NAME"].text,
            placeGEOID: place?["GEOID"].text
        )

        memo[Self.memoKey(coordinate)] = jurisdiction
        if let ring = county.geometry?.coordinatePaths.max(by: { $0.count < $1.count }), ring.count > 2 {
            currentCounty = (jurisdiction, ring)
        }
        // Largest ring only, as for the county. A city with detached parts — Houston publishes
        // 100 rings — reads as "left the place" in an outlying piece, which costs one refetch
        // and returns the right answer rather than a wrong one.
        let placeRing = place?.geometry?.coordinatePaths.max(by: { $0.count < $1.count })
        currentPlace = (placeRing?.count ?? 0) > 2 ? placeRing : nil
        placeResolvedAt = coordinate
        return jurisdiction
    }

    static func memoKey(_ coordinate: Coordinate) -> String {
        let scale = pow(10, memoDecimalPlaces)
        let lat = (coordinate.latitude * scale).rounded() / scale
        let lon = (coordinate.longitude * scale).rounded() / scale
        return String(format: "%.3f,%.3f", lat, lon)
    }
}

public extension Jurisdiction {
    /// State names by FIPS, for rendering "Harris County, Texas" without a second request.
    /// The list does not change.
    static let stateNames: [String: String] = [
        "01": "Alabama", "02": "Alaska", "04": "Arizona", "05": "Arkansas", "06": "California",
        "08": "Colorado", "09": "Connecticut", "10": "Delaware", "11": "District of Columbia",
        "12": "Florida", "13": "Georgia", "15": "Hawaii", "16": "Idaho", "17": "Illinois",
        "18": "Indiana", "19": "Iowa", "20": "Kansas", "21": "Kentucky", "22": "Louisiana",
        "23": "Maine", "24": "Maryland", "25": "Massachusetts", "26": "Michigan",
        "27": "Minnesota", "28": "Mississippi", "29": "Missouri", "30": "Montana",
        "31": "Nebraska", "32": "Nevada", "33": "New Hampshire", "34": "New Jersey",
        "35": "New Mexico", "36": "New York", "37": "North Carolina", "38": "North Dakota",
        "39": "Ohio", "40": "Oklahoma", "41": "Oregon", "42": "Pennsylvania",
        "44": "Rhode Island", "45": "South Carolina", "46": "South Dakota", "47": "Tennessee",
        "48": "Texas", "49": "Utah", "50": "Vermont", "51": "Virginia", "53": "Washington",
        "54": "West Virginia", "55": "Wisconsin", "56": "Wyoming", "60": "American Samoa",
        "66": "Guam", "69": "Northern Mariana Islands", "72": "Puerto Rico",
        "78": "US Virgin Islands",
    ]
}
