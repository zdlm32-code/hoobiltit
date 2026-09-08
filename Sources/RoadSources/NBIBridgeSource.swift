import Foundation
import RoadCore

/// The National Bridge Inventory, published by USDOT.
///
/// Structures are the only place a genuine build year survives from before the county and
/// state started keeping segment records: 2,854 in Maricopa County, with `YEAR_BUILT` reaching
/// back to **1927**. It also separates original construction from reconstruction, which no
/// other source does — I-10 over Bullard Ave reads *built 1978, reconstructed 2011*, and
/// ADOT's construction date for that stretch is 2011. Showing only the later date would hide
/// half the road's history.
///
/// Most pins are ordinary street segments with no structure, so this source is usually silent:
/// it hit 1 of 6 test pins at 150 m and 3 of 6 at 400 m. That is expected, not a failure.
public struct NBIBridgeSource: RoadSource {
    public let id = "usdot.nbi"
    public let displayName = "National Bridge Inventory"

    static let layerURL = "https://services.arcgis.com/xOi1kZaI0eWDREZv/arcgis/rest/services/NTAD_National_Bridge_Inventory/FeatureServer"

    /// Bridges sit off the centerline more than a street segment does, and a structure a few
    /// hundred metres along the same road is still the structure you are standing on.
    static let searchRadiusMeters = 400.0

    /// NBI item 22. Codes are zero-padded strings.
    static let ownerNames: [String: String] = [
        "01": "State highway agency",
        "02": "County highway agency",
        "03": "Town or township highway agency",
        "04": "City or municipal highway agency",
        "11": "State park or forest agency",
        "12": "Local park or forest agency",
        "21": "Other state agency",
        "25": "Other local agency",
        "26": "Private owner",
        "27": "Railroad",
        "31": "State toll authority",
        "32": "Local toll authority",
        "62": "Bureau of Indian Affairs",
        "64": "US Forest Service",
        "66": "National Park Service",
        "68": "Bureau of Land Management",
    ]

    private let client: ArcGISClient
    private let now: @Sendable () -> Date

    public init(client: ArcGISClient = ArcGISClient(), now: @escaping @Sendable () -> Date = Date.init) {
        self.client = client
        self.now = now
    }

    /// A structure number with padding and separators removed, so two agencies' spellings of
    /// the same bridge compare equal.
    static func structureKey(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let stripped = raw.filter { $0.isLetter || $0.isNumber }
            .drop { $0 == "0" }
        return stripped.isEmpty ? nil : String(stripped).uppercased()
    }

    public func fetch(_ query: RoadQuery, resolved: RoadRecord) async throws -> RoadFragment {
        var fragment = RoadFragment()
        let roadName = resolved.segmentName?.value ?? resolved.routeDesignation?.value
        // An upstream layer may already know the structure number, which is the same key NBI
        // files a bridge under. TxDOT publishes it on 44,781 segments. With it there is no
        // guessing left to do; without it, the name gate below is the only thing standing
        // between a residential pin and a canal bridge four hundred metres away.
        let structure = resolved.structureNumber?.value
        guard roadName != nil || structure != nil else {
            fragment.notes = [note(.skipped, "No road identified yet, so a nearby structure "
                                             + "cannot be tied to it.")]
            return fragment
        }

        let layer = ArcGISLayer(Self.layerURL, layer: 0)!
        let envelope = Geo.envelope(around: query.coordinate,
                                    radiusMeters: max(Self.searchRadiusMeters, query.searchRadiusMeters))
        let (features, url) = try await client.query(layer: layer, envelope: envelope,
                                                     returnGeometry: false)

        // An exact key beats a name match, so it is tried first. NBI zero-pads its structure
        // numbers and the roadway layers do not always agree on the padding, so both are
        // compared with it stripped.
        let exact = structure.flatMap { number in
            features.features.first {
                Self.structureKey($0["STRUCTURE_NUMBER_008"].text) == Self.structureKey(number)
            }
        }
        // Otherwise gate on the road the structure carries. Without this a pin on a
        // residential street would be told about a canal bridge four hundred metres away.
        let byName = roadName.flatMap { name in
            features.features.first { RoadName.matches($0["FACILITY_CARRIED_007"].text, name) }
        }
        guard let feature = exact ?? byName else {
            fragment.notes = [note(.foundNothing, features.isEmpty
                ? "No bridge or structure near this point."
                : "Structures nearby, but none carries \(roadName ?? "this road").")]
            return fragment
        }

        let bridge = BridgeReference(
            structureNumber: feature["STRUCTURE_NUMBER_008"].text,
            carries: feature["FACILITY_CARRIED_007"].text,
            crosses: feature["FEATURES_DESC_006A"].text,
            yearBuilt: feature["YEAR_BUILT_027"].int,
            // 0 is the "never reconstructed" sentinel.
            yearReconstructed: feature["YEAR_RECONSTRUCTED_106"].int.flatMap { $0 > 0 ? $0 : nil },
            ownerDescription: feature["OWNER_022"].text.flatMap { Self.ownerNames[$0] },
            averageDailyTraffic: feature["ADT_029"].int,
            trafficCountYear: feature["YEAR_ADT_030"].int
        )
        fragment.bridge = Attributed(bridge, provenance: provenance(url: url, fetchedAt: now()),
                                     confidence: .direct)
        fragment.notes = [note(.contributed, Self.summary(bridge))]
        return fragment
    }

    static func summary(_ bridge: BridgeReference) -> String {
        var text = bridge.crosses.map { "Structure over \($0)" } ?? "Structure on this road"
        if let built = bridge.yearBuilt { text += ", built \(built)" }
        if let rebuilt = bridge.yearReconstructed { text += ", reconstructed \(rebuilt)" }
        return text + "."
    }
}
