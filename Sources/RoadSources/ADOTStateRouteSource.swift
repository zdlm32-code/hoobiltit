import Foundation
import RoadCore

/// ADOT's ATIS linear referencing system, published whole as a feature service.
///
/// It is the only source anywhere that carries a genuine construction date
/// (docs/ENDPOINTS.md §3), so it runs **before** the county source: a pin on I-10 sits inside
/// Goodyear's municipal boundary, and county-only resolution would call the interstate a city
/// road. ADOT's ownership verdict has to claim the field first.
///
/// The source stays silent unless the nearest route is genuinely ADOT's. ATIS mirrors local
/// streets too — `"07  BULLARD             AVE     "`, `RouteType: "L - Local (Non-ADOT)"` —
/// and claiming those would let a nearby freeway hijack a residential pin.
public struct ADOTStateRouteSource: RoadSource {
    public let id = "adot.atis"
    public let displayName = "ADOT ATIS"

    static let service = "https://services1.arcgis.com/XAiBIVuto7zeZj1B/arcgis/rest/services/ATIS_prod_gdb/FeatureServer"

    private enum Layer {
        static let routes = 1              // LRSN_ATIS_Routes
        static let ownerMaintenance = 29   // LRSE_OwnerMaint
        static let yearLastConstruction = 3
        static let yearLastImprovement = 2
        static let projectSegment = 24     // LRSE_ProjectSegment — carries TRACS
    }

    /// ATIS stores every physical road twice — once under the ADOT namespace
    /// (`"  I 010"`) and once as a local mirror with *identical* geometry
    /// (`"07  I 10"`). Measured at the Exit 127 interchange the pairs sit at 1.7/1.7 m,
    /// 24.1/24.1 m, 31.3/31.3 m from the pin, while the next distinct road is 22 m further
    /// out. A tolerance well under that gap separates "the same road, other namespace" from
    /// "a different road nearby".
    static let coincidenceToleranceMeters = 2.0

    private let client: ArcGISClient
    private let now: @Sendable () -> Date

    public init(client: ArcGISClient = ArcGISClient(), now: @escaping @Sendable () -> Date = Date.init) {
        self.client = client
        self.now = now
    }

    public func fetch(_ query: RoadQuery, resolved: RoadRecord) async throws -> RoadFragment {
        var fragment = RoadFragment()
        let point = query.coordinate
        let corridor = Geo.envelope(around: point, radiusMeters: query.searchRadiusMeters)

        let routes = try await result(layer: Layer.routes, envelope: corridor)
        guard let route = primaryRoute(in: routes.features, near: point),
              let routeID = route["RouteId"].rawString
        else {
            fragment.notes = [note(.foundNothing,
                                   "No ADOT route at this location; leaving it to the local agency.")]
            return fragment
        }

        applyRoute(route, from: routes, to: &fragment)
        try await applyOwnership(routeID: routeID, envelope: corridor, near: point, to: &fragment)
        let commentTracs = try await applyConstructionDates(routeID: routeID, envelope: corridor,
                                                            near: point, to: &fragment)
        try await applyProject(routeID: routeID, envelope: corridor, builtUnder: commentTracs,
                               to: &fragment)

        fragment.notes = [note(.contributed,
                               "\(route["RouteNameShort"].text.map(Self.displayRouteName) ?? "State route") "
                               + "(\(route["RouteSubtype"].text.map(Self.displayRouteType) ?? "ADOT route")).")]
        return fragment
    }

    // MARK: - Fields

    private func applyRoute(_ route: ArcGISFeature, from result: LayerResult, to fragment: inout RoadFragment) {
        let prov = provenance(url: result.url, fetchedAt: result.fetchedAt)
        if let name = route["RouteNameShort"].text.map(Self.displayRouteName) {
            fragment.routeDesignation = Attributed(name, provenance: prov, confidence: .direct)
            fragment.segmentName = Attributed(name, provenance: prov, confidence: .direct)
        }
        // "70-Interstate", "74-Ramps" — the ordinal is an internal sort key.
        if let subtype = route["RouteSubtype"].text {
            fragment.classification = Attributed(Self.displayRouteType(subtype),
                                                 provenance: prov, confidence: .direct)
        }
    }

    private func applyOwnership(routeID: String, envelope: Envelope, near point: Coordinate,
                                to fragment: inout RoadFragment) async throws {
        let result = try await result(layer: Layer.ownerMaintenance, envelope: envelope)
        guard let feature = LRSJoin.best(in: result.features, routeID: routeID, near: point)
        else { return }
        // "DOT" is ADOT; a city code such as "GDY" means ATIS is tracking someone else's road,
        // and the county source is the better authority for that.
        guard feature["Owner"].text == "DOT" else { return }

        let agency = feature["Ownership"].text.map(Self.stripAgencyCode) ?? "Arizona Department of Transportation"
        fragment.owner = Attributed(.state(agency: agency),
                                    provenance: provenance(url: result.url, fetchedAt: result.fetchedAt),
                                    confidence: .direct)
        if let county = feature["County"].text.map(Self.stripAgencyCode) {
            fragment.jurisdiction = Attributed("\(county) County, Arizona",
                                               provenance: provenance(url: result.url, fetchedAt: result.fetchedAt),
                                               confidence: .direct)
        }
    }

    /// TRACS recovered from a year layer's free-text comment, used only when the typed
    /// project layer has nothing for this route.
    private struct CommentTracs { let number: String; let url: URL; let fetchedAt: Date }

    private func applyConstructionDates(routeID: String, envelope: Envelope, near point: Coordinate,
                                        to fragment: inout RoadFragment) async throws -> CommentTracs? {
        var recovered: CommentTracs?
        let construction = try await result(layer: Layer.yearLastConstruction, envelope: envelope)
        if let feature = LRSJoin.best(in: construction.features, routeID: routeID, near: point) {
            if let date = feature["YearLastConstruction"].compactStringDate {
                fragment.yearLastConstruction = Attributed(
                    date,
                    provenance: provenance(url: construction.url, fetchedAt: construction.fetchedAt),
                    confidence: .direct
                )
            }
            if let comment = feature["YearBuiltComment"].text, let tracs = Self.tracsNumber(in: comment) {
                recovered = CommentTracs(number: tracs, url: construction.url,
                                         fetchedAt: construction.fetchedAt)
            }
        }

        let improvement = try await result(layer: Layer.yearLastImprovement, envelope: envelope)
        if let feature = LRSJoin.best(in: improvement.features, routeID: routeID, near: point),
           let date = feature["YearLastImprovement"].compactStringDate {
            fragment.yearLastImprovement = Attributed(
                date,
                provenance: provenance(url: improvement.url, fetchedAt: improvement.fetchedAt),
                confidence: .direct
            )
        }
        return recovered
    }

    /// Two different project facts, kept apart because conflating them misleads.
    ///
    /// `project` answers the app's actual question — which project ADOT credits with the
    /// last construction — and so is the TRACS cited alongside the construction date the UI
    /// is showing. `lastKnownImprovement` is the most recent project of any kind on the
    /// route, which is usually a later resurfacing and would look like a contradiction if
    /// reported as the builder.
    private func applyProject(routeID: String, envelope: Envelope, builtUnder: CommentTracs?,
                              to fragment: inout RoadFragment) async throws {
        let result = try await result(layer: Layer.projectSegment, envelope: envelope)
        let candidates = result.features.matching(routeID: routeID)
        let mostRecent = candidates.max { lhs, rhs in
            (lhs["InServiceDate"].compactStringDate ?? .distantPast)
                < (rhs["InServiceDate"].compactStringDate ?? .distantPast)
        }

        if let builtUnder {
            // The typed project layer may also carry this TRACS; if it does, the claim is a
            // matched record rather than a string scraped out of a note.
            let typed = candidates.first { $0["TracsNumber"].text == builtUnder.number }
            fragment.project = Attributed(
                ProjectReference(
                    projectNumber: builtUnder.number,
                    title: "ADOT project \(builtUnder.number)",
                    detail: "Credited by ADOT with the last construction on this route.",
                    projectType: "State highway construction",
                    location: fragment.routeDesignation?.value
                ),
                provenance: provenance(url: typed == nil ? builtUnder.url : result.url,
                                       fetchedAt: typed == nil ? builtUnder.fetchedAt : result.fetchedAt),
                confidence: typed == nil ? .nameMatch : .direct
            )
        }

        if let mostRecent, let tracs = mostRecent["TracsNumber"].text,
           tracs != fragment.project?.value.projectNumber {
            let inService = mostRecent["InServiceYear"].text
            fragment.lastKnownImprovement = Attributed(
                ProjectReference(
                    projectNumber: tracs,
                    title: "ADOT project \(tracs)",
                    detail: inService.map { "Most recent project on this route; in service \($0)." }
                        ?? "Most recent project on this route.",
                    projectType: "State highway work",
                    location: fragment.routeDesignation?.value
                ),
                provenance: provenance(url: result.url, fetchedAt: result.fetchedAt),
                confidence: .direct
            )
        } else if fragment.project == nil, let mostRecent,
                  let tracs = mostRecent["TracsNumber"].text {
            fragment.project = Attributed(
                ProjectReference(
                    projectNumber: tracs,
                    title: "ADOT project \(tracs)",
                    detail: mostRecent["InServiceYear"].text.map { "In service \($0)." },
                    projectType: "State highway work",
                    location: fragment.routeDesignation?.value
                ),
                provenance: provenance(url: result.url, fetchedAt: result.fetchedAt),
                confidence: .direct
            )
        }
    }

    // MARK: - Value cleaning

    /// ADOT prefixes coded values with the code itself: `"DOT-Arizona Department of
    /// Transportation"`, `"013-Maricopa"`.
    static func stripAgencyCode(_ value: String) -> String {
        guard let dash = value.firstIndex(of: "-") else { return value }
        let name = value[value.index(after: dash)...].trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? value : name
    }

    /// `"70-Interstate"` -> `"Interstate"`, `"I - Interstate"` -> `"Interstate"`.
    static func stripOrdinal(_ value: String) -> String {
        let stripped = value.replacing(/^[A-Z0-9]{1,3}\s*-\s*/, with: "")
        return stripped.isEmpty ? value : String(stripped)
    }

    /// ADOT's carriageway bookkeeping, removed before anything reaches a driver.
    ///
    /// ATIS names each direction of a divided highway separately, because mileposts run one way
    /// and it needs to say which. So the southbound Loop 101 is published as
    /// `"SR-101 nonCard"` — non-Cardinal, the decreasing-milepost direction — and its subtype
    /// as `"91-State Rte non-Card"`. Picking that feature is *correct* when you are on that
    /// carriageway; showing its internal label is not. The road is called SR-101 whichever way
    /// you are pointed.
    ///
    /// `Front` is expanded rather than dropped: a frontage road genuinely is a different road
    /// from the highway it runs beside, and collapsing the two would name the wrong one.
    static func displayRouteName(_ value: String) -> String {
        var name = value.replacing(/\s*\bnonCard\b/.ignoresCase(), with: "")
        name = name.replacing(/\bFront\b(?!age)/, with: "Frontage")
        let cleaned = name.replacing(/\s{2,}/, with: " ")
            .trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? value : cleaned
    }

    /// `"91-State Rte non-Card"` -> `"State Route"`, `"US Hwy non-Card"` -> `"US Highway"`.
    ///
    /// ADOT abbreviates in the data because the column is short; the card has room for words.
    static func displayRouteType(_ value: String) -> String {
        var text = stripOrdinal(value)
        text = text.replacing(/\s*non-Card\b/.ignoresCase(), with: "")
        text = text.replacing(/\bRte\b/, with: "Route")
        text = text.replacing(/\bHwy\b/, with: "Highway")
        let cleaned = text.trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? value : cleaned
    }

    /// TRACS is ADOT's project identifier: one or two letters, five or six digits, a trailing
    /// letter. It is a typed field on layer 24 and embedded in free text on layers 2 and 3
    /// (`"Per H729601C(Cy11)"`, `"Per ROW response from Ray 20120302, ..."`).
    static func tracsNumber(in text: String) -> String? {
        text.firstMatch(of: /[A-Z]{1,2}[0-9]{5,6}[A-Z]/).map { String($0.output) }
    }

    /// ATIS mirrors non-ADOT streets; those carry `RouteType` "L - Local (Non-ADOT)".
    private func isADOTRoute(_ feature: ArcGISFeature) -> Bool {
        guard let type = feature["RouteType"].text else { return false }
        return !type.hasPrefix("L")
    }

    /// The ADOT route the pin is actually on, or nil when the nearest road is not ADOT's.
    ///
    /// Taking the nearest feature outright would be a coin flip between a route and its own
    /// local mirror, and would silence this source on the interstate itself. Taking the
    /// nearest *ADOT* feature outright would be worse — a freeway 100 m away would claim a
    /// residential pin. So: find what is nearest, then prefer the ADOT record among the
    /// features sitting at that same spot.
    private func primaryRoute(in set: ArcGISFeatureSet, near point: Coordinate) -> ArcGISFeature? {
        let ranked = set.features
            .compactMap { feature in feature.distance(from: point).map { (feature, $0) } }
            .sorted { $0.1 < $1.1 }
        guard let nearest = ranked.first else { return nil }
        let coincident = ranked.prefix { $0.1 <= nearest.1 + Self.coincidenceToleranceMeters }
        return coincident.first { isADOTRoute($0.0) }?.0
    }

    // MARK: - Plumbing

    private struct LayerResult {
        let features: ArcGISFeatureSet
        let url: URL
        let fetchedAt: Date
    }

    private func result(layer: Int, envelope: Envelope) async throws -> LayerResult {
        let target = ArcGISLayer(Self.service, layer: layer)!
        let (features, url) = try await client.query(layer: target, envelope: envelope, returnGeometry: true)
        return LayerResult(features: features, url: url, fetchedAt: now())
    }
}

private extension ArcGISFeatureSet {
    /// Exact `RouteId` match. ATIS route ids are fixed-width composites
    /// (`"  I 010                         "`), and an interchange envelope returns the
    /// mainline, its ramps and nearby local streets all at once — matching on the raw id is
    /// what stops a ramp's TRACS number being reported as the mainline's.
    ///
    /// Only `applyProject` still uses this, and deliberately: it ranks by in-service date
    /// rather than by proximity, because `lastKnownImprovement` means *most recent work on
    /// this route*, not *nearest work to the pin*. Every lookup that wants the event the pin
    /// is standing on goes through `LRSJoin` instead.
    func matching(routeID: String) -> [ArcGISFeature] {
        features.filter { $0["RouteId"].rawString == routeID }
    }
}
