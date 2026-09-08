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
///
/// Two guards sit on top of that. A nearest line that is still too far away is declined
/// outright, and a service that keeps its names on a second layer gets them joined back on, so
/// the name and the owner always describe the same segment.
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
        let (features, url) = try await client.query(
            layer: layer, envelope: envelope,
            outFields: profile.outFields.map { $0.joined(separator: ",") } ?? "*",
            returnGeometry: true)

        let nearest: ArcGISFeature
        switch profile.matchMode {
        case .containsPoint:
            // A project area is a polygon, and the pin is either in it or it is not. Measuring
            // to the boundary would reject a project the pin is standing in the middle of.
            let containing = features.features.filter { feature in
                (feature.geometry?.coordinatePaths ?? []).contains {
                    Geo.ring($0, contains: query.coordinate)
                }
            }
            guard let first = containing.first else {
                fragment.notes = [note(.foundNothing,
                                       "No \(displayName) project area covers this point.")]
                return fragment
            }
            // Every project covering the point, not one of them. A city rebuilds the same
            // street more than once, and the areas overlap; taking whichever the service
            // happened to return first would pick a year at random.
            let dated = containing.compactMap { ProfileMapping.work($0, mapping, now: now()) }
                .sorted { ($0.letDate ?? .distantPast) > ($1.letDate ?? .distantPast) }
            if !dated.isEmpty {
                fragment.works = Attributed(dated, provenance: provenance(url: url, fetchedAt: now()),
                                            confidence: .spatial)
            }
            nearest = first
        case .nearestLine:
            guard let (line, metres) = features.features
                .compactMap({ feature -> (ArcGISFeature, Double)? in
                    feature.distance(from: query.coordinate).map { (feature, $0) }
                })
                .min(by: { $0.1 < $1.1 })
            else {
                fragment.notes = [note(.foundNothing, "\(displayName) publishes no road here.")]
                return fragment
            }
            // An inventory covers one jurisdiction but not every road in it, and the nearest
            // thing it holds may simply be the next street over. Declining lets a later source
            // answer instead of attributing an arterial's owner to the lane beside it.
            guard RoadProximity.isOnRoad(metres) else {
                fragment.notes = [note(.foundNothing, "Nearest inventory segment is "
                                       + "\(Int(metres)) m away \u{2014} too far to be the road "
                                       + "at this point.")]
                return fragment
            }
            nearest = line
        }

        let provenance = provenance(url: url, fetchedAt: now())
        // Applied first so that a joined name wins over any the main layer carries, which is
        // the point of configuring a join at all.
        if let join = profile.nameJoin {
            await applyJoin(join, to: nearest, service: service, fragment: &fragment)
        }

        // Centreline geometry is generalised and the pin is wherever the user put it, so this
        // is a spatial match — never `.direct`, which would overstate it.
        ProfileMapping.apply(nearest, mapping: mapping, provenance: provenance,
                             confidence: .spatial, now: now(), to: &fragment)

        fragment.notes = [note(fragment.contributesAnything ? .contributed : .foundNothing,
                               summary(fragment))]
        return fragment
    }

    /// Borrows fields from a second layer keyed on an exact match.
    ///
    /// Failure is deliberately silent: the join supplies a name, and losing the name is not a
    /// reason to throw away the ownership and traffic the main layer already returned. The
    /// road ends up named by the national tier instead, which is the pre-join behaviour.
    private func applyJoin(_ join: NameJoinProfile,
                           to feature: ArcGISFeature,
                           service: String,
                           fragment: inout RoadFragment) async {
        guard let layer = ArcGISLayer(join.service ?? service, layer: join.layer),
              let key = feature[join.localKeyField].text
        else { return }
        var qualifier: (field: String, value: String)?
        if let field = join.filterField, let value = join.filterValue {
            qualifier = (field: field, value: value)
        }
        guard let (joined, url) = try? await client.query(layer: layer,
                                                          field: join.foreignKeyField,
                                                          equals: key, and: qualifier),
              let match = joined.features.first
        else { return }

        ProfileMapping.apply(match, mapping: join.fields,
                             provenance: provenance(url: url, fetchedAt: now()),
                             confidence: .spatial, to: &fragment)
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
