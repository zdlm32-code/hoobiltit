import Foundation
import Testing
@testable import RoadCore

private func report(lat: Double = 33.689441, lon: Double = -112.317668,
                    note: String? = "deep one in the right lane, past the light",
                    at when: Date = Date(timeIntervalSince1970: 1_757_012_345)) -> RoadReport {
    RoadReport(coordinate: Coordinate(latitude: lat, longitude: lon),
               createdAt: when,
               rating: .veryPoor,
               issue: .pavement,
               note: note,
               roadName: "Williams Dr",
               crossStreets: "El Mirage Rd to Deer Valley Rd",
               maintainedBy: "Maricopa County DOT",
               jurisdiction: "Unincorporated Maricopa County",
               segmentIdentifier: "41028",
               countyRating: .good)
}

@Suite("What a shared report gives away")
struct PooledReportRedactionTests {
    @Test("The note never leaves the device")
    func dropsTheNote() {
        // The only free text in the app. Keeping it private is most of the moderation problem
        // solved by construction — and this test is what stops a later refactor putting it back.
        let pooled = PooledReport(from: report())
        let published = pooled.fields.values.compactMap(\.text).joined(separator: " ")
        #expect(!published.contains("right lane"))
        #expect(!published.lowercased().contains("past the light"))
        #expect(pooled.fields["note"] == nil)
    }

    @Test("Cross streets are dropped too, because they re-sharpen the location")
    func dropsCrossStreets() {
        let published = PooledReport(from: report()).fields.values.compactMap(\.text)
        #expect(!published.contains { $0.contains("El Mirage") })
    }

    @Test("The coordinate is published at about 100 m, not the cache's 11 m")
    func roundsTheCoordinate() {
        // 11 m is house-level. The cache rounds there for correctness — so one key cannot cover
        // two roads — and that reasoning does not carry to a permanent public record.
        let pooled = PooledReport(from: report(lat: 33.689441, lon: -112.317668))
        #expect(pooled.coordinate.latitude == 33.689)
        #expect(pooled.coordinate.longitude == -112.318)
        #expect(PooledReport.publishedDecimalPlaces < CacheKey.decimalPlaces)
    }

    @Test("Rounding goes to the nearest cell, not always downwards")
    func roundsRatherThanTruncates() {
        let up = PooledReport(from: report(lat: 33.6899, lon: -112.3179))
        #expect(up.coordinate.latitude == 33.690)
        #expect(up.coordinate.longitude == -112.318)
    }

    @Test("The time is published to the day")
    func roundsTheTimestamp() {
        // 100 m plus a millisecond timestamp is a movement trace; enough of them is a commute.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Phoenix")!
        let pooled = PooledReport(from: report(), calendar: calendar)
        #expect(calendar.dateComponents([.hour, .minute, .second], from: pooled.reportedOn)
                == DateComponents(hour: 0, minute: 0, second: 0))
    }

    @Test("Exactly the documented fields are published, and no others")
    func publishesOnlyTheDocumentedFields() {
        // A field added to `RoadReport` cannot leak into the pool by being forgotten about.
        #expect(Set(PooledReport(from: report()).fields.keys) == PooledReport.Field.all)
    }
}

@Suite("Reading the pool back")
struct PooledReportDecodingTests {
    @Test("Every rating and issue survives the round trip")
    func vocabularyRoundTrips() {
        // Mirrors ReportTests.categoriesAreReal: the vocabularies are the contract.
        for rating in [ConditionRating.veryPoor, .poor, .fair, .good, .veryGood] {
            for issue in RoadIssue.allCases {
                let original = PooledReport(id: UUID(),
                                            coordinate: Coordinate(latitude: 33.689, longitude: -112.318),
                                            rating: rating, issue: issue,
                                            reportedOn: Date(timeIntervalSince1970: 1_757_000_000))
                let decoded = PooledReport(fields: original.fields, id: original.id)
                #expect(decoded?.rating == rating)
                #expect(decoded?.issue == issue)
            }
        }
    }

    @Test("A value from a future version is dropped, not crashed on")
    func unknownVocabularyIsDropped() {
        // A later release adding a RoadIssue case will publish records this build cannot read.
        // The map should draw what it understands and ignore the rest — this is what stops a
        // v1.1 release breaking v1.0's map.
        var fields = PooledReport(from: report()).fields
        fields[PooledReport.Field.issue] = .text("signage")
        #expect(PooledReport(fields: fields, id: UUID()) == nil)
    }

    @Test("An unknown county rating loses only itself")
    func unknownCountyRatingIsNotFatal() {
        // It is context, not the claim, so it must not take the whole record down with it.
        var fields = PooledReport(from: report()).fields
        fields[PooledReport.Field.countyRating] = .text("Immaculate")
        let decoded = PooledReport(fields: fields, id: UUID())
        #expect(decoded != nil)
        #expect(decoded?.countyRating == nil)
    }

    @Test("A record missing what it needs is refused")
    func incompleteRecordIsRefused() {
        var fields = PooledReport(from: report()).fields
        fields[PooledReport.Field.latitude] = nil
        #expect(PooledReport(fields: fields, id: UUID()) == nil)
    }
}

@Suite("The grid the pool is queried by")
struct PoolCellTests {
    @Test("A cell is about a kilometre, and the same point always lands in the same one")
    func cellsAreStable() {
        let a = PoolCell(Coordinate(latitude: 33.6894, longitude: -112.3177))
        let b = PoolCell(Coordinate(latitude: 33.6912, longitude: -112.3169))
        #expect(a == b, "points a couple of hundred metres apart share a cell")
        #expect(a.identifier == "33.69,-112.32")
    }

    @Test("A viewport resolves to the cells it touches")
    func coveringAViewport() {
        let cells = PoolCell.covering(centre: Coordinate(latitude: 33.69, longitude: -112.32),
                                      span: MapSpan(latitudeDelta: 0.01, longitudeDelta: 0.01))
        let found = try? #require(cells)
        #expect((found?.count ?? 0) >= 4)
        #expect(found?.contains(PoolCell(Coordinate(latitude: 33.69, longitude: -112.32))) == true)
    }

    @Test("A viewport too wide to query says so rather than asking for the county")
    func refusesAnEnormousViewport() {
        // The same instinct as the parcel overlay's zoom gate: decline honestly rather than issue
        // a query nobody wants to pay for.
        #expect(PoolCell.covering(centre: Coordinate(latitude: 33.69, longitude: -112.32),
                                  span: MapSpan(latitudeDelta: 5, longitudeDelta: 5)) == nil)
    }

    @Test("A tiny viewport still yields at least one cell")
    func tinyViewport() {
        let cells = PoolCell.covering(centre: Coordinate(latitude: 33.6894, longitude: -112.3177),
                                      span: MapSpan(latitudeDelta: 0.0001, longitudeDelta: 0.0001))
        #expect((cells?.isEmpty == false))
    }

    @Test("Cells are unique")
    func noDuplicates() {
        let cells = PoolCell.covering(centre: Coordinate(latitude: 33.69, longitude: -112.32),
                                      span: MapSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)) ?? []
        #expect(Set(cells).count == cells.count)
    }
}

@Suite("The pool as the app uses it")
struct PoolStoreTests {
    private func pooled(_ id: UUID = UUID(), lat: Double = 33.689, lon: Double = -112.318,
                        rating: ConditionRating = .veryPoor) -> PooledReport {
        PooledReport(id: id, coordinate: Coordinate(latitude: lat, longitude: lon),
                     rating: rating, issue: .pavement,
                     reportedOn: Date(timeIntervalSince1970: 1_757_000_000))
    }

    @Test("A published report comes back for the cell it is in, and not for others")
    func publishAndFetch() async throws {
        let pool = MemoryPool()
        let report = pooled()
        try await pool.publish(report)

        let here = try await pool.reports(in: [report.cell])
        #expect(here.map(\.id) == [report.id])

        let elsewhere = try await pool.reports(
            in: [PoolCell(Coordinate(latitude: 42.36, longitude: -71.06))])
        #expect(elsewhere.isEmpty)
    }

    @Test("Withdrawing a report removes it from the pool")
    func retract() async throws {
        let pool = MemoryPool()
        let report = pooled()
        try await pool.publish(report)
        try await pool.retract(id: report.id)
        #expect(try await pool.reports(in: [report.cell]).isEmpty)
    }

    @Test("A failure is thrown so the map can say so, not swallowed")
    func failuresSurface() async throws {
        // The app's rule: a partial answer is normal, a failure is disclosed. A pool that
        // returned an empty array on error would be indistinguishable from a road nobody has
        // reported.
        let pool = MemoryPool()
        await pool.setFailNext(.offline)
        await #expect(throws: PoolFailure.offline) {
            try await pool.reports(in: [PoolCell(Coordinate(latitude: 33.689, longitude: -112.318))])
        }
    }

    @Test("Every failure has something the driver can read")
    func failuresAreLegible() {
        for failure: PoolFailure in [.offline, .rateLimited(retryAfter: 30), .notSignedIn,
                                     .misconfigured("x"), .unknown("y")] {
            #expect(!failure.message.isEmpty)
            // Never leaks a raw error string or blames the user for something that is not theirs.
            #expect(!failure.message.contains("Error"))
            #expect(!failure.message.contains("CKError"))
        }
    }

    @Test("Flags accumulate, and enough of them hide a marker")
    func flagging() async throws {
        let pool = MemoryPool()
        let report = pooled()
        try await pool.publish(report)
        for _ in 0..<PoolLimits.flagsToHide { try await pool.flag(id: report.id) }
        let counts = try await pool.flagCounts(in: [report.cell])
        #expect(counts[report.id] == PoolLimits.flagsToHide)
        // One person disagreeing is not enough to silence a report.
        #expect(PoolLimits.flagsToHide > 1)
    }

    @Test("Signed out means you cannot contribute, not that you cannot look")
    func readingDoesNotNeedAnAccount() async throws {
        // The public database is readable without an iCloud account. Gating reads on the account
        // check is the mistake that shows a signed-out user an empty map.
        let pool = MemoryPool(contributes: false)
        try await pool.publish(pooled())
        #expect(await pool.canContribute() == false)
        #expect(try await pool.reports(
            in: [PoolCell(Coordinate(latitude: 33.689, longitude: -112.318))]).count == 1)
    }
}
