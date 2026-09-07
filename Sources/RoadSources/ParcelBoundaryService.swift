import Foundation
import RoadCore

/// Parcel boundaries for whatever rectangle the map is showing.
///
/// Deliberately *not* a `RoadSource`. That protocol answers "what is at this pin" and its
/// results are merged into a `RoadRecord` and cached per location; this answers "what is in
/// this rectangle" and its results live only as long as the map is looking there. It shares
/// nothing with `MaricopaParcelSource` but the endpoint.
public struct ParcelBoundaryService: Sendable {
    /// The Assessor caps a response at 1,000 features and does not say when it truncates, so
    /// anything at or above this count is treated as "the viewport is too wide to trust".
    public static let serverRecordCap = 1000
    /// Each polygon is a SwiftUI view. The zoom gate should keep us far below this; it exists
    /// so a dense downtown block cannot stall the map.
    public static let renderCap = 400

    public struct Result: Sendable {
        public let outlines: [ParcelOutline]
        /// True when the server may have withheld parcels, so the overlay must not imply it is
        /// showing the whole picture.
        public let possiblyTruncated: Bool
    }

    private let client: ArcGISClient

    public init(client: ArcGISClient = ArcGISClient()) {
        self.client = client
    }

    /// Boundaries intersecting `envelope`, or nil when the viewport is too wide to draw.
    public func outlines(in envelope: Envelope, span: MapSpan) async throws -> Result? {
        guard Geo.parcelsWorthDrawing(at: span) else { return nil }

        let layer = ArcGISLayer(MaricopaParcelSource.layerURL,
                                layer: MaricopaParcelSource.parcelLayerID)!
        // Only the APN: none of the owner or valuation fields matter for drawing lines.
        let (features, _) = try await client.query(
            layer: layer, envelope: envelope,
            outFields: "APN_DASH", returnGeometry: true,
            maxAllowableOffset: Geo.simplificationTolerance(for: span)
        )

        let outlines = features.features.prefix(Self.renderCap).compactMap(Self.outline(from:))
        return Result(outlines: Array(outlines),
                      possiblyTruncated: features.features.count >= Self.serverRecordCap)
    }

    static func outline(from feature: ArcGISFeature) -> ParcelOutline? {
        guard let apn = feature["APN_DASH"].text ?? feature["APN"].text else { return nil }
        let rings = feature.geometry?.coordinatePaths.filter { $0.count >= 3 } ?? []
        guard !rings.isEmpty else { return nil }
        return ParcelOutline(apn: apn, rings: rings)
    }
}
