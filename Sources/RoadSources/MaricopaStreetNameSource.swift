import Foundation
import RoadCore

/// Names the street from the county's countywide centreline.
///
/// Every other source that identifies a road covers only part of the county: MCDOT's
/// maintained-roads layer stops at the city line, and ADOT's covers state routes. So inside an
/// incorporated city the app could say *City of Goodyear maintains this* and still not name
/// the street — which is what "No road identified here" meant while driving through Goodyear,
/// on a road with a perfectly good name.
///
/// `IndividualService/Street` is the county's full centreline and does cover cities: verified
/// naming streets in Goodyear, Phoenix and Tempe.
///
/// Runs **after** `MCDOTRoadInfoSource`, so a county-maintained road keeps MCDOT's richer
/// record, and **before** the declaration, project, bridge and parcel sources, all of which
/// gate on having a segment name — giving them one is what makes them work inside cities.
public struct MaricopaStreetNameSource: RoadSource {
    public let id = "mcdot.centerline"
    public let displayName = "Maricopa County street centerline"

    private let probe: RoadNameProbe
    private let now: @Sendable () -> Date

    public init(probe: RoadNameProbe = RoadNameProbe(service: .maricopa),
                now: @escaping @Sendable () -> Date = Date.init) {
        self.probe = probe
        self.now = now
    }

    public func fetch(_ query: RoadQuery, resolved: RoadRecord) async throws -> RoadFragment {
        var fragment = RoadFragment()
        // Nothing to add if an authoritative source already named the road.
        guard resolved.segmentName == nil else {
            fragment.notes = [note(.skipped, "Already named by "
                                             + (resolved.segmentName?.provenance.sourceName ?? "another source") + ".")]
            return fragment
        }
        guard let hit = await probe.nearestRoad(to: query.coordinate,
                                                within: query.searchRadiusMeters) else {
            fragment.notes = [note(.foundNothing, "No named centreline within "
                                                  + "\(Int(query.searchRadiusMeters)) m.")]
            return fragment
        }
        // The county's centreline does not cover every street — newer subdivisions in the
        // incorporated towns are missing from it. Without this gate it answered with whatever
        // it *did* hold nearby: a pin on E Athena Ave in Gilbert was named E Germann Rd, the
        // arterial 76 m away, because Athena Ave is not in the layer at all. Declining lets
        // TIGER, which has Athena Ave 5.9 m from that pin, name it instead.
        guard RoadProximity.isOnRoad(hit.metresAway) else {
            fragment.notes = [note(.foundNothing, "Nearest centreline here is \(hit.name), "
                                   + "\(Int(hit.metresAway)) m away \u{2014} too far to be the "
                                   + "road at this point.")]
            return fragment
        }

        let url = URL(string: probe.service.url)!
        let provenance = provenance(url: url, fetchedAt: now())
        fragment.segmentName = Attributed(hit.name, provenance: provenance, confidence: .spatial)
        if let classification = hit.classification {
            fragment.classification = Attributed(classification, provenance: provenance,
                                                 confidence: .spatial)
        }
        fragment.notes = [note(.contributed,
                               "\(hit.name), \(Int(hit.metresAway)) m from the pin.")]
        return fragment
    }
}
