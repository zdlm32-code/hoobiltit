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

/// How a feature is chosen from what an envelope returns.
///
/// Polyline layers want the nearest line: a centreline is the road, and distance to it is
/// meaningful. Polygon layers want containment, and the difference is not cosmetic. A city
/// capital-project area can be half a mile across, so the distance from a pin *inside* it to
/// its boundary routinely exceeds the on-road gate — nearest-line would reject the very
/// project the pin is standing in.
public enum MatchMode: String, Sendable, Codable {
    case nearestLine
    case containsPoint
}

/// Which shipped table decodes a coded field. `nil` means the value is already prose.
public enum CodeTableReference: String, Sendable, Codable {
    case hpmsOwnership
    case fhwaFunctionalClass
    case penndotJurisdiction
    case txdotAdmin
    /// The field names the owner outright rather than coding it. See `CodeTables.owner(named:)`.
    case namedAgency
    /// Plain-English pavement treatments, as Dallas and Denver both publish them. Classifies
    /// work, not ownership.
    case pavementTreatment
    /// City of Dallas `maint_resp`, which names a level of government rather than a body.
    case dallasMaintenance
    /// ADOT's `Ownership_Value`, which names the body and carries its HPMS code.
    case adotOwnership
    /// NCDOT `ImprvType`, the one vocabulary an agency actually documents.
    case ncdotImprovement
    /// ODOT `JURISDICTI`, a single letter per level of government.
    case ohioJurisdiction
    /// MassDOT `JURISDICTN`, eighteen documented values.
    case massdotJurisdiction
    /// A field that names a *level* of government in plain English rather than a body or a
    /// code — Montana's `Ownership` and New Hampshire's `LC_LEGEND`. See
    /// `CodeTables.owner(level:)`.
    case authorityLevel
    /// SDDOT `LOCAL_SYSTEM`, which distinguishes a county secondary road, a township road and
    /// a road district from one another.
    case sdLocalSystem
    /// SDDOT `DATA_CLASS`, which is the only field that identifies the state trunk system.
    case sdDataClass
}

/// How a year is stored. Verified encodings: PennDOT writes a plain `1916`, ADOT a compact
/// string `"20031110"`, Maricopa Esri epoch milliseconds.
public enum YearEncoding: String, Sendable, Codable {
    case yearNumber
    case compactString
    case epochMilliseconds
}

/// One way of reading ownership off a feature, tried in order.
///
/// A single field is the normal case, but not the only one. NCDOT publishes the level and the
/// body in `OwnerType` and `OwnerName` — `4` and `Charlotte` — and says NCDOT itself maintains a
/// road through a *third* field, `RouteMaintCode = System`, on 607,062 segments that name no
/// owner at all. One field cannot express that, and inferring "state" from a blank would be a
/// guess where the agency has published an answer.
public struct OwnershipRule: Sendable, Codable, Hashable {
    public var field: String
    public var table: CodeTableReference?
    /// Names the body to pair with the kind the code gives, so `4` + `Charlotte` reads as
    /// Charlotte rather than "city or municipal highway agency".
    public var nameField: String?
    /// Rewrites a value before it is classified. An empty string declines.
    public var names: [String: String]?

    public init(field: String, table: CodeTableReference? = nil,
                nameField: String? = nil, names: [String: String]? = nil) {
        self.field = field
        self.table = table
        self.nameField = nameField
        self.names = names
    }
}

/// The field names one layer uses for the facts the app reports.
///
/// Every slot is optional because no service publishes all of them, and a profile that names
/// a field the layer does not have simply contributes nothing for it.
public struct FieldMapping: Sendable, Codable, Hashable {
    /// Ordered; the first that yields a value wins. King County and Cook County split names
    /// into left- and right-of-centreline variants, so more than one candidate is normal.
    public var name: [String]?
    /// Joined with a space to form the name, for a layer that stores it in pieces. Ohio holds
    /// `S` + `MAIN` + `ST` in three fields; taking the first that yields gives "MAIN".
    /// Preferred over `name` when both are set.
    public var nameParts: [String]?
    /// Joined with a space to form a route designation, e.g. PennDOT's
    /// `TRAF_RT_NO_PREFIX` + `TRAF_RT_NO`.
    public var routeDesignation: [String]?
    public var ownership: String?
    public var ownershipTable: CodeTableReference?
    /// Rewrites an ownership value before it is classified, for a layer that publishes a bare
    /// level rather than a body: Pharr writes `CITY`, which is true of every city in Texas.
    /// Mapping to an empty string makes the source decline, which is how a city layer says a
    /// street is outside its own jurisdiction.
    public var ownerNames: [String: String]?
    /// Tried in order, first that yields an owner wins. Takes precedence over `ownership`.
    public var ownershipRules: [OwnershipRule]?
    public var yearBuilt: String?
    public var yearImproved: String?
    public var yearEncoding: YearEncoding?
    public var functionalClass: String?
    public var functionalClassTable: CodeTableReference?
    public var aadt: String?
    public var crossStreetFrom: String?
    public var crossStreetTo: String?
    /// A single dated job recorded against the segment, as city pavement layers publish it —
    /// a year plus what was done. Emitted as a one-entry `works` list so it reaches the same
    /// history UI a state's whole register does.
    public var workYear: String?
    public var workType: String?
    public var workTypeTable: CodeTableReference?
    /// Expands an abbreviation the layer stores. Denver writes `HIPR`, which is hot in-place
    /// recycling and reads as noise on a card.
    public var workTypeNames: [String: String]?
    /// The agency's own description of the extent, e.g. Dallas's "18400-18500 TIMBER OAKS DR".
    public var workLocation: String?
    /// What the work was, when the layer is a project register rather than a pavement survey
    /// and every row is by definition construction.
    public var workKindDefault: RoadWorkKind?
    public var workDetail: String?
    public var workCost: String?
    public var workContractor: String?
    /// When a city took the land in. Not a construction date and never shown as one — it
    /// appears in the paper trail beside the plat and the right-of-way — but where a city
    /// publishes nothing else it is the one dated fact bounding when the streets went in.
    public var annexationOrdinance: String?
    public var annexationDate: String?
    /// Pavement, as a city layer publishes it. Assembled into one `SurfaceDescription`, which
    /// already carries a type, a width, a plain-English rating and a 0-100 index because
    /// Maricopa publishes all four.
    public var surface: String?
    /// Rewrites a surface value the layer abbreviates. NCDOT stores `Bitum` and documents it
    /// as `Bituminous`; the abbreviation reads as a truncation on a card.
    public var surfaceNames: [String: String]?
    /// The agency's own plain-English rating — Dallas's `blend_cond` is A through F.
    public var condition: String?
    /// A 0-100 condition index, e.g. Dallas's blended PCI or San Antonio's PCI.
    public var conditionIndex: String?
    public var widthFeet: String?
    /// The NBI structure number, where a roadway layer carries one. Lets the bridge source
    /// join exactly instead of guessing from distance and name.
    public var structureNumber: String?

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

/// A second layer joined on an exact key, to borrow the fields the main layer lacks.
///
/// Written for Texas and deliberately not Texas-specific. TxDOT publishes ownership, class and
/// traffic on `TxDOT_Roadway_Inventory` — 133 fields, **not one of them a street name** — and
/// the names on a separate `TxDOT_Roadways` layer, with `GID` common to both.
///
/// Without the join the app would name a Texas road from the national tier and own it from the
/// state tier, which is worse than it sounds: the two would routinely describe *different
/// roads*. A mid-block pin on San Jacinto Blvd in Austin has Loop 343 only 54.7 m away, inside
/// the proximity gate, so TIGER would say "San Jacinto Blvd" while TxDOT said "state highway
/// agency" — a card that is coherent, confident and wrong. Joining makes name and owner come
/// from one segment or from neither.
public struct NameJoinProfile: Sendable, Codable, Hashable {
    /// Defaults to the profile's own service when omitted, which is the usual case.
    public var service: String?
    public var layer: Int
    /// The key on the main layer, read off the segment the pin matched.
    public var localKeyField: String
    /// The key on the joined layer. Usually the same name; separate because it need not be.
    public var foreignKeyField: String
    /// Restricts the join to rows where a second field holds a given value, for a layer whose
    /// fields mean different things on different rows.
    ///
    /// TxDOT's `MAP_LBL` is the case in point: it is a *map shield label*, so on-system rows
    /// carry `35`, `175`, `10C` — never a street name — while off-system rows carry
    /// `SAN JACINTO BLVD`. Joining without this named Interstate 35 "35".
    public var filterField: String?
    public var filterValue: String?
    /// What the joined layer contributes. Applied *before* the main layer, so a field present
    /// on both comes from here.
    public var fields: FieldMapping

    public init(service: String? = nil, layer: Int, localKeyField: String,
                foreignKeyField: String, filterField: String? = nil,
                filterValue: String? = nil, fields: FieldMapping) {
        self.service = service
        self.layer = layer
        self.localKeyField = localKeyField
        self.foreignKeyField = foreignKeyField
        self.filterField = filterField
        self.filterValue = filterValue
        self.fields = fields
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
    /// How the pin picks a feature. Defaults to nearest line; see `MatchMode`.
    public var matching: MatchMode?
    /// Fields to request, when asking for everything is wasteful. Edinburg's capital-project
    /// rows carry about 150 fields including thirty paragraphs of status history, which is
    /// 200 KB for seven features on what may be a phone in a car. Omit to request `*`.
    public var outFields: [String]?
    /// `flatInventory`: an optional second layer joined on an exact key, for a service that
    /// splits attributes from names.
    public var nameJoin: NameJoinProfile?

    /// `lrsEvents`: the layer that identifies the road, then the tables to join to it.
    public var routeLayer: Int?
    public var routeIDField: String?
    public var routeFields: FieldMapping?
    public var eventLayers: [EventLayerProfile]?

    /// `bespoke`: ids of sources compiled into the app, in pipeline order.
    public var sourceIDs: [String]?
    /// Runs `sourceIDs` *before* a generic adapter's own source rather than after.
    ///
    /// Arizona needs it. Its hand-written ADOT sources know things the statewide HPMS tables
    /// do not — they exclude the non-ADOT route namespace, disambiguate two coincident routes
    /// 2 m apart, and recover a project number from free text — so on a state route they must
    /// claim the answer first. HPMS then fills the roads they never covered, which is most of
    /// the state.
    public var compiledFirst: Bool?

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
    public var matchMode: MatchMode { matching ?? .nearestLine }
    public var runsCompiledFirst: Bool { compiledFirst ?? false }
    public var drawsParcels: Bool { hasParcels ?? false }

    public init(id: String, displayName: String, adapter: CoverageAdapter) {
        self.id = id
        self.displayName = displayName
        self.adapter = adapter
    }
}
