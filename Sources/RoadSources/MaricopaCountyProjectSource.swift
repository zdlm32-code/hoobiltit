import Foundation
import RoadCore

/// Maricopa County's capital and maintenance programmes.
///
/// The county splits work into two programmes and the distinction is exactly the one this
/// app cares about: **TIP** is capital work — widening, extension, construction — and answers
/// "what project built this"; **MIP** is maintenance — slurry seal, crack seal — and answers
/// "when was it last worked on". Reporting a slurry seal as the thing that built a road would
/// be wrong, so they land in different fields (docs/ENDPOINTS.md §2.1).
///
/// Neither programme records a contractor or an award amount. Nothing in the county's GIS
/// does; that leg needs the Board's agenda PDFs and is out of scope for v1 (§6).
public struct MaricopaCountyProjectSource: RoadSource {
    public let id = "mcdot.projects"
    public let displayName = "MCDOT capital & maintenance programmes"

    static let transportationService = "https://gis.maricopa.gov/arcgis/rest/services/BOS/Transportation/MapServer"
    static let projectStatusService = "https://gis.maricopa.gov/dot/rest/services/Planning/ProjectStatus/MapServer"

    private enum Layer {
        static let linearTIP = 770   // capital improvements along a corridor
        static let linearMIP = 790   // maintenance along a corridor
        /// Point-located work — bridges, signals, drainage, cattle guards. A line query
        /// structurally cannot see these, and they are often the only project on a segment.
        static let spotTIP = 760
        static let spotMIP = 780
        static let projectStatus = 1 // Planning/ProjectStatus — joins to TIP by project number
    }

    /// Projects are stored against a linear referencing system, not as copies of the
    /// centerline, so a project line can sit a couple of hundred metres off the road it
    /// describes — the Deer Valley Road TIP line measures 206 m from a pin on that road.
    /// A radius tight enough to identify *which street you are on* therefore misses the
    /// project that built it, and one wide enough to catch it will also catch the next
    /// street over. The wider radius is only trusted when the road names agree.
    static let corridorRadiusMeters = 400.0

    private let client: ArcGISClient
    private let now: @Sendable () -> Date

    public init(client: ArcGISClient = ArcGISClient(), now: @escaping @Sendable () -> Date = Date.init) {
        self.client = client
        self.now = now
    }

    public func fetch(_ query: RoadQuery, resolved: RoadRecord) async throws -> RoadFragment {
        var fragment = RoadFragment()
        let point = query.coordinate
        let corridor = Geo.envelope(around: point, radiusMeters: max(Self.corridorRadiusMeters,
                                                                     query.searchRadiusMeters))
        // What the segment is called, if an earlier source worked it out.
        let roadName = resolved.segmentName?.value ?? resolved.routeDesignation?.value

        // Corridor work first, then point work. A widening is the better answer to "what built
        // this road" than a cattle-guard repair at the same spot, so spot layers only fill a
        // gap the linear ones left.
        var capital: ProjectReference?
        for layer in [Layer.linearTIP, Layer.spotTIP] where fragment.project == nil {
            let tip = try await result(Self.transportationService, layer: layer, envelope: corridor)
            guard let feature = pick(from: tip.features, near: point, on: roadName,
                                     within: query.searchRadiusMeters) else { continue }
            capital = project(from: feature, kind: "Capital improvement")
            fragment.project = capital.map {
                // Projects are linearly referenced, not shaped like the centerline, so this
                // is a proximity match and says so (§5.5).
                Attributed($0, provenance: provenance(url: tip.url, fetchedAt: tip.fetchedAt),
                           confidence: .spatial)
            }
        }
        for layer in [Layer.linearMIP, Layer.spotMIP] where fragment.lastKnownImprovement == nil {
            // Spot MIP carries no road name at all, so the gate below can never widen for it —
            // it is accepted only when the pin falls inside the tight radius. That is the
            // right outcome: an unnamed maintenance point 300 m away could be any street.
            let mip = try await result(Self.transportationService, layer: layer, envelope: corridor)
            guard let feature = pick(from: mip.features, near: point, on: roadName,
                                     within: query.searchRadiusMeters),
                  let maintenance = project(from: feature, kind: "Maintenance") else { continue }
            fragment.lastKnownImprovement = Attributed(
                maintenance,
                provenance: provenance(url: mip.url, fetchedAt: mip.fetchedAt),
                confidence: .spatial
            )
        }

        // The status table shares TIP's `TTxxxx` numbering, so this is a typed join rather
        // than another guess at geometry.
        if let number = capital?.projectNumber {
            try await enrichWithStatus(projectNumber: number, to: &fragment)
        }

        fragment.notes = [note(fragment.project == nil && fragment.lastKnownImprovement == nil
                               ? .foundNothing : .contributed,
                               summary(tip: fragment.project, mip: fragment.lastKnownImprovement))]
        return fragment
    }

    /// The project covering this pin, or nil.
    ///
    /// Inside the tight radius, nearest wins — the pin is on the project. Between there and
    /// the corridor radius, a project is only accepted when its road name matches the segment
    /// an earlier source identified, which is what stops a neighbouring street's project
    /// being reported as this one's.
    private func pick(from set: ArcGISFeatureSet, near point: Coordinate,
                      on roadName: String?, within tightRadius: Double) -> ArcGISFeature? {
        let ranked = set.features
            .compactMap { feature in feature.distance(from: point).map { (feature, $0) } }
            .sorted { $0.1 < $1.1 }
        guard let nearest = ranked.first else { return nil }
        if nearest.1 <= tightRadius { return nearest.0 }

        guard let roadName else { return nil }
        return ranked.first { candidate, _ in
            RoadName.matches(candidate["OnRoadName"].roadName, roadName)
        }?.0
    }

    // MARK: - Fields

    private func project(from feature: ArcGISFeature, kind: String) -> ProjectReference? {
        guard let title = feature["Title"].text else { return nil }
        return ProjectReference(
            projectNumber: feature["ProjNum"].text,
            title: title,
            detail: feature["Description"].text.map { AgencyText.summary(AgencyText.strippingHTML($0)) },
            phase: feature["Phase"].text,
            projectType: feature["ProjectType"].text ?? kind,
            location: location(from: feature)
        )
    }

    /// Road names on these layers carry a padded route-segment ordinal
    /// (`"Deer Valley Rd                          01"`), so they need `roadName`, not `text`.
    private func location(from feature: ArcGISFeature) -> String? {
        guard let on = feature["OnRoadName"].roadName else { return nil }
        guard let from = feature["FromRefName"].roadName, let to = feature["ToRefName"].roadName else {
            return on
        }
        return "\(on): \(from) to \(to)"
    }

    private func enrichWithStatus(projectNumber: String, to fragment: inout RoadFragment) async throws {
        let layer = ArcGISLayer(Self.projectStatusService, layer: Layer.projectStatus)!
        let (features, url) = try await client.query(layer: layer, field: "ProjectNumber",
                                                     equals: projectNumber)
        guard let feature = features.features.first, let existing = fragment.project?.value else { return }

        let description = feature["ProjectDescription"].text.map {
            AgencyText.summary(AgencyText.strippingHTML($0))
        }
        fragment.project = Attributed(
            ProjectReference(
                projectNumber: existing.projectNumber,
                title: feature["ProjectTitle"].text ?? existing.title,
                // The status table's write-up is public-facing prose; prefer it.
                detail: description ?? existing.detail,
                phase: feature["CurrentStatus"].text ?? existing.phase,
                projectType: existing.projectType,
                location: existing.location
            ),
            provenance: provenance(url: url, fetchedAt: now()),
            // Joined on the project number, not on geometry.
            confidence: .direct
        )
    }

    private func summary(tip: Attributed<ProjectReference>?, mip: Attributed<ProjectReference>?) -> String {
        switch (tip?.value, mip?.value) {
        case let (capital?, maintenance?):
            "Capital project \(capital.projectNumber ?? capital.title); "
            + "last maintenance \(maintenance.projectNumber ?? maintenance.title)."
        case let (capital?, nil):
            "Capital project \(capital.projectNumber ?? capital.title); no maintenance record here."
        case let (nil, maintenance?):
            "Maintenance only: \(maintenance.projectNumber ?? maintenance.title)."
        case (nil, nil):
            "No county capital or maintenance project recorded on this segment."
        }
    }

    // MARK: - Plumbing

    private struct LayerResult {
        let features: ArcGISFeatureSet
        let url: URL
        let fetchedAt: Date
    }

    private func result(_ service: String, layer: Int, envelope: Envelope) async throws -> LayerResult {
        let target = ArcGISLayer(service, layer: layer)!
        let (features, url) = try await client.query(layer: target, envelope: envelope, returnGeometry: true)
        return LayerResult(features: features, url: url, fetchedAt: now())
    }
}
