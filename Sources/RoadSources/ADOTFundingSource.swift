import Foundation
import RoadCore

/// What an ADOT project was programmed to cost, and when it actually opened.
///
/// This is the only source in the whole pipeline that carries money. It answers a question the
/// app could not previously touch at all — not *who* built the road, which has no API in this
/// county, but *what it cost and out of whose budget*. TRACS `H881901C` on I-10 resolves to
/// $4,160,000, FFY2018, lead agency ADOT (docs/ENDPOINTS.md §3.2).
///
/// Runs after `ADOTStateRouteSource`, which resolves the TRACS number both lookups join on.
public struct ADOTFundingSource: RoadSource {
    public let id = "adot.funding"
    public let displayName = "ADOT programmed funding"

    static let fundingService = "https://services1.arcgis.com/XAiBIVuto7zeZj1B/arcgis/rest/services/mapped_route_export_July7/FeatureServer"
    /// Carries the in-service date as a real timestamp, where ATIS layer 24 has only a year.
    static let trackerService = "https://services1.arcgis.com/XAiBIVuto7zeZj1B/arcgis/rest/services/RCI_Tracker/FeatureServer"

    private let client: ArcGISClient
    private let now: @Sendable () -> Date

    public init(client: ArcGISClient = ArcGISClient(), now: @escaping @Sendable () -> Date = Date.init) {
        self.client = client
        self.now = now
    }

    public func fetch(_ query: RoadQuery, resolved: RoadRecord) async throws -> RoadFragment {
        var fragment = RoadFragment()
        // Both project numbers the ADOT source resolved: the one credited with construction
        // and the most recent work on the route. Programmed dollars are recorded against
        // whichever project is currently in the STIP, which is usually the later one, so
        // trying only the construction TRACS finds nothing on a road that plainly has funding.
        let candidates = [resolved.project?.value.projectNumber,
                          resolved.lastKnownImprovement?.value.projectNumber].compactMap { $0 }
        guard !candidates.isEmpty else {
            fragment.notes = [note(.skipped, "No ADOT project number resolved for this segment.")]
            return fragment
        }
        let envelope = Geo.envelope(around: query.coordinate, radiusMeters: query.searchRadiusMeters)

        for tracs in candidates where fragment.funding == nil {
            try await applyFunding(tracs: tracs, envelope: envelope, to: &fragment)
        }

        fragment.notes = [note(fragment.funding == nil ? .foundNothing : .contributed,
                               fragment.funding.map { Self.summary($0.value) }
                               ?? "No programmed funding recorded for "
                                  + candidates.joined(separator: " or ") + ".")]
        return fragment
    }

    private func applyFunding(tracs: String, envelope: Envelope,
                              to fragment: inout RoadFragment) async throws {
        let layer = ArcGISLayer(Self.fundingService, layer: 0)!
        let (features, url) = try await client.query(layer: layer, envelope: envelope,
                                                     returnGeometry: false)
        // `TRACS_NUM` is sometimes a comma-separated list ("T037001D, T037001X").
        guard let feature = features.features.first(where: {
            $0["TRACS_NUM"].text?.contains(tracs) == true
        }) else { return }

        let funding = ProjectFunding(
            programmedAmount: Self.programmedTotal(feature),
            fiscalYear: feature["FFY_LIST"].text,
            leadAgency: feature["LEAD_AGY"].text,
            region: feature["MPO_COG"].text,
            projectNumber: tracs,
            inServiceDate: try await inServiceDate(tracs: tracs, envelope: envelope)
        )
        fragment.funding = Attributed(funding, provenance: provenance(url: url, fetchedAt: now()),
                                      confidence: .direct)
    }

    /// The exact date the project opened. It belongs to the project, not to the roadway, so
    /// it rides on `ProjectFunding` rather than overwriting either construction-year field —
    /// ADOT's layer 2 says this stretch was last improved in 2011 while the project on it
    /// opened in 2019, and both statements are true about different things.
    private func inServiceDate(tracs: String, envelope: Envelope) async throws -> Date? {
        let layer = ArcGISLayer(Self.trackerService, layer: 0)!
        let (features, _) = try await client.query(layer: layer, envelope: envelope,
                                                   returnGeometry: false)
        return features.features
            .first { $0["ProjectTracsNumberValue"].text == tracs }?["ProjectInServiceDateValue"]
            .epochMillisecondsDate
    }

    /// Dollars are spread across prior-year and per-fiscal-year columns; the programmed total
    /// is their sum.
    static func programmedTotal(_ feature: ArcGISFeature) -> Double? {
        let columns = ["PRG_PRIOR", "PRG_2023", "PRG_2024", "PRG_2025",
                       "PRG_2026", "PRG_2027", "PRG_FUTURE"]
        let amounts = columns.compactMap { feature[$0].double }.filter { $0 > 0 }
        return amounts.isEmpty ? nil : amounts.reduce(0, +)
    }

    static func summary(_ funding: ProjectFunding) -> String {
        var text = "Project \(funding.projectNumber ?? "")"
        if let amount = funding.programmedAmount {
            text += " programmed at "
                + amount.formatted(.currency(code: "USD").precision(.fractionLength(0)))
        }
        if let year = funding.fiscalYear { text += " in \(year)" }
        if let agency = funding.leadAgency { text += ", lead agency \(agency)" }
        return text + "."
    }
}
