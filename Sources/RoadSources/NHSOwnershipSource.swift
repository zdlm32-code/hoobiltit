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
///
/// Two narrow exceptions, both for highways. A segment whose route sign (`S101`) matches the
/// identified route ("State Rte 101") is the same road whatever its `LNAME` says. And some NHS
/// freeway segments are unnamed — Loop 101 through north Phoenix — or named after the arterial
/// alignment they follow — the same freeway is "PIMA RD" through Scottsdale. So when the road
/// under the pin is itself a freeway by name, the nearest freeway-class segment within
/// `unnamedFreewayMeters` that is unnamed or shares its base name may speak for its *owner*,
/// and nothing else: at an interchange the nearest freeway may be the other one, which has the
/// same owner but not the same traffic or class.
public struct NHSOwnershipSource: RoadSource {
    public let id = "fhwa.nhs"
    public let displayName = "FHWA National Highway System"

    public static let service = "https://geo.dot.gov/server/rest/services/National_Highway_System/MapServer"
    static let layer = 0
    /// How near an unnamed freeway segment must be to speak for the freeway under the pin.
    static let unnamedFreewayMeters = 60.0

    private let client: ArcGISClient
    private let now: @Sendable () -> Date

    public init(client: ArcGISClient = ArcGISClient(), now: @escaping @Sendable () -> Date = Date.init) {
        self.client = client
        self.now = now
    }

    public func fetch(_ query: RoadQuery, resolved: RoadRecord) async throws -> RoadFragment {
        var fragment = RoadFragment()
        // An owner inferred from city limits is not established; it is the gap this source exists
        // to fill. Skipping on it is how Loop 101 became "City of Phoenix (inferred)".
        guard resolved.owner.map({ $0.isInferredFromLocation }) ?? true else {
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

        // Only a segment whose own name — or route sign — matches the identified road may speak
        // for it.
        let route = resolved.routeDesignation?.value ?? known
        let matched = candidates.first { candidate in
            if let known, let lname = candidate.0["LNAME"].text, RoadName.matches(lname, known) {
                return true
            }
            return HighwayName.sameRoute(candidate.0["SIGN1"].text, route)
        }

        if matched == nil, HighwayName.isHighway(known),
           let nearest = candidates.first, nearest.1 <= Self.unnamedFreewayMeters,
           nearest.0["LNAME"].text == nil || HighwayName.sameStem(nearest.0["LNAME"].text, known),
           let fclass = CodeTables.code(nearest.0["FCLASS"]), (1...2).contains(fclass),
           let code = CodeTables.code(nearest.0["OWNERSHIP"]), let owner = CodeTables.owner(hpms: code) {
            fragment.owner = Attributed(owner, provenance: provenance(url: url, fetchedAt: now()),
                                        confidence: .spatial)
            let named = nearest.0["LNAME"].text.map { "named \($0)" } ?? "unnamed"
            fragment.notes = [note(.contributed, "Owner from the nearest National Highway System "
                                   + "freeway, which is \(named)"
                                   + (nearest.0["SIGN1"].text.map { " and signed \($0)" } ?? "")
                                   + ".")]
            return fragment
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
        // A ramp matches its route's sign but is not the main line: it shares the owner and
        // nothing else.
        if HighwayName.isRamp(known) {
            fragment.notes = [note(fragment.contributesAnything ? .contributed : .foundNothing,
                                   "Owner from the route this ramp serves"
                                   + (feature["SIGN1"].text.map { ", \($0)" } ?? "") + ".")]
            return fragment
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
