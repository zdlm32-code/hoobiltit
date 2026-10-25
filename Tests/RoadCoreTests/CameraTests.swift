import Foundation
import Testing
@testable import RoadCore

@Suite("Who moved the camera")
struct CameraChangeTests {
    /// The follow zoom: MapKit yields about this span at the app's 420 m follow distance.
    private let span = MapSpan(latitudeDelta: 0.0058, longitudeDelta: 0.0058)
    private let centre = Coordinate(latitude: 33.4340, longitude: -112.4009)

    private func moved(_ metres: Double) -> Coordinate {
        Coordinate(latitude: centre.latitude + metres / 111_320, longitude: centre.longitude)
    }

    @Test("Aiming at a road 100 m away ends the follow")
    func smallPanEndsFollowing() {
        // The old rule allowed 226 m of drift at this zoom, so this exact case kept following,
        // the next fix snapped the camera back, and Identify resolved the device instead.
        let change = Geo.classifyCameraChange(from: span, previousCentre: centre,
                                              to: span, currentCentre: moved(100))
        #expect(change == .panned)
    }

    @Test("Even a 20 m nudge counts as aiming")
    func tinyPanStillCounts() {
        #expect(Geo.classifyCameraChange(from: span, previousCentre: centre,
                                         to: span, currentCentre: moved(20)) == .panned)
    }

    @Test("A pinch keeps the follow and yields the new distance")
    func zoomKeepsFollowing() {
        let zoomedOut = MapSpan(latitudeDelta: 0.0116, longitudeDelta: 0.0116)
        #expect(Geo.classifyCameraChange(from: span, previousCentre: centre,
                                         to: zoomedOut, currentCentre: centre) == .zoomed)
    }

    @Test("The app's own moves are excluded by time, not by geometry")
    func programmaticWindowIsGenerous() {
        // An animated programmatic move emits intermediate changes that land nowhere near the
        // requested centre. Matching on position classified those as pans and switched
        // follow-on-launch off before the camera had finished arriving, leaving the map at the
        // county view with the road already identified.
        #expect(Geo.programmaticSettleWindow >= 1.0)
    }

    @Test("Float noise is neither a pan nor a zoom")
    func negligible() {
        #expect(Geo.classifyCameraChange(from: span, previousCentre: centre,
                                         to: span, currentCentre: moved(1)) == .negligible)
    }

    @Test("A follow move reported late is still the app's own")
    func lateFollowMoveIsNotAPan() {
        // The reproduction: back in the app after a few seconds away, the map caught up 160 m
        // to the car and MapKit reported it 1.54 s after `follow()` — past the settle window.
        // Read as a pan, it switched following off for the rest of the drive.
        let target = moved(160)
        #expect(Geo.classifyCameraChange(from: span, previousCentre: centre,
                                         to: span, currentCentre: target,
                                         followTarget: target) == .negligible)
        // An ordinary 25-40 m fix-to-fix move, late, with a little float noise on arrival.
        #expect(Geo.classifyCameraChange(from: span, previousCentre: centre,
                                         to: span, currentCentre: moved(43),
                                         followTarget: moved(40)) == .negligible)
    }

    @Test("Panning away from where the app put the camera still ends the follow")
    func panAwayFromTargetStillCounts() {
        #expect(Geo.classifyCameraChange(from: span, previousCentre: centre,
                                         to: span, currentCentre: moved(60),
                                         followTarget: centre) == .panned)
    }

    @Test("A pinch on the follow target is still a zoom")
    func zoomOnTargetIsAZoom() {
        let zoomedOut = MapSpan(latitudeDelta: 0.0116, longitudeDelta: 0.0116)
        #expect(Geo.classifyCameraChange(from: span, previousCentre: centre,
                                         to: zoomedOut, currentCentre: centre,
                                         followTarget: centre) == .zoomed)
    }

    @Test("A pinch while following keeps following, however far it drags the centre")
    func pinchKeepsFollowing() {
        // From the road: pinching out at 60 mph took the camera from 0.8 km to 3.3 km and, because
        // MapKit zooms around the fingers, dragged the centre 164 m off the car.
        let zoomedOut = MapSpan(latitudeDelta: 0.0232, longitudeDelta: 0.0232)
        #expect(Geo.classifyCameraChange(from: span, previousCentre: centre,
                                         to: zoomedOut, currentCentre: moved(164),
                                         followTarget: centre, userZoomed: true) == .zoomed)
    }

    @Test("A drag that leaves the zoom alone still ends the follow")
    func dragStillEndsFollowing() {
        #expect(Geo.classifyCameraChange(from: span, previousCentre: centre,
                                         to: span, currentCentre: moved(164),
                                         followTarget: centre, userZoomed: false) == .panned)
    }

    @Test("Not following, a pan wins over a simultaneous zoom")
    func panBeatsZoom() {
        // On geometry alone, moving and zooming at once is still a pan. Only a known zoom
        // gesture while following overrides that — see `pinchKeepsFollowing`.
        let zoomedOut = MapSpan(latitudeDelta: 0.0116, longitudeDelta: 0.0116)
        #expect(Geo.classifyCameraChange(from: span, previousCentre: centre,
                                         to: zoomedOut, currentCentre: moved(150)) == .panned)
    }
}

@Suite("Scale bar")
struct ScaleBarTests {
    @Test("Picks round numbers a person would recognise")
    func roundNumbers() {
        for metres in [15.0, 40.0, 150.0, 400.0, 1500.0, 8000.0, 30000.0] {
            let label = Geo.scaleBarDistance(fitting: metres).label
            let digits = label.filter(\.isNumber)
            // "½" is a numeric character, and "½ mi" is a perfectly ordinary scale label.
            #expect(["½", "1", "2", "5", "10", "20", "50", "100", "200", "500", "1000", "2000"]
                        .contains(digits), "\(metres) m gave \(label)")
        }
    }

    @Test("Never exceeds the width it was asked to fit")
    func fitsInside() {
        for metres in [12.0, 90.0, 700.0, 5000.0, 40000.0] {
            #expect(Geo.scaleBarDistance(fitting: metres).metres <= metres + 0.001,
                    "\(metres) m overflowed")
        }
    }

    @Test("Switches from feet to miles at a sensible point")
    func units() {
        #expect(Geo.scaleBarDistance(fitting: 100).label.hasSuffix("ft"))
        #expect(Geo.scaleBarDistance(fitting: 20_000).label.hasSuffix("mi"))
    }

    @Test("A degenerate span still yields something drawable")
    func degenerate() {
        let tiny = Geo.scaleBarDistance(fitting: 0.5)
        #expect(tiny.metres > 0)
        #expect(!tiny.label.isEmpty)
    }
}

@Suite("Follow distance")
struct FollowDistanceTests {
    @Test("A county-overview zoom cannot become the follow distance")
    func clampsAbsurdValues() {
        // Measured from the real failure: the camera sat at the county fallback and its
        // 337 km distance was adopted as the follow distance, so the map never zoomed to the
        // device even though the road under it resolved fine.
        #expect(Geo.clampFollowDistance(337_695) == Geo.followDistanceRange.upperBound)
        #expect(Geo.clampFollowDistance(5) == Geo.followDistanceRange.lowerBound)
    }

    @Test("Street-level distances pass through untouched")
    func keepsReasonableValues() {
        for metres in [150.0, 420.0, 900.0, 3_000.0] {
            #expect(Geo.clampFollowDistance(metres) == metres)
        }
    }

    @Test("Zooming out to see where you are going keeps following")
    func regionalZoomIsAllowed() {
        // The ceiling was 4 km, so a driver zooming out for context passed it immediately and
        // the next fix snapped the camera back to street level. These are the zoom levels a
        // driver actually reaches: a few miles of road, a metro, a region.
        for metres in [8_000.0, 25_000.0, 120_000.0, 240_000.0] {
            #expect(Geo.clampFollowDistance(metres) == metres, "\(metres) m should still follow")
        }
    }

    @Test("The default the app follows at is inside the allowed range")
    func defaultIsValid() {
        #expect(Geo.followDistanceRange.contains(420))
    }
}

@Suite("Zooming out while the car is moving")
struct DriveZoomTests {
    @Test("A distance the app did not ask for is the user's")
    func identifiesAUserZoom() {
        // The follow camera is always set to exactly `followDistance`, so anything materially
        // different came from a pinch. This is identity, not timing — and timing is precisely
        // what failed: the location provider delivers a fix every 25 m, about every 1.2 s at
        // 45 mph, against a 1.2 s programmatic-settle window. While driving that window never
        // closes, so every gesture was discarded and the next fix restored the old zoom.
        #expect(Geo.userChangedZoom(observed: 2_000, expected: 420))
        #expect(Geo.userChangedZoom(observed: 120, expected: 420))
    }

    @Test("The app's own recentring is not mistaken for a gesture")
    func ignoresItsOwnCamera() {
        #expect(!Geo.userChangedZoom(observed: 420, expected: 420))
        // MapKit does not land exactly on the requested distance, and an animation overshoots.
        #expect(!Geo.userChangedZoom(observed: 428, expected: 420))
        #expect(!Geo.userChangedZoom(observed: 412, expected: 420))
    }

    @Test("Nonsense distances are refused rather than adopted")
    func guardsBadInput() {
        #expect(!Geo.userChangedZoom(observed: 0, expected: 420))
        #expect(!Geo.userChangedZoom(observed: .nan, expected: 420))
        #expect(!Geo.userChangedZoom(observed: .infinity, expected: 420))
        #expect(!Geo.userChangedZoom(observed: 420, expected: 0))
    }

    @Test("A regional zoom survives being adopted")
    func adoptedZoomIsKept() {
        // The two halves have to agree: detecting the gesture is useless if the clamp then
        // pulls the value back to street level, which is what a 4 km ceiling did.
        for metres in [3_000.0, 40_000.0, 200_000.0] {
            #expect(Geo.userChangedZoom(observed: metres, expected: 420))
            #expect(Geo.clampFollowDistance(metres) == metres)
        }
    }

    @Test("The grace window outlasts the gap between fixes")
    func graceOutlastsFixCadence() {
        // If the window were shorter than the interval between GPS fixes, a recentre would
        // land in the middle of a pinch anyway. At 45 mph a 25 m filter fires about every
        // 1.2 s; the window is refreshed by every camera change during the gesture, so it
        // only has to cover the gap between two changes within one pinch.
        #expect(Geo.userZoomGraceWindow > 0.5)
        #expect(Geo.userZoomGraceWindow < Geo.programmaticSettleWindow + 1.0,
                "long enough to protect a gesture, short enough that follow resumes promptly")
    }
}

@Suite("The zoom buttons while following")
struct FollowZoomButtonTests {
    /// The factors the two buttons pass.
    let zoomIn = 0.5
    let zoomOut = 2.0

    @Test("A button press changes the follow distance, and stays in range")
    func scalesTheFollowDistance() {
        // While following, a zoom is a change of how far back the camera sits — not of where
        // it is pointed. The buttons used to push a new *region*, which re-centred on a stale
        // coordinate and read as a pan, switching the follow off.
        var distance = RoadMapScreenDefaults.followDistanceMeters
        distance = Geo.clampFollowDistance(distance * zoomOut)
        #expect(distance == 840)
        distance = Geo.clampFollowDistance(distance * zoomIn)
        #expect(distance == RoadMapScreenDefaults.followDistanceMeters, "in undoes out")
    }

    @Test("Repeated zooming out settles at the ceiling rather than running away")
    func clampsAtTheCeiling() {
        var distance = RoadMapScreenDefaults.followDistanceMeters
        for _ in 0..<20 { distance = Geo.clampFollowDistance(distance * zoomOut) }
        #expect(distance == Geo.followDistanceRange.upperBound)
    }

    @Test("Repeated zooming in settles at the floor")
    func clampsAtTheFloor() {
        var distance = RoadMapScreenDefaults.followDistanceMeters
        for _ in 0..<20 { distance = Geo.clampFollowDistance(distance * zoomIn) }
        #expect(distance == Geo.followDistanceRange.lowerBound)
    }
}

/// Mirrors the view's constant so the arithmetic above is testable without a map.
enum RoadMapScreenDefaults {
    static let followDistanceMeters: Double = 420
}

@Suite("Drive mode comes back to the car")
struct FollowAutoResumeTests {
    private let now = Date()

    private func resume(driving: Bool = true, following: Bool = false, gesture: Bool = true,
                        secondsSinceGesture: Double?) -> Bool {
        Geo.shouldAutoResume(isDriving: driving, isFollowing: following,
                             offBecauseOfMapGesture: gesture,
                             lastMapGesture: secondsSinceGesture.map { now.addingTimeInterval(-$0) },
                             now: now)
    }

    @Test("Five seconds after the last touch, following resumes")
    func resumesAfterTheDelay() {
        #expect(resume(secondsSinceGesture: Geo.followAutoResumeDelay))
        #expect(resume(secondsSinceGesture: 30))
    }

    @Test("Not while the driver is still looking around")
    func waitsOutTheGesture() {
        #expect(!resume(secondsSinceGesture: 0))
        #expect(!resume(secondsSinceGesture: Geo.followAutoResumeDelay - 0.1))
    }

    @Test("Turning following off with the button is a choice, and it sticks")
    func respectsTheButton() {
        #expect(!resume(gesture: false, secondsSinceGesture: 60))
    }

    @Test("Only in drive mode, and only when not already following")
    func onlyWhenItMatters() {
        #expect(!resume(driving: false, secondsSinceGesture: 60))
        #expect(!resume(following: true, secondsSinceGesture: 60))
    }
}
