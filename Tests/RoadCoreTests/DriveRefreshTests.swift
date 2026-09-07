import Foundation
import CoreLocation
import Testing
@testable import RoadCore
@testable import RoadSources
@testable import RoadUI

/// Serves fixtures, slowly, so a test can look at the screen while a lookup is still running.
/// That is the only way to prove the card does not blank *during* a refresh.
private struct SlowTransport: Transport {
    let inner: FixtureTransport
    let delay: Duration

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await Task.sleep(for: delay)
        return try await inner.data(for: request)
    }
}

@MainActor
private func drivingModel(delay: Duration = .milliseconds(250)) -> RoadLookupModel {
    // No jurisdiction: TIGERweb is refused, so the pipeline falls to the national tier and the
    // probe reads TIGER. Fewer moving parts than standing up a whole county.
    let roads = FixtureTransport(["Transportation/MapServer/8": .fixture("tiger_roads_houston")])
    let client = ArcGISClient(transport: SlowTransport(inner: roads, delay: delay))
    let blind = ArcGISClient(transport: FixtureTransport(["State_County/MapServer/1": .status(503)]))
    return RoadLookupModel(factory: PipelineFactory(client: client),
                           locator: JurisdictionLocator(client: blind),
                           cache: .some(nil))
}

private let houston = CLLocationCoordinate2D(latitude: 29.7604, longitude: -95.3698)
// Far enough to clear DriveTrigger's 250 m staleness rule, so a refresh actually fires.
private let downTheRoad = CLLocationCoordinate2D(latitude: 29.7644, longitude: -95.3698)

@MainActor
@Suite("A drive refresh happens behind the answer")
struct DriveRefreshTests {
    @Test("The card keeps its answer while the next lookup runs")
    func refreshNeverBlanks() async throws {
        // The complaint this exists for: "drive mode is constantly 'Looking' even though I've
        // been on the same road for the last 15 minutes." Drive mode re-resolves about every
        // 250 m and each lookup takes seconds, and `resolve` used to nil `record` first — so
        // the card was blank for much of every drive.
        let model = drivingModel()
        model.setDriving(true)
        await model.identifyOnce(at: houston)
        let firstAnswer = try #require(model.record?.segmentName?.value)

        // The probe runs first and is itself three slow queries, so the wait has to clear it
        // to land inside the refresh rather than ahead of it.
        let refresh = Task { await model.handleDrivingFix(downTheRoad) }
        try await Task.sleep(for: .milliseconds(600))

        #expect(model.isRefreshing, "a lookup really is in progress")
        #expect(model.record?.segmentName?.value == firstAnswer, "the answer stayed on screen")
        // And because `phase` is untouched, the aiming reticle does not flash over the blue dot.
        #expect(model.phase == .resolved)

        await refresh.value
        #expect(model.record != nil)
        #expect(!model.isRefreshing)
    }

    @Test("Looking… is only ever the first answer of a drive")
    func firstAnswerStillSaysLooking() async throws {
        let model = drivingModel()
        model.setDriving(true)
        #expect(model.record == nil)

        let first = Task { await model.identifyOnce(at: houston) }
        try await Task.sleep(for: .milliseconds(80))
        // Nothing true to show yet, so the honest thing is to say it is looking.
        #expect(model.phase == .resolving)
        await first.value
        #expect(model.phase == .resolved)
    }

    @Test("Dropping a pin still clears the screen first")
    func pinDropStillBlanks() async throws {
        // A pin drop is a *new* question and deserves a clean slate — the two paths are
        // deliberately different, which is why this is a separate function rather than a flag.
        let model = drivingModel()
        await model.identifyOnce(at: houston)
        #expect(model.record != nil)

        model.drop(at: downTheRoad)
        try await Task.sleep(for: .milliseconds(80))
        #expect(model.record == nil, "a new question shows nothing until it is answered")
        #expect(model.phase == .resolving)
    }

    @Test("One road driven for a while is one entry in the log")
    func driveLogStaysHonest() async throws {
        let model = drivingModel(delay: .milliseconds(1))
        model.setDriving(true)
        await model.identifyOnce(at: houston)
        for step in 1...5 {
            await model.handleDrivingFix(
                CLLocationCoordinate2D(latitude: houston.latitude + Double(step) * 0.004,
                                       longitude: houston.longitude))
        }
        // Same fixture every time, so it is the same road throughout.
        #expect(model.driveLog.count == 1, "the counter reports roads, not lookups")
    }
}
