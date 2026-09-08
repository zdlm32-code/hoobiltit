import Foundation

/// A dropped pin. The record keys on this, not on a road identifier: no two sources share a
/// segment ID (docs/ENDPOINTS.md §5.4), so the coordinate is the only stable join.
public struct RoadQuery: Sendable, Hashable, Codable {
    public let coordinate: Coordinate
    /// Half-width of the search envelope, in metres. ~150 m catches the road you meant
    /// without dragging in the next block.
    public let searchRadiusMeters: Double

    public init(coordinate: Coordinate, searchRadiusMeters: Double = 150) {
        self.coordinate = coordinate
        self.searchRadiusMeters = searchRadiusMeters
    }

    public init(latitude: Double, longitude: Double, searchRadiusMeters: Double = 150) {
        self.init(coordinate: Coordinate(latitude: latitude, longitude: longitude),
                  searchRadiusMeters: searchRadiusMeters)
    }
}

/// Who is responsible for the road. A *conclusion*, never a column: no county centerline
/// layer carries an owner field (docs/ENDPOINTS.md §5.2).
public enum RoadOwner: Sendable, Hashable, Codable {
    /// Maintained by Maricopa County DOT, and accepted into the county system.
    case county(agency: String)
    /// The county maintains it but has *not* accepted it — 616 of 10,954 segments carry
    /// `CourtesyMaintained = Yes`. Usually a developer-built or private street, so the
    /// recorded plat is the real answer to who built it.
    case countyCourtesy(agency: String)
    /// Inside an incorporated city that is not the county's to maintain.
    case municipality(name: String, fullName: String)
    /// A state route.
    case state(agency: String)
    /// A federal agency — National Park Service, Forest Service, BLM, Army Corps. HPMS
    /// ownership codes 60, 62-70.
    case federal(agency: String)
    /// A tribal road. Separated from `federal` although the Bureau of Indian Affairs
    /// administers many of them, because "who to ask about this road" is a different answer.
    case tribal(agency: String)
    /// A turnpike or toll authority. HPMS 31/32, and Pennsylvania's `JURIS = 2`. Distinct
    /// from `state` because the Turnpike Commission is not the state DOT and does not answer
    /// records requests through it.
    case tollAuthority(agency: String)
    /// A road in private hands and identified as such by the agency, as opposed to merely
    /// absent from a maintained-roads list. HPMS 26.
    case privateOwner
    /// Unincorporated, but not in the county-maintained set — typically a private road, a
    /// tribal or federal road, or a street the county has never accepted. This is an
    /// *inference from absence*; prefer `privateOwner` or `tribal` when a source says so.
    case notPubliclyMaintained
    /// The jurisdiction resolved but no source claims maintenance. Distinct from a failure.
    case undetermined

    /// True when the maintaining agency has not accepted ownership, which changes what the
    /// app should point the user at.
    public var isCourtesyMaintained: Bool {
        if case .countyCourtesy = self { return true }
        return false
    }

    public var displayName: String {
        switch self {
        case .county(let agency): agency
        case .countyCourtesy(let agency): agency
        case .municipality(_, let fullName): fullName
        case .state(let agency): agency
        case .federal(let agency): agency
        case .tribal(let agency): agency
        case .tollAuthority(let agency): agency
        case .privateOwner: "Privately owned"
        case .notPubliclyMaintained: "Not publicly maintained"
        case .undetermined: "Undetermined"
        }
    }
}

/// The pavement build-up MCDOT records for a segment. Condition, not age.
public struct SurfaceDescription: Sendable, Hashable, Codable {
    public let type: String
    public let depthInches: Double?
    public let baseType: String?
    public let baseDepthInches: Double?
    public let laneCount: Int?
    public let widthFeet: Int?
    /// Estimated Overall Condition Index, 0–100. A condition score, *not* a build date.
    public let conditionIndex: Double?
    /// The county's own plain-English rating — "Very Poor" through "Very Good", present on
    /// 10,001 of 10,954 segments. Preferred over the raw index when showing a person.
    public let conditionRating: String?

    public init(type: String, depthInches: Double? = nil, baseType: String? = nil,
                baseDepthInches: Double? = nil, laneCount: Int? = nil,
                widthFeet: Int? = nil, conditionIndex: Double? = nil,
                conditionRating: String? = nil) {
        self.type = type
        self.depthInches = depthInches
        self.baseType = baseType
        self.baseDepthInches = baseDepthInches
        self.laneCount = laneCount
        self.widthFeet = widthFeet
        self.conditionIndex = conditionIndex
        self.conditionRating = conditionRating
    }
}

/// A recorded subdivision plat — the answer for most developer-built residential streets,
/// and a primary path rather than a fallback (docs/ENDPOINTS.md §1.3).
public struct PlatReference: Sendable, Hashable, Codable {
    public let subdivisionName: String
    /// County Recorder book-page, e.g. "185-38".
    public let recorderNumber: String?
    /// Deep link to the recorded plat document.
    public let recorderURL: URL?

    public init(subdivisionName: String, recorderNumber: String? = nil, recorderURL: URL? = nil) {
        self.subdivisionName = subdivisionName
        self.recorderNumber = recorderNumber
        self.recorderURL = recorderURL
    }
}

/// How the responsible agency came to hold the road.
public struct RoadAcquisition: Sendable, Hashable, Codable {
    /// e.g. "Road Easement", "Subdivision", "Warranty Deed", "Final Order of Condemnation".
    public let method: String
    public let widthFeet: Double?
    public let recorderNumber: String?
    public let recorderURL: URL?

    public init(method: String, widthFeet: Double? = nil,
                recorderNumber: String? = nil, recorderURL: URL? = nil) {
        self.method = method
        self.widthFeet = widthFeet
        self.recorderNumber = recorderNumber
        self.recorderURL = recorderURL
    }
}

/// The county road-file declaration — the legal moment a road became a public county road.
public struct RoadDeclaration: Sendable, Hashable, Codable {
    public let roadName: String
    public let roadFileNumber: String?
    public let effectiveDate: Date
    public let documentURL: URL?

    public init(roadName: String, roadFileNumber: String? = nil,
                effectiveDate: Date, documentURL: URL? = nil) {
        self.roadName = roadName
        self.roadFileNumber = roadFileNumber
        self.effectiveDate = effectiveDate
        self.documentURL = documentURL
    }
}

/// What a project was programmed to cost, and out of whose budget.
public struct ProjectFunding: Sendable, Hashable, Codable {
    public let programmedAmount: Double?
    public let fiscalYear: String?
    public let leadAgency: String?
    public let region: String?
    public let projectNumber: String?
    /// When the project actually opened to traffic. Distinct from any construction year —
    /// a project can open years after the roadway under it was last built.
    public let inServiceDate: Date?
    /// The company that built it, where the agency names one.
    ///
    /// Long assumed impossible: fourteen state DOTs were checked and none published a
    /// contractor, which is why the result screen carried a flat statement that no public
    /// source does. TxDOT's Project Tracker does, on work currently under construction, so
    /// the claim was wrong rather than merely unlucky.
    public let contractor: String?

    public init(programmedAmount: Double? = nil, fiscalYear: String? = nil,
                leadAgency: String? = nil, region: String? = nil,
                projectNumber: String? = nil, inServiceDate: Date? = nil,
                contractor: String? = nil) {
        self.programmedAmount = programmedAmount
        self.fiscalYear = fiscalYear
        self.leadAgency = leadAgency
        self.region = region
        self.projectNumber = projectNumber
        self.inServiceDate = inServiceDate
        self.contractor = contractor
    }
}

/// What a job actually did to the road.
///
/// Carried on the work itself rather than left in the source, so that a screen can group and
/// filter a history without knowing one agency's vocabulary. A `String` raw value so it
/// survives the cache's JSON round trip.
public enum RoadWorkKind: String, Sendable, Hashable, Codable {
    /// Built, widened, rebuilt or replaced something.
    case built
    /// Kept an existing road serviceable: seal coat, overlay, bridge maintenance.
    case maintained
    /// Signals, signs, landscaping, sidewalks, studies, right-of-way purchases, and design
    /// work billed before a shovel moves. Real spending on the road, worth listing, but it
    /// never built anything and must never be offered as the answer to who did.
    case ancillary
}

/// One dated job on a stretch of road.
///
/// The first fact in this app that is a *list*. Every other slot on a record holds a single
/// value, which is right when a source publishes one answer — MCDOT names one capital project
/// and one maintenance project, and that is all it has. TxDOT publishes a register going back
/// to 1970, and one pin on I-35 sits on twenty-two jobs: a widening, a resurfacing, a bridge
/// replacement, and work not yet let. Collapsing that to one project would throw away the
/// answer to the question the app exists to ask.
///
/// Deliberately separate from `ProjectReference`, which is a *reference* to a project and
/// carries neither a date nor money. This carries both, because a history is useless without
/// them, and merging the two would drag dates onto a type five other sources populate.
public struct RoadWork: Sendable, Hashable, Codable {
    /// TxDOT's control-section-job number, the id a records request should quote.
    public let projectNumber: String?
    /// The agency's own classification, from a controlled vocabulary — "Widen Freeway",
    /// "Seal Coat". Not free text, so it can be trusted to say what kind of job this was.
    public let title: String
    /// The agency's free-text description, which ranges from clear to pure jargon.
    public let detail: String?
    /// Where the job actually ran, in the agency's words. Worth showing because project
    /// geometry is drawn along a whole control section, so a job may have happened somewhere
    /// else on the stretch the pin is standing on.
    public let location: String?
    /// When the contract was let. Not the day a paving crew arrived, and never presented as
    /// one — but it is the date the agency itself files the job under.
    public let letDate: Date?
    /// The agency's *estimate*, not the awarded amount. The distinction is disclosed wherever
    /// this is shown.
    public let cost: Double?
    public let contractor: String?
    public let kind: RoadWorkKind
    /// Let date in the future. Kept apart everywhere it is displayed, so a road is never
    /// described as built by a job that has not happened.
    public let isPlanned: Bool

    public init(projectNumber: String? = nil, title: String, detail: String? = nil,
                location: String? = nil, letDate: Date? = nil, cost: Double? = nil,
                contractor: String? = nil, kind: RoadWorkKind = .ancillary,
                isPlanned: Bool = false) {
        self.projectNumber = projectNumber
        self.title = title
        self.detail = detail
        self.location = location
        self.letDate = letDate
        self.cost = cost
        self.contractor = contractor
        self.kind = kind
        self.isPlanned = isPlanned
    }
}

/// A structure carrying the road. The only place a build year survives from before the 1960s.
public struct BridgeReference: Sendable, Hashable, Codable {
    public let structureNumber: String?
    public let carries: String?
    public let crosses: String?
    public let yearBuilt: Int?
    /// Distinct from `yearBuilt` on purpose — a 1978 bridge reconstructed in 2011 is both.
    public let yearReconstructed: Int?
    public let ownerDescription: String?
    public let averageDailyTraffic: Int?
    public let trafficCountYear: Int?

    public init(structureNumber: String? = nil, carries: String? = nil, crosses: String? = nil,
                yearBuilt: Int? = nil, yearReconstructed: Int? = nil,
                ownerDescription: String? = nil, averageDailyTraffic: Int? = nil,
                trafficCountYear: Int? = nil) {
        self.structureNumber = structureNumber
        self.carries = carries
        self.crosses = crosses
        self.yearBuilt = yearBuilt
        self.yearReconstructed = yearReconstructed
        self.ownerDescription = ownerDescription
        self.averageDailyTraffic = averageDailyTraffic
        self.trafficCountYear = trafficCountYear
    }
}

/// The land beside the road, from the County Assessor.
///
/// A road pin normally falls in the right-of-way, *between* parcels, so this is usually the
/// land the road runs past rather than land the road is on. That distinction is carried in
/// `containsPin` and must reach the screen: the owner of an adjacent parcel is emphatically
/// not the owner of the road.
public struct ParcelReference: Sendable, Hashable, Codable {
    /// Formatted assessor's parcel number, e.g. "503-88-219".
    public let apn: String
    public let ownerName: String?
    public let address: String?
    public let subdivisionName: String?
    /// County Recorder book-page, the same identifier the plat layer uses — so the two can
    /// corroborate each other.
    public let recorderNumber: String?
    /// Year the *building* went up, not the road. For a developer-built street the two are
    /// usually within a year or two, which is the only reason it is worth showing.
    public let constructionYear: Int?
    /// Range across the parcels fronting this stretch, when several were sampled. More
    /// honest than one neighbour's year, and a better read on when the street went in.
    public let constructionYearRange: ClosedRange<Int>?
    public let landSizeAcres: Double?
    /// False when the parcel merely fronts the road, which is the common case.
    public let containsPin: Bool

    public init(apn: String, ownerName: String? = nil, address: String? = nil,
                subdivisionName: String? = nil, recorderNumber: String? = nil,
                constructionYear: Int? = nil, constructionYearRange: ClosedRange<Int>? = nil,
                landSizeAcres: Double? = nil, containsPin: Bool) {
        self.apn = apn
        self.ownerName = ownerName
        self.address = address
        self.subdivisionName = subdivisionName
        self.recorderNumber = recorderNumber
        self.constructionYear = constructionYear
        self.constructionYearRange = constructionYearRange
        self.landSizeAcres = landSizeAcres
        self.containsPin = containsPin
    }
}

/// A capital or maintenance project touching the segment.
public struct ProjectReference: Sendable, Hashable, Codable {
    public let projectNumber: String?
    public let title: String
    public let detail: String?
    public let phase: String?
    public let projectType: String?
    /// Free-text location as the agency wrote it, e.g. "Deer Valley Rd: 109th Ave to 107th Ave".
    public let location: String?

    public init(projectNumber: String? = nil, title: String, detail: String? = nil,
                phase: String? = nil, projectType: String? = nil, location: String? = nil) {
        self.projectNumber = projectNumber
        self.title = title
        self.detail = detail
        self.phase = phase
        self.projectType = projectType
        self.location = location
    }
}

/// The annexation that brought this ground into a city, with a link to the ordinance PDF.
public struct AnnexationReference: Sendable, Hashable, Codable {
    public let ordinance: String?
    public let ordinanceDate: Date?
    public let ordinanceURL: URL?

    public init(ordinance: String? = nil, ordinanceDate: Date? = nil, ordinanceURL: URL? = nil) {
        self.ordinance = ordinance
        self.ordinanceDate = ordinanceDate
        self.ordinanceURL = ordinanceURL
    }
}

/// What a single source contributed. Sources fill only the fields they actually know, which
/// is what keeps provenance honest — no source gets to imply it authored the whole record.
public struct RoadFragment: Sendable, Codable {
    public var segmentName: Attributed<String>?
    public var owner: Attributed<RoadOwner>?
    public var jurisdiction: Attributed<String>?
    public var annexation: Attributed<AnnexationReference>?
    public var classification: Attributed<String>?
    public var surface: Attributed<SurfaceDescription>?
    public var plat: Attributed<PlatReference>?
    public var crossStreets: Attributed<String>?
    public var maintenanceDistrict: Attributed<String>?
    /// MCDOT's stable per-segment identifier. Kept so several reports on one stretch group
    /// without relying on name matching, which is unreliable everywhere else in this app.
    public var segmentIdentifier: Attributed<String>?
    public var supervisorDistrict: Attributed<Int>?

    /// Deliberately *not* a `constructionYear`. `FromDate` on the maintained-roads layer is
    /// ArcGIS temporal versioning, not a build date (docs/ENDPOINTS.md §5.1). These three are
    /// separate, differently-sourced facts and the UI must never fuse them into one year.
    public var plattedDate: Attributed<Date>?
    /// When the county formally declared this a public road. For county roads this is the
    /// closest thing to a build date that exists, and it reaches back to the 1960s.
    public var declaration: Attributed<RoadDeclaration>?
    public var acquisition: Attributed<RoadAcquisition>?
    public var parcel: Attributed<ParcelReference>?
    public var bridge: Attributed<BridgeReference>?
    public var funding: Attributed<ProjectFunding>?
    public var lastKnownImprovement: Attributed<ProjectReference>?
    /// ADOT's recorded construction date for a state route. The only genuine build date in
    /// any source (docs/ENDPOINTS.md §3); nil everywhere else, which is most places.
    public var yearLastConstruction: Attributed<Date>?
    /// ADOT's recorded date of the last improvement. A separate fact from
    /// `yearLastConstruction` and never to be merged with it into one "built in YYYY".
    public var yearLastImprovement: Attributed<Date>?
    /// What the road is called by the agency that owns it, when that differs from the
    /// local street name — e.g. "I-10" for a segment the county would call a frontage road.
    /// Annual average daily traffic, where the agency publishes it.
    ///
    /// Context rather than an answer to "who built this", but it is the fact that tells a
    /// resident why their street is loud, and PennDOT, Louisiana and the National Highway
    /// System all carry it. Stored as published; nobody recomputes it.
    public var trafficCount: Attributed<Int>?
    public var routeDesignation: Attributed<String>?

    public var project: Attributed<ProjectReference>?
    /// Every dated job the agency records on this stretch, newest first.
    ///
    /// Additive and optional on purpose: `SwiftDataFragmentCache` stores a fragment as a JSON
    /// blob and decodes it with `try?`, so an entry written before this field existed still
    /// decodes, with `works` nil, instead of being thrown away.
    public var works: Attributed<[RoadWork]>?
    public var notes: [SourceNote] = []

    public init() {}
}

/// The merged answer for one pin. Every field is optional: a partial record is the normal
/// outcome, not an error.
public struct RoadRecord: Sendable {
    public let query: RoadQuery

    public var segmentName: Attributed<String>?
    public var owner: Attributed<RoadOwner>?
    public var jurisdiction: Attributed<String>?
    public var annexation: Attributed<AnnexationReference>?
    public var classification: Attributed<String>?
    public var surface: Attributed<SurfaceDescription>?
    public var plat: Attributed<PlatReference>?
    public var crossStreets: Attributed<String>?
    public var maintenanceDistrict: Attributed<String>?
    /// MCDOT's stable per-segment identifier. Kept so several reports on one stretch group
    /// without relying on name matching, which is unreliable everywhere else in this app.
    public var segmentIdentifier: Attributed<String>?
    public var supervisorDistrict: Attributed<Int>?
    public var plattedDate: Attributed<Date>?
    public var declaration: Attributed<RoadDeclaration>?
    public var acquisition: Attributed<RoadAcquisition>?
    public var parcel: Attributed<ParcelReference>?
    public var bridge: Attributed<BridgeReference>?
    public var funding: Attributed<ProjectFunding>?
    public var lastKnownImprovement: Attributed<ProjectReference>?
    public var yearLastConstruction: Attributed<Date>?
    public var yearLastImprovement: Attributed<Date>?
    /// Annual average daily traffic, where the agency publishes it.
    ///
    /// Context rather than an answer to "who built this", but it is the fact that tells a
    /// resident why their street is loud, and PennDOT, Louisiana and the National Highway
    /// System all carry it. Stored as published; nobody recomputes it.
    public var trafficCount: Attributed<Int>?
    public var routeDesignation: Attributed<String>?
    public var project: Attributed<ProjectReference>?
    /// Every dated job the agency records on this stretch, newest first. See `RoadWork`.
    public var works: Attributed<[RoadWork]>?

    /// One entry per source consulted, including the ones that found nothing or failed.
    public var notes: [SourceNote] = []

    /// What this build could bring to bear here. Set by the pipeline factory once, after
    /// resolution; deliberately absent from `RoadFragment` so `merge` can never touch it.
    public var coverage: Coverage?

    public init(query: RoadQuery) {
        self.query = query
    }

    /// True when no source identified a road. The UI shows the public-records and plat
    /// fallbacks from here.
    public var isEmpty: Bool {
        segmentName == nil && owner == nil && jurisdiction == nil && plat == nil && project == nil
    }

    /// Sources that errored, as opposed to sources that legitimately had nothing.
    public var failures: [SourceNote] {
        notes.filter { $0.outcome == .failed }
    }

    /// First writer wins: sources run in priority order, so an earlier source's value is
    /// the more authoritative one and is never overwritten by a later source.
    public mutating func merge(_ fragment: RoadFragment) {
        fill(&segmentName, fragment.segmentName)
        fill(&owner, fragment.owner)
        fill(&jurisdiction, fragment.jurisdiction)
        fill(&annexation, fragment.annexation)
        fill(&classification, fragment.classification)
        fill(&surface, fragment.surface)
        fill(&plat, fragment.plat)
        fill(&crossStreets, fragment.crossStreets)
        fill(&maintenanceDistrict, fragment.maintenanceDistrict)
        fill(&segmentIdentifier, fragment.segmentIdentifier)
        fill(&supervisorDistrict, fragment.supervisorDistrict)
        fill(&plattedDate, fragment.plattedDate)
        fill(&declaration, fragment.declaration)
        fill(&parcel, fragment.parcel)
        fill(&acquisition, fragment.acquisition)
        fill(&bridge, fragment.bridge)
        fill(&funding, fragment.funding)
        fill(&lastKnownImprovement, fragment.lastKnownImprovement)
        fill(&yearLastConstruction, fragment.yearLastConstruction)
        fill(&yearLastImprovement, fragment.yearLastImprovement)
        fill(&trafficCount, fragment.trafficCount)
        fill(&routeDesignation, fragment.routeDesignation)
        fill(&project, fragment.project)
        fill(&works, fragment.works)
        notes.append(contentsOf: fragment.notes)
    }

    private func fill<T>(_ slot: inout Attributed<T>?, _ incoming: Attributed<T>?) {
        if slot == nil, let incoming { slot = incoming }
    }
}
