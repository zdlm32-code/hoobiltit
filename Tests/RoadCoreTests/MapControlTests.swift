import Foundation
import Testing
@testable import RoadCore
@testable import RoadUI

@Suite("Zoom arithmetic")
struct ZoomTests {
    private let typical = MapSpan(latitudeDelta: 0.01, longitudeDelta: 0.012)

    @Test("Halving and doubling do what they say")
    func scales() {
        let inward = Geo.scaledSpan(typical, by: 0.5)
        #expect(abs(inward.latitudeDelta - 0.005) < 1e-9)
        #expect(abs(inward.longitudeDelta - 0.006) < 1e-9)

        let outward = Geo.scaledSpan(typical, by: 2)
        #expect(abs(outward.latitudeDelta - 0.02) < 1e-9)
    }

    @Test("Aspect ratio survives a clamp")
    func clampKeepsShape() {
        // Zooming far past the inner limit must not squash the viewport: clamping each axis
        // on its own distorts the map visibly at maximum zoom.
        let ratioBefore = typical.longitudeDelta / typical.latitudeDelta
        let clamped = Geo.scaledSpan(typical, by: 0.00001)
        let ratioAfter = clamped.longitudeDelta / clamped.latitudeDelta

        #expect(abs(ratioBefore - ratioAfter) < 1e-9)
        #expect(abs(clamped.latitudeDelta - Geo.minimumSpanDegrees) < 1e-9)
    }

    @Test("Neither button can walk the map out of the useful range")
    func clampsBothEnds() {
        let tiny = Geo.scaledSpan(MapSpan(latitudeDelta: 0.0006, longitudeDelta: 0.0006), by: 0.5)
        #expect(tiny.latitudeDelta >= Geo.minimumSpanDegrees - 1e-12)

        let huge = Geo.scaledSpan(MapSpan(latitudeDelta: 1.5, longitudeDelta: 1.5), by: 4)
        #expect(huge.latitudeDelta <= Geo.maximumSpanDegrees + 1e-12)
    }

    @Test("A viewport already outside the range is not dragged further out")
    func doesNotWorsenAnOutOfRangeSpan() {
        // Pinching can leave the span past a limit; the button must then refuse rather than
        // "clamp" in the wrong direction and jump the camera.
        let tooTight = MapSpan(latitudeDelta: 0.0001, longitudeDelta: 0.0001)
        #expect(Geo.scaledSpan(tooTight, by: 0.5) == tooTight)

        // Expressed against the limit rather than a literal, so raising the maximum — as
        // going national did, from one county's width to the continent's — cannot silently
        // turn this into a test of nothing.
        let tooWide = MapSpan(latitudeDelta: Geo.maximumSpanDegrees + 1,
                              longitudeDelta: Geo.maximumSpanDegrees + 1)
        #expect(Geo.scaledSpan(tooWide, by: 2) == tooWide)
    }

    @Test("Nonsense factors are refused rather than producing a broken viewport")
    func guardsBadInput() {
        #expect(Geo.scaledSpan(typical, by: 0) == typical)
        #expect(Geo.scaledSpan(typical, by: -1) == typical)
        #expect(Geo.scaledSpan(MapSpan(latitudeDelta: 0, longitudeDelta: 0), by: 0.5)
                == MapSpan(latitudeDelta: 0, longitudeDelta: 0))
    }

    @Test("Buttons know when they would do nothing")
    func availability() {
        #expect(Geo.canZoomIn(typical))
        #expect(Geo.canZoomOut(typical))
        #expect(!Geo.canZoomIn(MapSpan(latitudeDelta: Geo.minimumSpanDegrees,
                                       longitudeDelta: Geo.minimumSpanDegrees)))
        #expect(!Geo.canZoomOut(MapSpan(latitudeDelta: Geo.maximumSpanDegrees,
                                        longitudeDelta: Geo.maximumSpanDegrees)))
    }
}

@Suite("Map styles")
struct MapStyleChoiceTests {
    @Test("Every style is offerable and distinct")
    func allCases() {
        #expect(MapStyleChoice.allCases.count == 3)
        #expect(Set(MapStyleChoice.allCases.map(\.name)).count == 3)
        #expect(Set(MapStyleChoice.allCases.map(\.symbol)).count == 3)
        // Named for what a person calls it, not what MapKit calls it.
        #expect(MapStyleChoice.imagery.name == "Satellite")
    }

    @Test("Round-trips through its raw value for persistence")
    func rawValues() {
        for choice in MapStyleChoice.allCases {
            #expect(MapStyleChoice(rawValue: choice.rawValue) == choice)
        }
    }
}

@Suite("Location availability")
struct LocationAvailabilityTests {
    @Test("A refusal explains itself rather than leaving a dead button")
    func deniedCarriesAReason() {
        let denied = LocationProvider.availability(for: .denied)
        #expect(denied.isDenied)
        guard case .unavailable(let reason) = denied else {
            Issue.record("expected an explanation"); return
        }
        #expect(reason.contains("Settings"))
    }

    @Test("Restricted is unavailable but is not the user's doing")
    func restricted() {
        guard case .unavailable(let reason) = LocationProvider.availability(for: .restricted) else {
            Issue.record("expected unavailable"); return
        }
        #expect(reason.contains("restricted"))
    }

    @Test("Not yet asked is distinct from refused, so the prompt still happens")
    func notDetermined() {
        #expect(LocationProvider.availability(for: .notDetermined) == .notYetAsked)
        #expect(!LocationProvider.availability(for: .notDetermined).isDenied)
    }

    @Test("Authorised states count as authorised")
    func authorized() {
        #expect(LocationProvider.availability(for: .authorizedAlways) == .authorized)
        #if os(iOS)
        // The only status this app ever actually requests.
        #expect(LocationProvider.availability(for: .authorizedWhenInUse) == .authorized)
        #endif
    }
}
