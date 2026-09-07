import Foundation

/// How much of the question this build can answer where the pin is.
public enum CoverageLevel: String, Sendable, Codable, Comparable, CaseIterable {
    /// Nothing but the national tier: a street name, and an owner only on the ~498k segments
    /// of the National Highway System.
    case national
    /// A state DOT publishes this road.
    case state
    /// Somebody has done the reconnaissance for this county, Maricopa-style.
    case county

    public static func < (lhs: Self, rhs: Self) -> Bool {
        let order: [Self] = [.national, .state, .county]
        return order.firstIndex(of: lhs)! < order.firstIndex(of: rhs)!
    }
}

/// Which generic adapter reads a jurisdiction's service, or that it needs hand-written Swift.
///
/// The two generic shapes are not a field-naming difference and one adapter cannot cover both.
/// Of fourteen state DOTs probed, roughly half publish a single denormalised polyline carrying
/// every attribute (`flatInventory`) and half decompose attributes into separate event tables
/// joined on a route id and a measure range (`lrsEvents`).
public enum CoverageAdapter: String, Sendable, Codable {
    case flatInventory
    case lrsEvents
    /// Sources compiled into the app. A county mapped to Maricopa's depth encodes judgement —
    /// concluding ownership from a layer's *silence*, disambiguating coincident geometry,
    /// gating a join on a name — that configuration should not try to express.
    case bespoke
}

/// Which shipped table decodes a coded field. `nil` means the value is already prose.
public enum CodeTableReference: String, Sendable, Codable {
    case hpmsOwnership
    case fhwaFunctionalClass
    case penndotJurisdiction
}

/// How a year is stored. Verified encodings: PennDOT writes a plain `1916`, ADOT a compact
/// string `"20031110"`, Maricopa Esri epoch milliseconds.
public enum YearEncoding: String, Sendable, Codable {
    case yearNumber
    case compactString
    case epochMilliseconds
}

/// The field names one layer uses for the facts the app reports.
///
/// Every slot is optional because no service publishes all of them, and a profile that names
/// a field the layer does not have simply contributes nothing for it.
public struct FieldMapping: Sendable, Codable, Hashable {
    /// Ordered; the first that yields a value wins. King County and Cook County split names
    /// into left- and right-of-centreline variants, so more than one candidate is normal.
    public var name: [String]?
    /// Joined with a space to form a route designation, e.g. PennDOT's
    /// `TRAF_RT_NO_PREFIX` + `TRAF_RT_NO`.
    public var routeDesignation: [String]?
    public var ownership: String?
    public var ownershipTable: CodeTableReference?
    public var yearBuilt: String?
    public var yearImproved: String?
    public var yearEncoding: YearEncoding?
    public var functionalClass: String?
    public var functionalClassTable: CodeTableReference?
    public var aadt: String?
    public var crossStreetFrom: String?
    public var crossStreetTo: String?

    /// Values that mean "no value" and must never reach the screen.
    ///
    /// This is not defensive padding. PennDOT writes `YR_BUILT = 0` on all 11,737 locally
    /// owned segments; without this the app reports *built in year 0* — or, once a decoder
    /// gets hold of it, *1970* — for every local road in Pennsylvania. Maricopa's sentinel is
    /// `-2208988800000` and NBI's is `0`.
    public var nullNumbers: [Double]?

    /// Text values that mean "no value".
    ///
    /// Distinct from `nullNumbers` because the sentinel is often a *string* that would parse
    /// as a perfectly good number. PennDOT writes `TRAF_RT_NO = "000"` on every road that
    /// carries no signed route number, so without this the app labels an ordinary city street
    /// "Route 000".
    public var nullStrings: [String]?

    public init() {}

    public func isNull(_ value: Double) -> Bool {
        (nullNumbers ?? []).contains(value)
    }

    public func isNull(_ value: String) -> Bool {
        (nullStrings ?? []).contains(value)
    }
}

/// One event table in an LRS, and what it contributes.
public struct EventLayerProfile: Sendable, Codable, Hashable {
    public var layer: Int
    /// Shown in provenance, so the card can say which table an answer came from.
    public var displayName: String
    public var routeIDField: String
    public var fromMeasureField: String
    public var toMeasureField: String
    public var fields: FieldMapping

    public init(layer: Int, displayName: String, routeIDField: String = "RouteID",
                fromMeasureField: String = "FromMeasure", toMeasureField: String = "ToMeasure",
                fields: FieldMapping) {
        self.layer = layer
        self.displayName = displayName
        self.routeIDField = routeIDField
        self.fromMeasureField = fromMeasureField
        self.toMeasureField = toMeasureField
        self.fields = fields
    }
}

/// The centreline drive mode's cheap "which road am I on" probe should read here.
///
/// Drive mode runs this on every fix and the full pipeline only when the answer changes, so
/// it has to be one fast service. Census TIGER/Line is the default because it covers the whole
/// country; a jurisdiction with a better centreline of its own can name it here and get its
/// own naming and its own classification wording instead.
public struct CentrelineProfile: Sendable, Codable, Hashable {
    public var service: String
    /// Queried concurrently. Services routinely split roads across layers by class with no
    /// combined layer to query.
    public var layers: [Int]
    public var nameField: String
    public var classificationField: String?
    public var minimumRadiusMeters: Double?

    public init(service: String, layers: [Int], nameField: String,
                classificationField: String? = nil, minimumRadiusMeters: Double? = nil) {
        self.service = service
        self.layers = layers
        self.nameField = nameField
        self.classificationField = classificationField
        self.minimumRadiusMeters = minimumRadiusMeters
    }
}

/// A jurisdiction's road data, described rather than coded.
public struct CoverageProfile: Sendable, Codable, Hashable {
    /// Stable source id; also the cache key, so changing it discards that source's cache.
    public var id: String
    public var displayName: String
    public var adapter: CoverageAdapter
    /// The lowest catalog schema version that can read this entry. An app that does not
    /// understand it skips this entry alone rather than rejecting the whole catalog.
    ///
    /// Optional in the JSON and read through `requiredSchema`. A synthesised `Decodable` does
    /// **not** fall back to a property's default value for a missing key — it throws — so a
    /// non-optional with a default here would mean one omitted field silently emptied the
    /// entire catalog and dropped every jurisdiction to the national tier.
    public var minSchema: Int?

    public var service: String?
    /// `flatInventory`: the one layer to read.
    public var layer: Int?
    public var fields: FieldMapping?

    /// `lrsEvents`: the layer that identifies the road, then the tables to join to it.
    public var routeLayer: Int?
    public var routeIDField: String?
    public var routeFields: FieldMapping?
    public var eventLayers: [EventLayerProfile]?

    /// `bespoke`: ids of sources compiled into the app, in pipeline order.
    public var sourceIDs: [String]?

    /// What drive mode should probe here, if this jurisdiction beats TIGER/Line.
    public var centreline: CentrelineProfile?

    /// Whether this jurisdiction has a parcel overlay the map can draw.
    ///
    /// Off unless a profile says otherwise, because the overlay is the one feature that spends
    /// network merely because the map moved. The assessor service behind it is Maricopa's, so
    /// without this gate every pan anywhere in the country would fire requests at Maricopa
    /// County and get nothing back.
    public var hasParcels: Bool?

    /// Said plainly on the card when this profile cannot supply a date, so the app explains a
    /// gap rather than looking broken. Pennsylvania and Louisiana both need one: each
    /// publishes a construction year only for roads the state itself owns.
    public var dateCaveat: String?

    /// Defaults applied on read rather than at decode. See `minSchema`.
    public var requiredSchema: Int { minSchema ?? 1 }
    public var drawsParcels: Bool { hasParcels ?? false }

    public init(id: String, displayName: String, adapter: CoverageAdapter) {
        self.id = id
        self.displayName = displayName
        self.adapter = adapter
    }
}
