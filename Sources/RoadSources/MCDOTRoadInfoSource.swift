import Foundation
import RoadCore

/// Maricopa County DOT's Road Information Tool — the primary v1 source.
///
/// One service carries jurisdiction, county maintenance, classification, pavement build-up
/// and the recorded subdivision plat (docs/ENDPOINTS.md §1).
///
/// Ownership here is a *conclusion*, not a column. No county centerline layer has an owner
/// field, so it is derived from two facts: whether an incorporated municipality contains the
/// pin, and whether the pin falls on a county-maintained segment. An empty maintained-roads
/// response is meaningful data — it is how the app learns a city, not the county, is
/// responsible (§1.1, §1.2, §5.2).
public struct MCDOTRoadInfoSource: RoadSource {
    public let id = "mcdot.rit"
    public let displayName = "MCDOT Road Information Tool"

    static let service = "https://gis.maricopa.gov/dot/rest/services/Maintenance/RoadInformationTool/MapServer"

    private enum Layer {
        /// Incorporated municipalities only — absence means unincorporated county.
        static let municipalities = 7
        /// The 10,954 segments the county maintains.
        static let maintainedRoads = 2
        /// Recorded subdivision plats, 31,811 of 31,860 carrying a Recorder link.
        static let subdivision = 3
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
        let corridor = Geo.envelope(around: point, radiusMeters: query.searchRadiusMeters)
        // Polygon layers get a pin-sized envelope so "intersects" means "contains this point"
        // rather than "is somewhere in the neighbourhood".
        let pin = Geo.envelope(around: point, radiusMeters: 1)

        let municipality = try await result(layer: Layer.municipalities, envelope: pin, geometry: false)
        let maintained = try await result(layer: Layer.maintainedRoads, envelope: corridor, geometry: true)
        let subdivision = try await result(layer: Layer.subdivision, envelope: pin, geometry: false)

        applySegment(maintained, point: point, to: &fragment)
        applyJurisdiction(municipality, to: &fragment)
        applyPlat(subdivision, to: &fragment)
        applyOwner(municipality: municipality, maintained: maintained, point: point, to: &fragment)

        fragment.notes = [note(fragment.owner == nil ? .foundNothing : .contributed,
                               summary(municipality: municipality, maintained: maintained))]
        return fragment
    }

    // MARK: - Field extraction

    private func applySegment(_ result: LayerResult, point: Coordinate, to fragment: inout RoadFragment) {
        // Same gate as the other namers. The maintained-roads layer stops at the city line, so
        // a pin just inside a town can sit 100 m from the nearest county road; describing the
        // user's street with that road's name, surface and cross streets would be confident
        // and wrong.
        guard let feature = result.features.nearest(to: point),
              RoadProximity.isOnRoad(feature.distance(from: point))
        else { return }
        let source = { (confidence: MatchConfidence) in
            (provenance(url: result.url, fetchedAt: result.fetchedAt), confidence)
        }
        let (prov, confidence) = source(.direct)

        if let name = feature["OnRoad"].text ?? feature["Street"].text {
            fragment.segmentName = Attributed(name, provenance: prov, confidence: confidence)
        }
        if let classification = feature["Classification"].text {
            // Stored as "01 - Local"; the ordinal prefix is an internal sort key.
            let cleaned = classification.replacing(#/^\d+\s*-\s*/#, with: "")
            fragment.classification = Attributed(cleaned, provenance: prov, confidence: confidence)
        }
        if let from = feature["FromRoad"].text, let to = feature["ToRoad"].text {
            fragment.crossStreets = Attributed("\(from) to \(to)", provenance: prov, confidence: confidence)
        }
        if let identifier = feature["SegmentID"].text {
            fragment.segmentIdentifier = Attributed(identifier, provenance: prov, confidence: confidence)
        }
        if let district = feature["MaintenanceDistrict"].text {
            fragment.maintenanceDistrict = Attributed(district, provenance: prov, confidence: confidence)
        }
        if let district = feature["BoardOfSupervisorDistrict"].int {
            fragment.supervisorDistrict = Attributed(district, provenance: prov, confidence: confidence)
        }
        if let surfaceType = feature["SurfaceType"].text {
            let surface = SurfaceDescription(
                type: surfaceType,
                depthInches: feature["SurfaceDepth"].double,
                baseType: feature["BaseType"].text,
                baseDepthInches: feature["BaseDepth"].double,
                laneCount: feature["LaneCount"].int,
                widthFeet: feature["RoadWidth"].int,
                conditionIndex: feature["EstimatedOci"].double,
                conditionRating: feature["EstimatedOcr"].text
            )
            fragment.surface = Attributed(surface, provenance: prov, confidence: confidence)
        }

        // Deliberately not read: `FromDate`. It looks like a build date and is not — it is
        // ArcGIS temporal versioning, and its newest values are days old (§5.1).
    }

    private func applyJurisdiction(_ result: LayerResult, to fragment: inout RoadFragment) {
        let prov = provenance(url: result.url, fetchedAt: result.fetchedAt)
        guard let feature = result.features.features.first else {
            // Layer 7 holds incorporated cities only, so an empty result is the answer.
            fragment.jurisdiction = Attributed("Unincorporated Maricopa County",
                                               provenance: prov, confidence: .derived)
            return
        }
        if let full = feature["FullCityName"].text ?? feature["CityName"].text {
            fragment.jurisdiction = Attributed(full, provenance: prov, confidence: .spatial)
        }
        let annexation = AnnexationReference(
            ordinance: feature["Ordinance"].text,
            ordinanceDate: feature["OrdinanceDate"].epochMillisecondsDate,
            ordinanceURL: feature["OrdinanceWebLink"].url
        )
        if annexation != AnnexationReference() {
            fragment.annexation = Attributed(annexation, provenance: prov, confidence: .spatial)
        }
    }

    private func applyPlat(_ result: LayerResult, to fragment: inout RoadFragment) {
        guard let feature = result.features.features.first,
              let name = feature["SubdivisionName"].text else { return }
        fragment.plat = Attributed(
            PlatReference(subdivisionName: name,
                          recorderNumber: feature["MCRNumber"].text,
                          recorderURL: feature["MCRWebLink"].url),
            provenance: provenance(url: result.url, fetchedAt: result.fetchedAt),
            confidence: .spatial
        )

        // `plattedDate` is left nil on purpose. Layer 3 carries the Recorder book-page and a
        // link to the document but no recording date, so the date is not derivable here —
        // the UI sends the user to `recorderURL` for it (§1.3).
    }

    /// Ownership: maintained-set membership first, then municipality, then the honest
    /// remainder — unincorporated ground the county has not accepted.
    private func applyOwner(municipality: LayerResult, maintained: LayerResult,
                            point: Coordinate, to fragment: inout RoadFragment) {
        if let segment = maintained.features.nearest(to: point) {
            // 616 of 10,954 segments are maintained without having been accepted into the
            // county system — usually developer-built streets. Reporting those as county-owned
            // overstates what the county actually holds.
            let courtesy = segment["CourtesyMaintained"].text?.lowercased() == "yes"
            let agency = "Maricopa County Department of Transportation"
            fragment.owner = Attributed(
                courtesy ? .countyCourtesy(agency: agency) : .county(agency: agency),
                provenance: provenance(url: maintained.url, fetchedAt: maintained.fetchedAt),
                confidence: .derived
            )
        } else if let city = municipality.features.features.first,
                  let name = city["CityName"].text {
            fragment.owner = Attributed(
                .municipality(name: name, fullName: city["FullCityName"].text ?? name),
                provenance: provenance(url: municipality.url, fetchedAt: municipality.fetchedAt),
                confidence: .derived
            )
        } else {
            fragment.owner = Attributed(
                .notPubliclyMaintained,
                provenance: provenance(url: maintained.url, fetchedAt: maintained.fetchedAt),
                confidence: .derived
            )
        }
    }

    private func summary(municipality: LayerResult, maintained: LayerResult) -> String {
        let place = municipality.features.features.first?["FullCityName"].text
            ?? "unincorporated Maricopa County"
        return maintained.features.isEmpty
            ? "Not a county-maintained road; the pin is in \(place)."
            : "County-maintained segment in \(place)."
    }

    // MARK: - Plumbing

    private struct LayerResult {
        let features: ArcGISFeatureSet
        let url: URL
        let fetchedAt: Date
    }

    private func result(layer: Int, envelope: Envelope, geometry: Bool) async throws -> LayerResult {
        let target = ArcGISLayer(Self.service, layer: layer)!
        let (features, url) = try await client.query(layer: target, envelope: envelope,
                                                     returnGeometry: geometry)
        return LayerResult(features: features, url: url, fetchedAt: now())
    }
}
