import Foundation

/// The grid square a shared report is filed under, and the only spatial key the pool is queried by.
///
/// CloudKit does offer a location predicate, `distanceToLocation:fromLocation:`. It is not usable
/// here: Apple documents its index resolution as **no less than 10 km**, it forbids `NOT`, and its
/// radius unit is given as kilometres in the sample code and reported as metres by developers who
/// have measured it. It would also send the user's exact position to Apple on every map settle,
/// which is the wrong shape for an app whose whole premise is that lookups go device-to-agency.
///
/// A rounded cell is the `CacheKey` idea one order of magnitude coarser. It is exact, it indexes
/// cleanly as a string, and what travels is a ~1 km grid identifier rather than a position.
public struct PoolCell: Sendable, Hashable, Codable {
    public let identifier: String

    /// ~1.1 km. Coarse enough that a viewport is a handful of cells, fine enough that a query
    /// does not drag in a whole city.
    public static let decimalPlaces = 2.0
    /// Past this a viewport needs more cells than one query should carry, and the map says
    /// "zoom in" instead — the same instinct as the parcel overlay's zoom gate.
    public static let coveringLimit = 24

    public init(_ coordinate: Coordinate) {
        let rounded = coordinate.rounded(toDecimalPlaces: Self.decimalPlaces)
        self.identifier = String(format: "%.2f,%.2f", rounded.latitude, rounded.longitude)
    }

    public init(identifier: String) {
        self.identifier = identifier
    }

    /// Every cell a viewport touches, or nil when that is more than `coveringLimit`.
    ///
    /// Inclusive of the edges: a report sitting exactly on a boundary belongs to a cell the
    /// viewport can see, and dropping it would make markers wink out at particular zooms.
    public static func covering(centre: Coordinate, span: MapSpan,
                                limit: Int = coveringLimit) -> [PoolCell]? {
        let step = pow(10, -decimalPlaces)
        let halfLat = max(span.latitudeDelta, step) / 2
        let halfLon = max(span.longitudeDelta, step) / 2

        let minLat = ((centre.latitude - halfLat) / step).rounded(.down) * step
        let maxLat = ((centre.latitude + halfLat) / step).rounded(.up) * step
        let minLon = ((centre.longitude - halfLon) / step).rounded(.down) * step
        let maxLon = ((centre.longitude + halfLon) / step).rounded(.up) * step

        let rows = Int(((maxLat - minLat) / step).rounded()) + 1
        let columns = Int(((maxLon - minLon) / step).rounded()) + 1
        guard rows > 0, columns > 0, rows * columns <= limit else { return nil }

        var cells: [PoolCell] = []
        for row in 0..<rows {
            for column in 0..<columns {
                cells.append(PoolCell(Coordinate(latitude: minLat + Double(row) * step,
                                                 longitude: minLon + Double(column) * step)))
            }
        }
        // Deduplicated: rounding at the edges can land two steps on one cell.
        var seen = Set<String>()
        return cells.filter { seen.insert($0.identifier).inserted }
    }
}
