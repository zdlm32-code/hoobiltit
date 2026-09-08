import Foundation
import RoadCore

/// Reads TxDOT's construction register — the answer to "who built this road?" in Texas.
///
/// `TxDOT_DCIS_All_Projects` is the Design and Construction Information System published as a
/// polyline layer: **73,306 projects let between 1970 and 2050**, with a construction cost on
/// 99.7% of them and a controlled-vocabulary `PROJ_CLASS` on 99%. It is by a wide margin the
/// richest source in this app, and it is the reason the flat statement that "no public source
/// publishes the contractor or the award amount" had to be qualified: `ProjectTracker_AGO`
/// joins to it on the control-section-job number and names the construction company.
///
/// What it does **not** cover is everything off the state system. A pin on a residential street
/// or a county road gets nothing here, which is correct rather than broken, and the profile's
/// `dateCaveat` says so.
public struct TxDOTProjectSource: RoadSource {
    public let id = "tx.dcis"
    public let displayName = "TxDOT Design and Construction Information System"

    static let projects = ArcGISLayer(
        "https://services.arcgis.com/KTcxiTD9dsQw4r7Z/arcgis/rest/services/TxDOT_DCIS_All_Projects/FeatureServer",
        layer: 0)!
    static let tracker = ArcGISLayer(
        "https://services.arcgis.com/KTcxiTD9dsQw4r7Z/arcgis/rest/services/ProjectTracker_AGO/FeatureServer",
        layer: 1)!
    /// The spending ledger, one row per account line.
    static let spending = ArcGISLayer(
        "https://services.arcgis.com/KTcxiTD9dsQw4r7Z/arcgis/rest/services/ProjectTracker_AGO/FeatureServer",
        layer: 2)!

    /// Only what is used. The layer publishes 42 fields and the geometry is corridor-length, so
    /// asking for everything triples the payload on a connection that may be a phone in a car.
    static let fields = "CONTROL_SECT_JOB,HIGHWAY_NUMBER,PROJ_CLASS,TYPE_OF_WORK,"
        + "PROJ_ESTMTD_LET_D,COMMISSION_AWARD_OF_CONTRACT,EST_CONSTRUCTION_COST,"
        + "LIMITS_FROM,LIMITS_TO,PROJ_STAT"

    /// How close a project line must be before it describes the road under the pin.
    ///
    /// Tighter than `RoadProximity.onRoadMeters`, and measured rather than guessed. DCIS
    /// geometry is derived from the same linear reference as the roadway, so a project sits
    /// almost on the centreline: the 22 genuine projects at the I-35 test pin measure 6.8 m to
    /// 10.5 m away. The failure this prevents is the one that has already bitten this app
    /// twice — at the mid-block San Jacinto Blvd pin, DCIS returns exactly one project, and it
    /// is **State Loop 343's, 55.0 m away**, comfortably inside the 60 m general gate. A city
    /// street would otherwise be credited with a state highway's construction history.
    static let onProjectMeters: Double = 25

    private let client: ArcGISClient
    private let now: @Sendable () -> Date

    public init(client: ArcGISClient = ArcGISClient(),
                now: @escaping @Sendable () -> Date = Date.init) {
        self.client = client
        self.now = now
    }

    public func fetch(_ query: RoadQuery, resolved: RoadRecord) async throws -> RoadFragment {
        var fragment = RoadFragment()
        let envelope = Geo.envelope(around: query.coordinate, radiusMeters: query.searchRadiusMeters)
        let (features, url) = try await client.query(layer: Self.projects, envelope: envelope,
                                                     outFields: Self.fields, returnGeometry: true)

        let ranked = features.features
            .compactMap { feature in feature.distance(from: query.coordinate).map { (feature, $0) } }
            .sorted { $0.1 < $1.1 }

        guard let (nearest, metres) = ranked.first else {
            fragment.notes = [note(.foundNothing, "TxDOT records no project on this stretch.")]
            return fragment
        }
        guard metres <= Self.onProjectMeters else {
            fragment.notes = [note(.foundNothing, "Nearest TxDOT project is \(Int(metres)) m away "
                                   + "\u{2014} on another road, not this one.")]
            return fragment
        }

        // One pin, one corridor. An interchange puts two highways' registers inside the same
        // envelope, and blending them would invent a history for both.
        let highway = nearest["HIGHWAY_NUMBER"].text
        let onThisRoad = ranked.filter { feature, _ in
            feature["HIGHWAY_NUMBER"].text == highway
        }.map(\.0)

        let provenance = provenance(url: url, fetchedAt: now())
        // A control section is drawn as several features, so one project appears more than
        // once in an envelope. Listing it twice reads as two separate jobs in the same year.
        var seen = Set<String>()
        let works = onThisRoad.compactMap { Self.work(from: $0, now: now()) }
            .sorted { ($0.letDate ?? .distantPast) > ($1.letDate ?? .distantPast) }
            .filter { work in
                guard let number = work.projectNumber else { return true }
                return seen.insert(number).inserted
            }
        guard !works.isEmpty else {
            fragment.notes = [note(.foundNothing, "TxDOT records no project on this stretch.")]
            return fragment
        }
        fragment.works = Attributed(works, provenance: provenance, confidence: .spatial)

        // Only work already let may answer "who built this". A project let in 2037 has not
        // built anything yet, however large it is.
        let done = zip(onThisRoad, onThisRoad.map { Self.work(from: $0, now: now()) })
            .compactMap { feature, work in work.map { (feature, $0) } }
            .filter { !$0.1.isPlanned }

        let built = done
            .filter { $0.1.kind == .built }
            .max { lhs, rhs in
                (lhs.1.cost ?? 0, lhs.1.letDate ?? .distantPast)
                    < (rhs.1.cost ?? 0, rhs.1.letDate ?? .distantPast)
            }
        let latest = done.max { ($0.1.letDate ?? .distantPast) < ($1.1.letDate ?? .distantPast) }

        if let built {
            fragment.project = Attributed(Self.reference(built.1, kind: "Construction"),
                                          provenance: provenance, confidence: .spatial)
            var contractor = built.1.contractor
            var spent: Double?
            if let csj = built.1.projectNumber {
                if contractor == nil { contractor = await self.contractor(forCSJ: csj) }
                spent = await self.constructionSpend(forCSJ: csj)
            }
            fragment.funding = Attributed(
                ProjectFunding(programmedAmount: built.1.cost,
                               fiscalYear: built.1.letDate.map { "let \(CalendarDate.year($0))" },
                               leadAgency: "Texas Department of Transportation",
                               projectNumber: built.1.projectNumber,
                               contractor: contractor,
                               actualSpend: spent),
                provenance: provenance, confidence: .spatial)
        }
        // Omitted when it *is* the build project: "built under X, most recent work X" reads as
        // a bug rather than as one job doing both.
        if let latest, latest.1.projectNumber != built?.1.projectNumber {
            fragment.lastKnownImprovement = Attributed(
                Self.reference(latest.1, kind: "Most recent work"),
                provenance: provenance, confidence: .spatial)
        }

        fragment.notes = [note(.contributed, Self.summary(works: works, built: built?.1))]
        return fragment
    }

    /// The construction company, for work currently under way.
    ///
    /// Project Tracker holds only live and near-term jobs — 7,542 of them carry a company —
    /// so a historical project simply has no contractor to find. Failure is silent: losing the
    /// company name is not a reason to discard the cost and dates already in hand.
    private func contractor(forCSJ csj: String) async -> String? {
        guard let (features, _) = try? await client.query(
            layer: Self.tracker, field: "CSJ_NBR", equals: csj,
            outFields: "CSJ_NBR,CNSTR_CMPNY_NM,CNSTR_WKBG_DT,CNSTR_PCT_COMPLETE")
        else { return nil }
        return features.features.first?["CNSTR_CMPNY_NM"].text
    }

    /// What has actually been paid out on construction for one project.
    ///
    /// The ledger splits a project across categories — `PE` is design, `ROW` is land — and
    /// only `CNST` is the road being built, so the rows are filtered rather than summed
    /// wholesale. A project with no ledger rows is the normal case for older work.
    private func constructionSpend(forCSJ csj: String) async -> Double? {
        guard let (features, _) = try? await client.query(
            layer: Self.spending, field: "CSJ_NBR", equals: csj,
            outFields: "CSJ_NBR,SPENDING_CAT,SPENT_AMT")
        else { return nil }
        let construction = features.features
            .filter { $0["SPENDING_CAT"].text == "CNST" }
            .compactMap { $0["SPENT_AMT"].double }
        guard !construction.isEmpty else { return nil }
        let total = construction.reduce(0, +)
        return total > 0 ? total : nil
    }

    static func work(from feature: ArcGISFeature, now: Date) -> RoadWork? {
        // The class is the headline, so a project without one cannot be described honestly.
        guard let projectClass = feature["PROJ_CLASS"].text, projectClass != "Default",
              projectClass != "None"
        else { return nil }
        let let_ = feature["PROJ_ESTMTD_LET_D"].epochMillisecondsDate
        let detail = feature["TYPE_OF_WORK"].text
        return RoadWork(
            projectNumber: feature["CONTROL_SECT_JOB"].text,
            title: projectClass,
            // "Legacy" is TxDOT's placeholder on 1,500 old rows and says nothing.
            detail: detail == "Legacy" ? nil : detail,
            location: limits(feature),
            letDate: let_,
            cost: feature["EST_CONSTRUCTION_COST"].double.flatMap { Self.realCost($0) },
            kind: CodeTables.workKind(txdot: projectClass),
            isPlanned: let_.map { $0 > now } ?? false)
    }

    /// Placeholder amounts, discarded rather than shown.
    ///
    /// 429 projects carry exactly `1`, and another 25 sit below a hundred dollars — `0.01`,
    /// `0.66`, `2`, `42`. No road project costs a dollar, and "Widen Non-Freeway $1" reads as
    /// a bug in the app rather than a gap in the register. 454 of 73,085, so the floor costs
    /// nothing real.
    static let costFloor: Double = 100

    static func realCost(_ amount: Double) -> Double? {
        amount >= costFloor ? amount : nil
    }

    /// "0.1 MI SOUTH OF RM 2243 to 0.21 MI NORTH OF RM 2243", as the agency wrote it.
    ///
    /// Worth carrying because project geometry spans a whole control section: a bridge job
    /// 0.001 miles long is drawn across 6.4 km of highway, so the limits are what tell a
    /// reader whether the job happened where they are standing.
    static func limits(_ feature: ArcGISFeature) -> String? {
        let from = feature["LIMITS_FROM"].text
        let to = feature["LIMITS_TO"].text
        switch (from, to) {
        // A lone "." is TxDOT's way of writing "at a point", not a second limit.
        case let (from?, to?) where to != ".": return "\(from) to \(to)"
        case let (from?, _): return from
        default: return to
        }
    }

    static func reference(_ work: RoadWork, kind: String) -> ProjectReference {
        ProjectReference(projectNumber: work.projectNumber, title: work.title,
                         detail: work.detail, phase: nil, projectType: kind,
                         location: work.location)
    }

    static func summary(works: [RoadWork], built: RoadWork?) -> String {
        let planned = works.filter(\.isPlanned).count
        var text = "\(works.count) TxDOT project\(works.count == 1 ? "" : "s") on this stretch"
        if let built, let year = built.letDate.map({ CalendarDate.year($0) }) {
            text += "; \(built.title.lowercased()) let \(year)"
        }
        if planned > 0 { text += "; \(planned) not yet let" }
        return text + "."
    }
}
