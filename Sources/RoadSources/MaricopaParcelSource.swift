import Foundation
import RoadCore

/// The County Assessor's parcel fabric — who owns the land the road runs through.
///
/// Ported from the cellsurveys operator dashboard, which queries the same service for GPS
/// points. The difference here is that this app's pins land on *roads*, and a road sits in
/// the right-of-way between parcels: a point-in-polygon query at Williams Dr returns nothing
/// at all. So containment is tried first and frontage is the fallback, with the two clearly
/// distinguished — the owner of the parcel beside a road is not the owner of the road.
///
/// What it adds that no other source has:
/// - **APN and owner.** For a street the county has *not* accepted, the adjoining owner is
///   often who is actually responsible for it.
/// - **`CONST_YEAR`.** The year the buildings went up, which for a developer-built street
///   brackets when the street went in. On Williams Dr the frontage reads 2008–2009 and the
///   county declared the road in May 2009.
/// - **`SUBNAME` and `MCRNUM`,** which are the same subdivision name and Recorder book-page
///   the plat layer returns — an independent check on a value the app already shows.
public struct MaricopaParcelSource: RoadSource {
    public let id = "mcassessor.parcels"
    public let displayName = "Maricopa County Assessor"

    /// Shared with `ParcelBoundaryService`. Note the host: the public `mcassessor.maricopa.gov`
    /// is Cloudflare-fronted HTML, but `gis.mcassessor…` is a plain ArcGIS server.
    public static let layerURL = "https://gis.mcassessor.maricopa.gov/arcgis/rest/services/MaricopaDynamicQueryService/MapServer"
    public static let parcelLayerID = 3

    /// Frontage, not neighbourhood. Wide enough to reach across a right-of-way and catch the
    /// lots either side, tight enough that the sample is still *this* stretch of road.
    static let frontageRadiusMeters = 80.0

    private let client: ArcGISClient
    private let now: @Sendable () -> Date

    public init(client: ArcGISClient = ArcGISClient(), now: @escaping @Sendable () -> Date = Date.init) {
        self.client = client
        self.now = now
    }

    public func fetch(_ query: RoadQuery, resolved: RoadRecord) async throws -> RoadFragment {
        var fragment = RoadFragment()
        let point = query.coordinate
        let layer = ArcGISLayer(Self.layerURL, layer: Self.parcelLayerID)!

        // A pin-sized box first: "intersects" against a polygon layer is containment.
        let pin = Geo.envelope(around: point, radiusMeters: 1)
        let (contained, containedURL) = try await client.query(layer: layer, envelope: pin,
                                                               returnGeometry: false)
        if let feature = contained.features.first, let parcel = Self.parcel(from: feature, containsPin: true) {
            fragment.parcel = Attributed(parcel,
                                         provenance: provenance(url: containedURL, fetchedAt: now()),
                                         confidence: .direct)
            fragment.notes = [note(.contributed, Self.summary(parcel))]
            return fragment
        }

        let frontage = Geo.envelope(around: point, radiusMeters: Self.frontageRadiusMeters)
        let (nearby, nearbyURL) = try await client.query(layer: layer, envelope: frontage,
                                                         returnGeometry: true)
        guard let nearest = nearby.nearest(to: point),
              var parcel = Self.parcel(from: nearest, containsPin: false)
        else {
            fragment.notes = [note(.foundNothing, "No assessor parcel adjoins this point.")]
            return fragment
        }

        // One neighbour's build year is an anecdote; the spread across the frontage is a
        // reading on when the street was laid out.
        let years = nearby.features.compactMap { Self.year(from: $0["CONST_YEAR"]) }
        if let low = years.min(), let high = years.max(), low != high {
            parcel = ParcelReference(
                apn: parcel.apn, ownerName: parcel.ownerName, address: parcel.address,
                subdivisionName: parcel.subdivisionName, recorderNumber: parcel.recorderNumber,
                constructionYear: parcel.constructionYear, constructionYearRange: low...high,
                landSizeAcres: parcel.landSizeAcres, containsPin: false
            )
        }

        fragment.parcel = Attributed(parcel,
                                     provenance: provenance(url: nearbyURL, fetchedAt: now()),
                                     confidence: .spatial)
        fragment.notes = [note(.contributed, Self.summary(parcel))]
        return fragment
    }

    /// Full record for one parcel, for when a boundary on the map is tapped. The overlay only
    /// carries APNs, so the rest has to be fetched — but by identifier, not by geometry.
    public func parcel(forAPN apn: String) async -> ParcelReference? {
        let layer = ArcGISLayer(Self.layerURL, layer: Self.parcelLayerID)!
        guard let (features, _) = try? await client.query(layer: layer, field: "APN_DASH",
                                                          equals: apn),
              let feature = features.features.first
        else { return nil }
        // Tapped deliberately, so the pin is beside the point — this is the parcel asked for.
        return Self.parcel(from: feature, containsPin: true)
    }

    static func parcel(from feature: ArcGISFeature, containsPin: Bool) -> ParcelReference? {
        // APN_DASH is the human-readable form; APN is the same digits unpunctuated.
        guard let apn = feature["APN_DASH"].text ?? feature["APN"].text else { return nil }
        let squareFeet = feature["LAND_SIZE"].double
        return ParcelReference(
            apn: apn,
            ownerName: feature["OWNER_NAME"].text,
            address: feature["PHYSICAL_ADDRESS"].text,
            subdivisionName: feature["SUBNAME"].text,
            recorderNumber: feature["MCRNUM"].text,
            constructionYear: year(from: feature["CONST_YEAR"]),
            constructionYearRange: nil,
            landSizeAcres: squareFeet.map { $0 / 43_560 },
            containsPin: containsPin
        )
    }

    /// `CONST_YEAR` is a string, and vacant land carries "0" rather than nothing.
    static func year(from value: AttributeValue) -> Int? {
        guard let year = value.int, year > 1800, year <= 2200 else { return nil }
        return year
    }

    static func summary(_ parcel: ParcelReference) -> String {
        let where_ = parcel.containsPin ? "The pin falls inside parcel" : "Nearest parcel"
        var text = "\(where_) \(parcel.apn)"
        if let owner = parcel.ownerName { text += ", owned by \(owner)" }
        if let range = parcel.constructionYearRange {
            text += "; buildings alongside built \(range.lowerBound)\u{2013}\(range.upperBound)"
        } else if let year = parcel.constructionYear {
            text += "; built \(year)"
        }
        return text + "."
    }
}
