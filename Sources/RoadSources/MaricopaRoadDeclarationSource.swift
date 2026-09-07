import Foundation
import RoadCore

/// The county's road-file declarations and right-of-way acquisitions.
///
/// This is the closest thing to a build date that exists for a county road. The county has no
/// construction-year field anywhere, but it does record the moment a road was *declared a
/// public county road*, with the recorded document behind it — 3,222 of 3,283 polygons carry
/// an `EffectiveDate`, reaching back past 1970. Lone Mountain Rd resolves to 2014, Sun City's
/// Santa Fe Dr to 1982 (docs/ENDPOINTS.md §2.4).
///
/// Runs after `MCDOTRoadInfoSource`, because the gate below needs the segment name.
public struct MaricopaRoadDeclarationSource: RoadSource {
    public let id = "mcdot.declaration"
    public let displayName = "Maricopa County road declarations"

    static let propertyService = "https://gis.maricopa.gov/dot/rest/services/Property/RightOfWay/MapServer"

    private enum Layer {
        /// Open And Declared (Verified) — the declaration polygons and their effective dates.
        static let declaration = 1
        /// Right-Of-Way (Verified) — how the county acquired the ground.
        static let rightOfWay = 0
    }

    private let client: ArcGISClient
    private let now: @Sendable () -> Date

    public init(client: ArcGISClient = ArcGISClient(), now: @escaping @Sendable () -> Date = Date.init) {
        self.client = client
        self.now = now
    }

    public func fetch(_ query: RoadQuery, resolved: RoadRecord) async throws -> RoadFragment {
        var fragment = RoadFragment()
        let point = query.coordinate
        let envelope = Geo.envelope(around: point, radiusMeters: query.searchRadiusMeters)

        try await applyDeclaration(envelope: envelope, resolved: resolved, to: &fragment)
        try await applyAcquisition(envelope: envelope, point: point, to: &fragment)

        fragment.notes = [note(fragment.declaration == nil ? .foundNothing : .contributed,
                               summary(fragment))]
        return fragment
    }

    // MARK: - Declaration

    private func applyDeclaration(envelope: Envelope, resolved: RoadRecord,
                                  to fragment: inout RoadFragment) async throws {
        let layer = ArcGISLayer(Self.propertyService, layer: Layer.declaration)!
        let (features, url) = try await client.query(layer: layer, envelope: envelope,
                                                     returnGeometry: false)
        guard let (feature, confidence) = pick(from: features.features, resolved: resolved),
              let date = feature["EffectiveDate"].epochMillisecondsDate,
              let roadName = feature["RoadName"].text
        else { return }

        fragment.declaration = Attributed(
            RoadDeclaration(roadName: roadName,
                            roadFileNumber: feature["RoadFileNumber"].text,
                            effectiveDate: date,
                            documentURL: feature["RoadFileRecordingNumberURL"].url),
            provenance: provenance(url: url, fetchedAt: now()),
            confidence: confidence
        )
    }

    /// The declaration covering this pin, and how firmly it is tied to it.
    ///
    /// A 150 m envelope returns a handful of polygons — the road's own declaration plus its
    /// neighbours' — so something has to choose. `RoadName` holds either a street name or a
    /// subdivision name depending on how the road came to be, which is exactly the two things
    /// an earlier source has already resolved. Matching against both covers the street case
    /// (Lone Mountain Rd, Santa Fe Dr) and the developer case (Crossriver Unit 8), and
    /// matching neither means saying nothing.
    private func pick(from features: [ArcGISFeature],
                      resolved: RoadRecord) -> (ArcGISFeature, MatchConfidence)? {
        let segmentName = resolved.segmentName?.value
        if let match = features.first(where: { RoadName.matches($0["RoadName"].text, segmentName) }) {
            return (match, .direct)
        }
        let subdivision = resolved.plat?.value.subdivisionName
        if let match = features.first(where: { RoadName.matches($0["RoadName"].text, subdivision) }) {
            return (match, .nameMatch)
        }
        return nil
    }

    // MARK: - Acquisition

    private func applyAcquisition(envelope: Envelope, point: Coordinate,
                                  to fragment: inout RoadFragment) async throws {
        let layer = ArcGISLayer(Self.propertyService, layer: Layer.rightOfWay)!
        let (features, url) = try await client.query(layer: layer, envelope: envelope,
                                                     returnGeometry: true)
        // No road name on this layer, so the only handle is geometry.
        guard let feature = features.nearest(to: point),
              let method = feature["aquisition_type"].text   // misspelled in the schema
        else { return }

        fragment.acquisition = Attributed(
            RoadAcquisition(method: method,
                            widthFeet: feature["RightOfWayWidth"].double,
                            recorderNumber: feature["RecorderNumber"].text,
                            recorderURL: feature["RecorderUrl"].url),
            provenance: provenance(url: url, fetchedAt: now()),
            confidence: .spatial
        )
    }

    private func summary(_ fragment: RoadFragment) -> String {
        switch (fragment.declaration?.value, fragment.acquisition?.value) {
        case let (declaration?, acquisition?):
            "Declared a public road on "
            + CalendarDate.medium(declaration.effectiveDate)
            + "; right of way acquired by \(acquisition.method.lowercased())."
        case let (declaration?, nil):
            "Declared a public road on "
            + CalendarDate.medium(declaration.effectiveDate) + "."
        case let (nil, acquisition?):
            "No declaration matched this road; right of way acquired by \(acquisition.method.lowercased())."
        case (nil, nil):
            "No county road declaration recorded for this segment."
        }
    }
}
