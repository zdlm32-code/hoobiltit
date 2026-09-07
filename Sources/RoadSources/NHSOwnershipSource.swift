import Foundation
import RoadCore

/// The only national dataset that says who owns a road.
///
/// FHWA's National Highway System, published on `geo.dot.gov` without a key, carries genuine
/// HPMS ownership codes on 498,226 segments: in Boston it reports the John F Fitzgerald
/// Expressway as state-owned and Tremont St as the city's.
///
/// Its limit is the point. The NHS is interstates, principal arterials and connectors — about
/// 4% of the network. An ordinary county arterial returns nothing, and so does a residential
/// street. That is not a failure to report; it is the honest edge of what can be known
/// nationally, and the two datasets that would fix it — FHWA ARNOLD and the full HPMS release
/// — are token-gated and unreachable from a keyless client.
///
/// **Name-gated.** The NHS is a coarse national layer and its lines sit tens of metres off a
/// local centreline, so an envelope near a city street will happily return the expressway two
/// blocks over. Unless the NHS's own `LNAME` matches the road already identified, this source
/// says nothing rather than attributing a freeway's owner to the street beside it.
public struct NHSOwnershipSource: RoadSource {
    public let id = "fhwa.nhs"
    public let displayName = "FHWA National Highway System"

    public static let service = "https://geo.dot.gov/server/rest/services/National_Highway_System/MapServer"
    static let layer = 0

    private let client: ArcGISClient
    private let now: @Sendable () -> Date

    public init(client: ArcGISClient = ArcGISClient(), now: @escaping @Sendable () -> Date = Date.init) {
        self.client = client
        self.now = now
    }

    public func fetch(_ query: RoadQuery, resolved: RoadRecord) async throws -> RoadFragment {
        var fragment = RoadFragment()
        guard resolved.owner == nil else {
            fragment.notes = [note(.skipped, "Ownership already established by "
                                   + (resolved.owner?.provenance.sourceName ?? "another source") + ".")]
            return fragment
        }
        guard let target = ArcGISLayer(Self.service, layer: Self.layer) else { return fragment }

        let envelope = Geo.envelope(around: query.coordinate, radiusMeters: query.searchRadiusMeters)
        let (features, url) = try await client.query(
            layer: target, envelope: envelope,
            outFields: "LNAME,OWNERSHIP,FCLASS,AADT,SIGN1", returnGeometry: true)

        let known = resolved.segmentName?.value ?? resolved.routeDesignation?.value
        let candidates = features.features.compactMap { feature -> (ArcGISFeature, Double)? in
            feature.distance(from: query.coordinate).map { (feature, $0) }
        }.sorted { $0.1 < $1.1 }

        // Only a segment whose own name matches the identified road may speak for it.
        let matched = candidates.first { candidate in
            guard let known, let lname = candidate.0["LNAME"].text else { return false }
            return RoadName.matches(lname, known)
        }

        guard let feature = matched?.0 else {
            fragment.notes = [note(.foundNothing, candidates.isEmpty
                ? "Not on the National Highway System."
                : "The nearest National Highway System route is not this road.")]
            return fragment
        }

        let provenance = provenance(url: url, fetchedAt: now())
        if let code = CodeTables.code(feature["OWNERSHIP"]), let owner = CodeTables.owner(hpms: code) {
            fragment.owner = Attributed(owner, provenance: provenance, confidence: .nameMatch)
        }
        if let code = CodeTables.code(feature["FCLASS"]),
           let classification = CodeTables.functionalClass[code] {
            fragment.classification = Attributed(classification, provenance: provenance,
                                                 confidence: .nameMatch)
        }
        if let aadt = feature["AADT"].double, aadt > 0 {
            fragment.trafficCount = Attributed(Int(aadt), provenance: provenance, confidence: .nameMatch)
        }
        fragment.notes = [note(fragment.contributesAnything ? .contributed : .foundNothing,
                               "On the National Highway System"
                               + (feature["SIGN1"].text.map { " as \($0)" } ?? "") + ".")]
        return fragment
    }
}
