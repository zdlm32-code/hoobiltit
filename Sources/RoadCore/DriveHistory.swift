import Foundation

/// One road from a past drive: what the app found out about it, and nothing about where you
/// were on it.
///
/// **No coordinates and no per-road times, deliberately.** History exists so a driver can look
/// back at which roads they drove and who built them. A timestamped trail of positions would be
/// a movement record of the person holding the phone, which is a different thing to keep and
/// not one this app wants to hold. Road names, cities and the trip's own start and end are the
/// useful part.
public struct DrivenRoad: Codable, Hashable, Sendable {
    /// `RoadName.comparisonKey`, so consecutive sightings of one road merge into one entry.
    public var key: String
    public var name: String
    public var between: String?
    public var owner: String?
    public var years: [String]
    /// Why there is no year, when there is none.
    public var dateNote: String?
    public var project: String?
    public var explanation: String?
    public var jurisdiction: String?
    /// "Goodyear, Arizona": where this stretch of the road was first seen.
    public var city: String?

    public init(key: String, name: String, between: String? = nil, owner: String? = nil,
                years: [String] = [], dateNote: String? = nil, project: String? = nil,
                explanation: String? = nil, jurisdiction: String? = nil, city: String? = nil) {
        self.key = key
        self.name = name
        self.between = between
        self.owner = owner
        self.years = years
        self.dateNote = dateNote
        self.project = project
        self.explanation = explanation
        self.jurisdiction = jurisdiction
        self.city = city
    }
}

/// One drive: the roads in the order they were driven, and the cities passed through.
public struct DriveTrip: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var startedAt: Date
    /// When the trip last recorded anything. A trip goes quiet when the car stops, so this is
    /// when it ended, near enough.
    public var lastActiveAt: Date
    /// Oldest first: the order they were driven.
    public var roads: [DrivenRoad]
    /// Oldest first, each listed once per visit. Kept apart from the roads because a highway
    /// crosses three cities without changing its name.
    public var places: [String]

    public init(id: UUID = UUID(), startedAt: Date, lastActiveAt: Date,
                roads: [DrivenRoad] = [], places: [String] = []) {
        self.id = id
        self.startedAt = startedAt
        self.lastActiveAt = lastActiveAt
        self.roads = roads
        self.places = places
    }
}

/// The rules for turning a stream of identified roads into trips. Pure, so they are tested
/// without a file system, a clock or a car.
public enum DriveHistory {
    /// A stop shorter than this continues the same trip: fuel, a drive-through, a long light.
    /// Drive mode itself ends after 45 s at rest, which would split one errand into several.
    public static let tripGap: TimeInterval = 15 * 60
    /// The oldest trips are dropped past this, so the history cannot grow without bound. At a
    /// few drives a day it is most of a year.
    public static let maximumTrips = 1_000

    /// Adds a road to the trip in progress, or starts a new trip if the last one went quiet
    /// more than `tripGap` ago. Trips are newest first.
    ///
    /// The same road twice in a row is one entry, and the later sighting replaces the earlier
    /// one: it comes from the drive log's own merge, which keeps whichever answer knows more.
    /// Its city does not replace the first one, though — that is where the road was joined.
    public static func recording(_ road: DrivenRoad, place: String?, at now: Date,
                                 in trips: [DriveTrip]) -> [DriveTrip] {
        var trips = trips
        if trips.first.map({ now.timeIntervalSince($0.lastActiveAt) >= tripGap }) ?? true {
            trips.insert(DriveTrip(startedAt: now, lastActiveAt: now), at: 0)
        }
        var trip = trips[0]
        if let last = trip.roads.last, last.key == road.key {
            var merged = road
            merged.city = last.city ?? road.city
            trip.roads[trip.roads.count - 1] = merged
        } else {
            trip.roads.append(road)
        }
        if let place { trip.places = noting(place, in: trip.places) }
        trip.lastActiveAt = now
        trips[0] = trip
        return Array(trips.prefix(maximumTrips))
    }

    /// Records a city crossed in the trip in progress. Never starts a trip by itself: a city
    /// with no road driven in it is not a drive.
    public static func notingPlace(_ place: String, at now: Date,
                                   in trips: [DriveTrip]) -> [DriveTrip] {
        guard var trip = trips.first, now.timeIntervalSince(trip.lastActiveAt) < tripGap
        else { return trips }
        trip.places = noting(place, in: trip.places)
        trip.lastActiveAt = now
        var trips = trips
        trips[0] = trip
        return trips
    }

    /// Applies today's ownership rules to roads saved under older ones.
    ///
    /// Saved roads keep no coordinates, so they cannot be looked up again. What can be done is
    /// to stop showing an owner a newer build would have withheld: an inferred owner on a road
    /// that is a highway by its own name — the "Pima Fwy, City of Phoenix (inferred)" that
    /// `RoadRecord.withholdImplausibleOwner` now prevents.
    public static func repaired(_ trips: [DriveTrip]) -> [DriveTrip] {
        trips.map { trip in
            var trip = trip
            trip.roads = trip.roads.map { road in
                guard let owner = road.owner, owner.hasSuffix(" (inferred)"),
                      HighwayName.isNotTheCitys(road.name) else { return road }
                var road = road
                road.owner = nil
                return road
            }
            return trip
        }
    }

    private static func noting(_ place: String, in places: [String]) -> [String] {
        places.last == place ? places : places + [place]
    }
}

public extension DriveTrip {
    /// "Goodyear → Avondale → Phoenix". The state is dropped when every city shares it, since a
    /// trip that never leaves Arizona does not need to say so three times. "Unincorporated
    /// Maricopa County" names no state and does not count against that.
    var routeSummary: String? {
        guard !places.isEmpty else { return nil }
        let parts = places.map { place -> (name: String, state: String?) in
            guard let comma = place.range(of: ", ") else { return (place, nil) }
            return (String(place[..<comma.lowerBound]), String(place[comma.upperBound...]))
        }
        let names = Set(parts.compactMap(\.state)).count <= 1 ? parts.map(\.name) : places
        return names.joined(separator: " \u{2192} ")
    }

    var roadCountLabel: String {
        roads.count == 1 ? "1 road" : "\(roads.count) roads"
    }

    /// "roads-2026-10-25.csv": the day it started, so exports from different drives do not all
    /// arrive with the same name.
    var exportFileName: String {
        // In the phone's own time zone: ISO 8601 formatting defaults to UTC, which dates an
        // evening drive in Arizona to the next day.
        let day = startedAt.formatted(Date.ISO8601FormatStyle(timeZone: .current).year().month().day())
        return "roads-\(day).csv"
    }
}
