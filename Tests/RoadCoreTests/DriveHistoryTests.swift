import Foundation
import Testing
@testable import RoadCore
@testable import RoadUI

private func road(_ name: String, city: String? = nil, owner: String? = nil) -> DrivenRoad {
    DrivenRoad(key: RoadName.comparisonKey(name), name: name, owner: owner, city: city)
}

private let start = Date(timeIntervalSince1970: 1_790_000_000)

private func minutes(_ m: Double) -> Date { start.addingTimeInterval(m * 60) }

@Suite("Drives become trips")
struct DriveHistoryTests {
    @Test("Roads are kept in the order they were driven")
    func drivingOrder() {
        var trips: [DriveTrip] = []
        trips = DriveHistory.recording(road("Williams Dr"), place: nil, at: minutes(0), in: trips)
        trips = DriveHistory.recording(road("Bullard Ave"), place: nil, at: minutes(2), in: trips)
        #expect(trips.count == 1)
        #expect(trips[0].roads.map(\.name) == ["Williams Dr", "Bullard Ave"])
        #expect(trips[0].startedAt == minutes(0))
        #expect(trips[0].lastActiveAt == minutes(2))
    }

    @Test("One road driven for a while is one entry, joined where it was joined")
    func sameRoadMerges() {
        var trips: [DriveTrip] = []
        trips = DriveHistory.recording(road("I-10", city: "Goodyear, Arizona"),
                                       place: "Goodyear, Arizona", at: minutes(0), in: trips)
        // The drive log's merge has learned the owner by now; the city is further on.
        trips = DriveHistory.recording(road("I-10", city: "Avondale, Arizona", owner: "ADOT"),
                                       place: "Avondale, Arizona", at: minutes(4), in: trips)
        #expect(trips[0].roads.count == 1)
        #expect(trips[0].roads[0].owner == "ADOT", "the later, richer sighting is kept")
        #expect(trips[0].roads[0].city == "Goodyear, Arizona", "but not its city")
        #expect(trips[0].places == ["Goodyear, Arizona", "Avondale, Arizona"])
    }

    @Test("A short stop continues the trip; a long one starts the next")
    func tripGap() {
        var trips: [DriveTrip] = []
        trips = DriveHistory.recording(road("Williams Dr"), place: nil, at: minutes(0), in: trips)
        // Fuel, or a long light: drive mode itself ends after 45 s at rest, the trip does not.
        trips = DriveHistory.recording(road("Bullard Ave"), place: nil, at: minutes(14), in: trips)
        #expect(trips.count == 1)
        trips = DriveHistory.recording(road("Van Buren St"), place: nil, at: minutes(30), in: trips)
        #expect(trips.count == 2)
        #expect(trips[0].roads.map(\.name) == ["Van Buren St"], "newest trip first")
        #expect(trips[1].roads.count == 2)
    }

    @Test("Crossing a city is noted, but a city alone is not a drive")
    func places() {
        #expect(DriveHistory.notingPlace("Phoenix, Arizona", at: minutes(0), in: []).isEmpty)

        var trips = DriveHistory.recording(road("I-10"), place: "Goodyear, Arizona",
                                           at: minutes(0), in: [])
        trips = DriveHistory.notingPlace("Avondale, Arizona", at: minutes(3), in: trips)
        trips = DriveHistory.notingPlace("Avondale, Arizona", at: minutes(4), in: trips)
        #expect(trips[0].places == ["Goodyear, Arizona", "Avondale, Arizona"])
        #expect(trips[0].lastActiveAt == minutes(4))
        // Long after the trip ended, a city does not reopen it.
        let later = DriveHistory.notingPlace("Phoenix, Arizona", at: minutes(60), in: trips)
        #expect(later == trips)
    }

    @Test("History is bounded")
    func bounded() {
        var trips: [DriveTrip] = []
        for i in 0..<(DriveHistory.maximumTrips + 5) {
            trips = DriveHistory.recording(road("Williams Dr"), place: nil,
                                           at: minutes(Double(i) * 60), in: trips)
        }
        #expect(trips.count == DriveHistory.maximumTrips)
        #expect(trips[0].startedAt == minutes(Double(DriveHistory.maximumTrips + 4) * 60))
    }

    @Test("A saved guess that a newer build would withhold is not shown")
    func repairsSavedInferences() {
        let saved = DriveTrip(startedAt: start, lastActiveAt: start, roads: [
            road("Pima Fwy", owner: "City of Phoenix (inferred)"),
            road("N Tatum Blvd", owner: "City of Phoenix (inferred)"),
            road("SR-101", owner: "Arizona Department of Transportation"),
        ])
        let owners = DriveHistory.repaired([saved])[0].roads.map(\.owner)
        #expect(owners == [nil, "City of Phoenix (inferred)", "Arizona Department of Transportation"])
    }

    @Test("The route reads like a route")
    func routeSummary() {
        func trip(_ places: [String]) -> DriveTrip {
            DriveTrip(startedAt: start, lastActiveAt: start, places: places)
        }
        #expect(trip(["Goodyear, Arizona", "Unincorporated Maricopa County", "Avondale, Arizona"])
            .routeSummary == "Goodyear \u{2192} Unincorporated Maricopa County \u{2192} Avondale")
        #expect(trip(["Yuma, Arizona", "Winterhaven, California"]).routeSummary
            == "Yuma, Arizona \u{2192} Winterhaven, California", "a state line is worth saying")
        #expect(trip([]).routeSummary == nil)
    }

    @Test("What is saved names roads, never positions")
    @MainActor
    func savedHistoryHasNoCoordinates() throws {
        var record = RoadRecord(query: RoadQuery(latitude: 33.689441, longitude: -112.317668))
        let provenance = Provenance(sourceID: "t", sourceName: "Test",
                                    url: URL(string: "https://example.org")!, fetchedAt: Date())
        record.segmentName = Attributed("Williams Dr", provenance: provenance)
        let store = DriveHistoryStore(directory: nil)
        store.record(record, city: "Waddell, Arizona", at: start)

        let json = String(decoding: try JSONEncoder().encode(store.trips), as: UTF8.self)
        #expect(json.contains("Williams Dr"))
        #expect(!json.contains("33.68"), "the query's latitude")
        #expect(!json.contains("112.31"), "the query's longitude")
        #expect(json.firstMatch(of: /-?\d{1,3}\.\d{4,}/) == nil)
        #expect(!json.lowercased().contains("latitude"))
    }
}

@Suite("Past drives survive the app closing")
@MainActor
struct DriveHistoryStoreTests {
    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("DriveHistoryTests-\(UUID().uuidString)", isDirectory: true)
    }

    private func named(_ name: String) -> RoadRecord {
        var record = RoadRecord(query: RoadQuery(latitude: 33.68, longitude: -112.31))
        record.segmentName = Attributed(name, provenance: Provenance(
            sourceID: "t", sourceName: "Test", url: URL(string: "https://example.org")!,
            fetchedAt: Date()))
        return record
    }

    @Test("A reopened app finds the drives it recorded")
    func roundTrip() {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = DriveHistoryStore(directory: directory)
        store.record(named("Williams Dr"), city: "Waddell, Arizona", at: start)
        store.record(named("Bullard Ave"), city: "Goodyear, Arizona", at: minutes(3))
        store.record(named("Van Buren St"), city: "Phoenix, Arizona", at: minutes(90))

        let reopened = DriveHistoryStore(directory: directory)
        #expect(reopened.trips == store.trips)
        #expect(reopened.trips.map(\.roads.count) == [1, 2])
    }

    @Test("Deleting a drive deletes it from disk")
    func deleteRemovesTheFile() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = DriveHistoryStore(directory: directory)
        store.record(named("Williams Dr"), city: nil, at: start)
        store.record(named("Van Buren St"), city: nil, at: minutes(90))
        store.delete(try #require(store.trips.last).id)
        #expect(DriveHistoryStore(directory: directory).trips.count == 1)

        store.deleteAll()
        #expect(DriveHistoryStore(directory: directory).trips.isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }

    @Test("A record that names no road is not a drive")
    func namelessRecordIsSkipped() {
        let store = DriveHistoryStore(directory: nil)
        store.record(RoadRecord(query: RoadQuery(latitude: 33.68, longitude: -112.31)),
                     city: "Goodyear, Arizona", at: start)
        #expect(store.trips.isEmpty)
    }
}
