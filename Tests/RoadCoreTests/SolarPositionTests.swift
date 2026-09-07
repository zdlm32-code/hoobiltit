import Foundation
import Testing
@testable import RoadCore

private func date(_ iso: String) -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: iso)!
}

private let phoenix = Coordinate(latitude: 33.4484, longitude: -112.0740)
/// Utqiaġvik, Alaska — above the Arctic Circle.
private let utqiagvik = Coordinate(latitude: 71.2906, longitude: -156.7886)

@Suite("Knowing when it is dark outside")
struct SolarPositionTests {
    @Test("Phoenix in the evening is night")
    func phoenixEvening() {
        // 19:00 MST in January, an hour after sunset.
        #expect(SolarPosition.altitudeDegrees(at: phoenix, on: date("2026-01-15T02:00:00Z")) < -3)
    }

    @Test("Phoenix at midday is not")
    func phoenixMidday() {
        // 13:00 MST at the summer solstice — the sun is near its highest.
        let noon = SolarPosition.altitudeDegrees(at: phoenix, on: date("2026-06-21T20:00:00Z"))
        #expect(noon > 70)
    }

    @Test("The midnight sun is daylight, which clock arithmetic would get wrong")
    func arcticSummerMidnight() {
        // The test that proves this is astronomy and not "is it after 6 pm". At Utqiaġvik in
        // June the sun does not set, so local midnight is bright — and a night mode that
        // darkened the map there would be simply wrong.
        let localMidnight = date("2026-06-21T09:00:00Z")   // 00:00 AKDT
        #expect(SolarPosition.altitudeDegrees(at: utqiagvik, on: localMidnight) > 0)
        #expect(!SolarPosition.isNight(at: utqiagvik, on: localMidnight, wasNight: false))
    }

    @Test("Polar winter is night all day, likewise")
    func arcticWinterNoon() {
        let localNoon = date("2026-12-21T21:00:00Z")       // 12:00 AKST
        #expect(SolarPosition.altitudeDegrees(at: utqiagvik, on: localNoon) < -3)
    }

    @Test("Dusk cannot flap between light and dark")
    func hysteresis() {
        // Between the two thresholds the state is held, so a map does not strobe while the sun
        // sits on the horizon for several minutes.
        let dusk = date("2026-01-15T01:15:00Z")
        let altitude = SolarPosition.altitudeDegrees(at: phoenix, on: dusk)
        if altitude < 0 && altitude > -3 {
            #expect(SolarPosition.isNight(at: phoenix, on: dusk, wasNight: true))
            #expect(!SolarPosition.isNight(at: phoenix, on: dusk, wasNight: false))
        }
        // And the thresholds are ordered the way hysteresis requires.
        #expect(SolarPosition.nightThreshold < SolarPosition.dayThreshold)
    }

    @Test("The sun goes round once a day, not twice or not at all")
    func sanityOverAFullDay() {
        // A cheap guard against sign and unit errors in the sidereal-time arithmetic: over 24
        // hours Phoenix must see exactly one crossing into daylight and one out of it.
        var crossings = 0
        var previous = SolarPosition.altitudeDegrees(at: phoenix, on: date("2026-03-20T00:00:00Z"))
        for minute in stride(from: 10, through: 24 * 60, by: 10) {
            let now = SolarPosition.altitudeDegrees(
                at: phoenix,
                on: date("2026-03-20T00:00:00Z").addingTimeInterval(Double(minute) * 60))
            if (previous < 0) != (now < 0) { crossings += 1 }
            previous = now
        }
        #expect(crossings == 2)
    }
}
