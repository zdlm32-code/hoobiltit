import Foundation

/// The roads identified on this drive, newest first.
///
/// Kept as a pure function rather than as mutation inside the view model so the collapsing rule
/// can be tested without a location manager or a network.
///
/// The rule exists because drive mode re-resolves roughly every 250 m whether or not the road
/// has changed — deliberately, so a stale answer cannot persist down a long road. Appending
/// every result unfiltered therefore records one five-mile arterial about thirty-two times, and
/// the "N roads" counter on the card becomes meaningless. Consecutive results for the same road
/// are one entry.
public enum DriveLog {
    /// Adds `record` to `log`, or merges it into the newest entry when it is the same road.
    ///
    /// Merging keeps whichever version knows more. A refresh further along the same road can
    /// pick up a project or a plat the first lookup missed — sources fail independently and a
    /// dead endpoint is retried on the next pass — so the last answer is not reliably the best
    /// one, and neither is the first.
    public static func appending(_ record: RoadRecord, to log: [RoadRecord]) -> [RoadRecord] {
        // A record naming no road says nothing worth logging.
        guard let key = identity(of: record) else { return log }

        guard let newest = log.first, identity(of: newest) == key else {
            return [record] + log
        }
        return [richer(newest, record)] + log.dropFirst()
    }

    /// How a road is recognised as the same one seen a moment ago.
    ///
    /// Name rather than any segment identifier: no two sources share a segment id, and a long
    /// road is many segments, so ids would split one road into dozens of entries — the very
    /// thing this is here to prevent.
    static func identity(of record: RoadRecord) -> String? {
        let name = record.segmentName?.value ?? record.routeDesignation?.value
        return name.map { RoadName.comparisonKey($0) }
    }

    static func richer(_ lhs: RoadRecord, _ rhs: RoadRecord) -> RoadRecord {
        detailCount(rhs) > detailCount(lhs) ? rhs : lhs
    }

    /// How much a record actually says. Only fields a reader would notice are counted; notes
    /// and coverage are about the lookup, not about the road.
    public static func detailCount(_ record: RoadRecord) -> Int {
        var count = 0
        for present in [record.segmentName != nil, record.routeDesignation != nil,
                        record.owner != nil, record.jurisdiction != nil,
                        record.classification != nil, record.crossStreets != nil,
                        record.surface != nil, record.trafficCount != nil,
                        record.yearLastConstruction != nil, record.yearLastImprovement != nil,
                        record.project != nil, record.lastKnownImprovement != nil,
                        record.plat != nil, record.plattedDate != nil,
                        record.declaration != nil, record.acquisition != nil,
                        record.bridge != nil, record.parcel != nil, record.funding != nil] {
            if present { count += 1 }
        }
        return count
    }
}
