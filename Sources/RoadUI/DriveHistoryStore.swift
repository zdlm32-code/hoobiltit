import Foundation
import Observation
import RoadCore

/// Past drives, kept on this device.
///
/// One small JSON file per trip in Application Support, so recording a road rewrites only the
/// trip in progress. A single file for the whole history would rewrite a year of drives every
/// time drive mode re-resolved, roughly every 250 m.
///
/// Never sent anywhere, and nothing in it is a coordinate — see `DrivenRoad` for why. The files
/// are ordinary app data, so they go wherever the user's own device backups go and nowhere else.
@MainActor
@Observable
public final class DriveHistoryStore {
    /// Newest first.
    public private(set) var trips: [DriveTrip] = []
    @ObservationIgnored private let directory: URL?

    /// - Parameter directory: where trip files live. Nil keeps history in memory only, which is
    ///   what tests use, so a test run never writes into the developer's Application Support.
    public init(directory: URL?) {
        self.directory = directory
        trips = DriveHistory.repaired(Self.load(from: directory))
    }

    /// The app's real history.
    public static func onDevice() -> DriveHistoryStore {
        let support = FileManager.default.urls(for: .applicationSupportDirectory,
                                               in: .userDomainMask).first
        return DriveHistoryStore(directory: support?.appendingPathComponent("DriveHistory",
                                                                            isDirectory: true))
    }

    /// Adds the road the drive log just settled on. `record` should be the log's newest entry,
    /// which already carries the log's merge of repeated sightings.
    public func record(_ record: RoadRecord, city: String?, at now: Date = Date()) {
        guard let road = DrivenRoad(record: record, city: city) else { return }
        update(DriveHistory.recording(road, place: city, at: now, in: trips))
    }

    public func notePlace(_ place: String, at now: Date = Date()) {
        update(DriveHistory.notingPlace(place, at: now, in: trips))
    }

    public func delete(_ id: DriveTrip.ID) {
        trips.removeAll { $0.id == id }
        removeFile(for: id)
    }

    public func deleteAll() {
        let ids = trips.map(\.id)
        trips = []
        ids.forEach(removeFile)
    }

    /// Only the newest trip changes when a road or a place is recorded, so only it is written.
    /// Trips pushed past `DriveHistory.maximumTrips` lose their files here too.
    private func update(_ next: [DriveTrip]) {
        let kept = Set(next.map(\.id))
        let dropped = trips.filter { !kept.contains($0.id) }
        trips = next
        if let current = next.first { write(current) }
        dropped.forEach { removeFile(for: $0.id) }
    }

    private func url(for id: DriveTrip.ID) -> URL? {
        directory?.appendingPathComponent("\(id.uuidString).json")
    }

    private func write(_ trip: DriveTrip) {
        guard let directory, let url = url(for: trip.id) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? Self.encoder.encode(trip) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private func removeFile(for id: DriveTrip.ID) {
        guard let url = url(for: id) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// A file that does not decode is skipped rather than failing the whole history.
    private static func load(from directory: URL?) -> [DriveTrip] {
        guard let directory,
              let files = try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil)
        else { return [] }
        return files.filter { $0.pathExtension == "json" }
            .compactMap { try? Data(contentsOf: $0) }
            .compactMap { try? decoder.decode(DriveTrip.self, from: $0) }
            .sorted { $0.startedAt > $1.startedAt }
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

extension DrivenRoad {
    /// What history keeps of a lookup: the finished strings the drive log shows, and none of
    /// the record's coordinates. Nil for a record that names no road, which the drive log does
    /// not keep either.
    init?(record: RoadRecord, city: String?) {
        let content = DriveCardContent(record: record)
        guard let key = content.key, let name = content.roadName else { return nil }
        let project = record.project?.value ?? record.lastKnownImprovement?.value
        self.init(key: key, name: name,
                  between: record.crossStreets?.value,
                  owner: content.owner,
                  years: content.years,
                  dateNote: content.dateNote,
                  project: project.map(SegmentCard.describe),
                  explanation: record.coverage?.explanation(for: record),
                  jurisdiction: record.jurisdiction?.value,
                  city: city)
    }
}
