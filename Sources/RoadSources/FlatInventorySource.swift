import Foundation
import RoadCore

/// Reads a state DOT that publishes one denormalised roadway inventory.
///
/// About half the state DOTs probed take this shape: a single polyline layer carrying every
/// attribute at once — TxDOT returns 133 fields in one hit. One envelope query answers the
/// whole question, so there is no join and nothing to get wrong about measures.
///
/// What it still has to get right is *which* of the returned lines the pin is on. An envelope
/// in central Philadelphia returns fourteen segments including `SIXTEENTH ST` twice — once as
/// `JURIS = 1` built 1916, once as `JURIS = 5` with no year at all, because the state and the
/// city each carry a stretch of the same street. Nearest line wins.
public struct FlatInventorySource: RoadSource {
    public let id: String
    public let displayName: String

    private let profile: CoverageProfile
    private let client: ArcGISClient
    private let now: @Sendable () -> Date

    public init?(profile: CoverageProfile,
                 client: ArcGISClient = ArcGISClient(),
                 now: @escaping @Sendable () -> Date = Date.init) {
        guard profile.adapter == .flatInventory,
              let service = profile.service, let layer = profile.layer,
              ArcGISLayer(service, layer: layer) != nil, profile.fields != nil
        else { return nil }
        self.id = profile.id
        self.displayName = profile.displayName
        self.profile = profile
        self.client = client
        self.now = now
    }

    public func fetch(_ query: RoadQuery, resolved: RoadRecord) async throws -> RoadFragment {
        var fragment = RoadFragment()
        guard let service = profile.service, let layerID = profile.layer,
              let layer = ArcGISLayer(service, layer: layerID),
              let mapping = profile.fields
        else { return fragment }

        let envelope = Geo.envelope(around: query.coordinate, radiusMeters: query.searchRadiusMeters)
        let (features, url) = try await client.query(layer: layer, envelope: envelope,
                                                     returnGeometry: true)

        guard let nearest = features.features
            .compactMap({ feature -> (ArcGISFeature, Double)? in
                feature.distance(from: query.coordinate).map { (feature, $0) }
            })
            .min(by: { $0.1 < $1.1 })?.0
        else {
            fragment.notes = [note(.foundNothing, "\(displayName) publishes no road here.")]
            return fragment
        }

        // Centreline geometry is generalised and the pin is wherever the user put it, so this
        // is a spatial match — never `.direct`, which would overstate it.
        ProfileMapping.apply(nearest, mapping: mapping,
                             provenance: provenance(url: url, fetchedAt: now()),
                             confidence: .spatial, to: &fragment)

        fragment.notes = [note(fragment.contributesAnything ? .contributed : .foundNothing,
                               summary(fragment))]
        return fragment
    }

    /// Explains a missing year rather than leaving a hole, because a state that dates only its
    /// own roads is the normal case and looks like a bug otherwise.
    private func summary(_ fragment: RoadFragment) -> String? {
        guard fragment.contributesAnything else { return nil }
        if fragment.yearLastConstruction == nil, let caveat = profile.dateCaveat {
            return caveat
        }
        return fragment.segmentName.map { "Matched \($0.value) in the roadway inventory." }
    }
}
