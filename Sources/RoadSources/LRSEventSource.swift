import Foundation
import RoadCore

/// Reads a state DOT that decomposes its road data into linear-referenced event tables.
///
/// Arizona, Louisiana and Virginia take this shape: a route layer identifies the road, and
/// each attribute — ownership, last construction, functional class — lives in its own table
/// keyed by route id and a measure range. Answering one question means several queries and a
/// join, which is where the accuracy lives.
///
/// The join is `LRSJoin`, and it matters more than it looks. One envelope returns every event
/// the corridor touches, on every road in it. In a residential box in Baton Rouge the
/// construction table returns a single row — for Perkins Rd, which runs through the same box
/// — and a source that took the first event would date Balis Dr to 1971. Filtering on the
/// pin's own route id is what prevents that; ranking the survivors by proximity is what picks
/// the right one of the three consecutive Perkins Rd segments.
///
/// Event queries are issued concurrently. Serially, a five-layer profile over cellular is
/// about five round trips deep, and that is the difference between a lookup that feels
/// instant while driving and one that does not.
public struct LRSEventSource: RoadSource {
    public let id: String
    public let displayName: String

    private let profile: CoverageProfile
    private let client: ArcGISClient
    private let now: @Sendable () -> Date

    public init?(profile: CoverageProfile,
                 client: ArcGISClient = ArcGISClient(),
                 now: @escaping @Sendable () -> Date = Date.init) {
        guard profile.adapter == .lrsEvents,
              let service = profile.service, let routeLayer = profile.routeLayer,
              ArcGISLayer(service, layer: routeLayer) != nil
        else { return nil }
        self.id = profile.id
        self.displayName = profile.displayName
        self.profile = profile
        self.client = client
        self.now = now
    }

    public func fetch(_ query: RoadQuery, resolved: RoadRecord) async throws -> RoadFragment {
        var fragment = RoadFragment()
        guard let service = profile.service, let routeLayerID = profile.routeLayer,
              let routeLayer = ArcGISLayer(service, layer: routeLayerID)
        else { return fragment }

        let envelope = Geo.envelope(around: query.coordinate, radiusMeters: query.searchRadiusMeters)
        let routeIDField = profile.routeIDField ?? "RouteID"

        let (routes, routeURL) = try await client.query(layer: routeLayer, envelope: envelope,
                                                        returnGeometry: true)
        guard let route = routes.features
            .compactMap({ feature -> (ArcGISFeature, Double)? in
                feature.distance(from: query.coordinate).map { (feature, $0) }
            })
            .min(by: { $0.1 < $1.1 })?.0,
              let routeID = route[routeIDField].rawString
        else {
            fragment.notes = [note(.foundNothing, "\(displayName) publishes no route here.")]
            return fragment
        }

        // The pin's own span on the route, when the route layer publishes measures. Arizona's
        // does not; Louisiana's does.
        let span = LRSJoin.measureRange(
            of: route,
            fromField: profile.eventLayers?.first?.fromMeasureField ?? "FromMeasure",
            toField: profile.eventLayers?.first?.toMeasureField ?? "ToMeasure")

        // Events first, so a dedicated table beats the route layer's copy of the same field.
        // Louisiana's layers 49 and 91 genuinely disagree about Balis Dr — 2 against 4 — and
        // 91 is the measured HPMS table, so it must be consulted first.
        let results = await eventResults(service: service, envelope: envelope)
        for (event, features, url) in results {
            guard let feature = LRSJoin.best(in: features, routeID: routeID,
                                             routeIDField: event.routeIDField,
                                             near: query.coordinate, within: span,
                                             fromField: event.fromMeasureField,
                                             toField: event.toMeasureField)
            else { continue }
            ProfileMapping.apply(feature, mapping: event.fields,
                                 provenance: provenance(url: url, fetchedAt: now()),
                                 confidence: .direct, to: &fragment)
        }

        if let routeFields = profile.routeFields {
            ProfileMapping.apply(route, mapping: routeFields,
                                 provenance: provenance(url: routeURL, fetchedAt: now()),
                                 confidence: .spatial, to: &fragment)
        }

        let detail: String? = if fragment.yearLastConstruction == nil {
            profile.dateCaveat
        } else {
            "Joined \(profile.eventLayers?.count ?? 0) event tables on route \(routeID.trimmingCharacters(in: .whitespaces))."
        }
        fragment.notes = [note(fragment.contributesAnything ? .contributed : .foundNothing, detail)]
        return fragment
    }

    /// Every event layer, queried at once. A layer that fails is skipped rather than failing
    /// the source: one dead table must not cost the fields the others resolved.
    private func eventResults(service: String, envelope: Envelope)
        async -> [(EventLayerProfile, ArcGISFeatureSet, URL)] {
        let layers = profile.eventLayers ?? []
        return await withTaskGroup(of: (Int, EventLayerProfile, ArcGISFeatureSet, URL)?.self) { group in
            for (index, event) in layers.enumerated() {
                group.addTask { [client] in
                    guard let layer = ArcGISLayer(service, layer: event.layer),
                          let result = try? await client.query(layer: layer, envelope: envelope,
                                                               returnGeometry: true)
                    else { return nil }
                    return (index, event, result.features, result.url)
                }
            }
            var collected: [(Int, EventLayerProfile, ArcGISFeatureSet, URL)] = []
            for await result in group { if let result { collected.append(result) } }
            // Restored to the catalog's order, which encodes precedence.
            return collected.sorted { $0.0 < $1.0 }.map { ($0.1, $0.2, $0.3) }
        }
    }
}
