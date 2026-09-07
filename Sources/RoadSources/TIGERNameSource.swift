import Foundation
import RoadCore

/// Names a street anywhere in the United States, from the Census Bureau's road centrelines.
///
/// This is the floor the app degrades to. TIGER/Line covers all 16.1 million local road
/// segments in the country, so outside a mapped county or state the app can still say *what*
/// road you are on — and, from the feature class, roughly what kind of road it is. It carries
/// **no ownership and no dates**; it is a gazetteer, and this source claims nothing more.
///
/// Runs last among the naming sources, so a state or county centreline that actually knows the
/// road keeps its own, richer answer.
///
/// Two practical notes learned by probing. The layers are split by road class and a query does
/// not fall through between them, so all three are asked at once. And TIGER geometry is
/// positionally coarse: a 60 m box in downtown Boston returns **nothing at all** while a 150 m
/// box returns eleven streets. The app's 150 m default is above that floor; a smaller radius
/// would make this source silently useless in exactly the dense places it is most needed.
public struct TIGERNameSource: RoadSource {
    public let id = "census.tiger"
    public let displayName = "Census TIGER/Line"

    public static let service = "https://tigerweb.geo.census.gov/arcgis/rest/services/TIGERweb/Transportation/MapServer"
    /// Primary (limited access), secondary (arteries), and local — which is everything else
    /// and is 16.1 million of the 16.6 million features.
    static let layers = [2, 6, 8]
    /// Below this TIGER's generalisation starts returning empty envelopes downtown.
    static let minimumRadiusMeters = 120.0

    /// MTFCC feature classes, from the Census code list. Only the classes a driver can
    /// plausibly be on are named; a walkway or a stairway is not a road this app answers for.
    static let featureClasses: [String: String] = [
        "S1100": "Primary road",
        "S1200": "Secondary road",
        "S1400": "Local street",
        "S1500": "Vehicular trail",
        "S1630": "Ramp",
        "S1640": "Frontage road",
        "S1730": "Alley",
        "S1740": "Service road",
        "S1780": "Parking lot road",
    ]

    private let client: ArcGISClient
    private let now: @Sendable () -> Date

    public init(client: ArcGISClient = ArcGISClient(), now: @escaping @Sendable () -> Date = Date.init) {
        self.client = client
        self.now = now
    }

    public func fetch(_ query: RoadQuery, resolved: RoadRecord) async throws -> RoadFragment {
        var fragment = RoadFragment()
        guard resolved.segmentName == nil else {
            fragment.notes = [note(.skipped, "Already named by "
                                   + (resolved.segmentName?.provenance.sourceName ?? "another source") + ".")]
            return fragment
        }

        let radius = max(query.searchRadiusMeters, Self.minimumRadiusMeters)
        let envelope = Geo.envelope(around: query.coordinate, radiusMeters: radius)

        let hits = await withTaskGroup(of: (ArcGISFeature, URL, Double)?.self) { group in
            for layer in Self.layers {
                group.addTask { [client] in
                    guard let target = ArcGISLayer(Self.service, layer: layer),
                          let (features, url) = try? await client.query(
                              layer: target, envelope: envelope,
                              outFields: "NAME,MTFCC,RTTYP", returnGeometry: true)
                    else { return nil }
                    // Unnamed features are ramps and service spurs; a name is the whole point.
                    let named = features.features.compactMap { feature -> (ArcGISFeature, URL, Double)? in
                        guard feature["NAME"].text != nil,
                              let distance = feature.distance(from: query.coordinate)
                        else { return nil }
                        return (feature, url, distance)
                    }
                    return named.min { $0.2 < $1.2 }
                }
            }
            var found: [(ArcGISFeature, URL, Double)] = []
            for await hit in group { if let hit { found.append(hit) } }
            return found
        }

        guard let (feature, url, metres) = hits.min(by: { $0.2 < $1.2 }),
              let name = feature["NAME"].text
        else {
            fragment.notes = [note(.foundNothing, "No Census road centreline within \(Int(radius)) m.")]
            return fragment
        }
        // Same rule as every other namer: near enough to be the road here, or say nothing.
        // As the last source to try, declining means the app reports no road — which is the
        // honest answer for a pin dropped between streets or out in open desert.
        guard RoadProximity.isOnRoad(metres) else {
            fragment.notes = [note(.foundNothing, "Nearest Census centreline is \(name), "
                                   + "\(Int(metres)) m away \u{2014} too far to be the road here.")]
            return fragment
        }

        let provenance = provenance(url: url, fetchedAt: now())
        fragment.segmentName = Attributed(name, provenance: provenance, confidence: .spatial)
        if let type = feature["MTFCC"].text.flatMap({ Self.featureClasses[$0] }) {
            fragment.classification = Attributed(type, provenance: provenance, confidence: .spatial)
        }
        // Deliberately no owner. RTTYP is how a route is *signed*, not who maintains it: a
        // county arterial like Williams Dr signs as a common name, and reading the shield as
        // ownership would invent an answer TIGER does not contain.
        fragment.notes = [note(.contributed, "Named from the Census road centreline. "
                               + "TIGER/Line carries no ownership or construction date.")]
        return fragment
    }
}
