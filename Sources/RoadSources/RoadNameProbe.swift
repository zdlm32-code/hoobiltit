import Foundation
import RoadCore

/// A cheap "which road am I on" check, used to decide whether a full lookup is worth running.
///
/// Drive mode cannot re-run the whole pipeline every few seconds: a full resolve asks every
/// source in the pipeline across a dozen-odd requests and takes ~20 s cold, by which time a
/// car at 45 mph has travelled 400 m. The 11 m cache key does not help either, because every
/// fix while moving is a fresh key.
///
/// So this reads one centreline service — its layers queried concurrently — and returns just
/// the nearest street name. When that name changes, and only then, the full pipeline runs.
///
/// The service is configuration rather than a constant, because the probe has to work
/// wherever the car is. It used to hardcode Maricopa County's centreline, which meant that
/// outside Maricopa it was silent on every road and drive mode fell back to re-resolving on
/// distance alone. `.national` reads Census TIGER/Line and so names a street anywhere in the
/// country; a county with a better centreline can still supply its own.
public struct RoadNameProbe: Sendable {
    /// Which service to read, and the fields that carry a name and a classification in it.
    public struct Service: Sendable, Hashable {
        public let url: String
        public let layers: [Int]
        public let nameField: String
        public let classificationField: String?
        /// TIGER's geometry is generalised and a 60 m box comes back empty in a dense
        /// downtown, so a service can insist on a wider search than the caller asked for.
        public let minimumRadiusMeters: Double

        public init(url: String, layers: [Int], nameField: String,
                    classificationField: String? = nil, minimumRadiusMeters: Double = 0) {
            self.url = url
            self.layers = layers
            self.nameField = nameField
            self.classificationField = classificationField
            self.minimumRadiusMeters = minimumRadiusMeters
        }

        /// Census TIGER/Line: 16.1 million local road segments, every state. The default,
        /// because the one thing this probe must never be is silent.
        public static let national = Service(
            url: TIGERNameSource.service,
            layers: TIGERNameSource.layers,
            nameField: "NAME",
            classificationField: "MTFCC",
            minimumRadiusMeters: TIGERNameSource.minimumRadiusMeters)

        /// Maricopa's countywide centreline. Better than TIGER inside the county: it is the
        /// county's own naming, and it carries a human classification ("Arterial") rather
        /// than a feature-class code.
        public static let maricopa = Service(
            url: "https://gis.maricopa.gov/arcgis/rest/services/IndividualService/Street/MapServer",
            layers: [1, 2, 3],       // Highway, Arterial, Local — no combined layer exists
            nameField: "FullStreetName",
            classificationField: "Classification")
    }

    public struct Hit: Sendable, Hashable {
        public let name: String
        public let metresAway: Double
        /// "Arterial", "Residential", "Local street" — the service's own wording.
        public let classification: String?
    }

    public let service: Service
    private let client: ArcGISClient

    public init(service: Service = .national, client: ArcGISClient = ArcGISClient()) {
        self.service = service
        self.client = client
    }

    /// Nearest named centreline to `coordinate`, or nil if none is within the radius.
    public func nearestRoad(to coordinate: Coordinate,
                            within radiusMeters: Double = 150) async -> Hit? {
        let radius = max(radiusMeters, service.minimumRadiusMeters)
        let envelope = Geo.envelope(around: coordinate, radiusMeters: radius)
        let fields = [service.nameField, service.classificationField]
            .compactMap { $0 }.joined(separator: ",")

        let hits = await withTaskGroup(of: Hit?.self) { group in
            for layer in service.layers {
                group.addTask { [client, service] in
                    guard let target = ArcGISLayer(service.url, layer: layer),
                          let (features, _) = try? await client.query(
                              layer: target, envelope: envelope,
                              outFields: fields, returnGeometry: true)
                    else { return nil }
                    return Self.nearest(in: features, to: coordinate, service: service)
                }
            }
            var found: [Hit] = []
            for await hit in group { if let hit { found.append(hit) } }
            return found
        }
        return hits.min { $0.metresAway < $1.metresAway }
    }

    static func nearest(in features: ArcGISFeatureSet, to point: Coordinate,
                        service: Service) -> Hit? {
        var best: Hit?
        for feature in features.features {
            guard let name = feature[service.nameField].text,
                  let distance = feature.distance(from: point) else { continue }
            if best == nil || distance < best!.metresAway {
                // TIGER classifies by MTFCC code, which is meaningless on screen; the shared
                // table turns S1400 into "Local street". A service publishing prose passes
                // straight through.
                let raw = service.classificationField.flatMap { feature[$0].text }
                best = Hit(name: name, metresAway: distance,
                           classification: raw.map { TIGERNameSource.featureClasses[$0] ?? $0 })
            }
        }
        return best
    }
}
