import Foundation

/// Where the sun is, so drive mode can go dark when the windscreen does.
///
/// The obvious trigger for a night mode is the system appearance, and it is the wrong one: most
/// people leave iOS on Light permanently, so a map keyed to it stays blinding white at 9 pm —
/// which is the complaint night mode exists to answer. The phone knows where it is and what
/// time it is, and that is enough to know whether it is dark outside.
///
/// This is the NOAA low-precision algorithm, good to about ±0.5°. That is far more accuracy
/// than "is it dark enough to want a dark map" needs, and it costs no dependency and no
/// network — the project has neither and should keep it that way.
public enum SolarPosition {
    /// Sun altitude above the horizon, in degrees. Negative is below.
    public static func altitudeDegrees(at coordinate: Coordinate, on date: Date) -> Double {
        // Days since J2000.0. Unix epoch is JD 2440587.5, J2000 is JD 2451545.0.
        let n = date.timeIntervalSince1970 / 86_400 + 2_440_587.5 - 2_451_545.0

        let meanLongitude = (280.460 + 0.985_647_4 * n).truncatingRemainder(dividingBy: 360)
        let meanAnomaly = radians((357.528 + 0.985_600_3 * n).truncatingRemainder(dividingBy: 360))
        // Equation of centre, to first order — the term that turns a circular orbit into the
        // real elliptical one.
        let eclipticLongitude = radians(meanLongitude
                                        + 1.915 * sin(meanAnomaly)
                                        + 0.020 * sin(2 * meanAnomaly))
        let obliquity = radians(23.439 - 0.000_000_4 * n)

        let declination = asin(sin(obliquity) * sin(eclipticLongitude))
        let rightAscension = atan2(cos(obliquity) * sin(eclipticLongitude), cos(eclipticLongitude))

        // Greenwich mean sidereal time, in hours, then local.
        let gmst = (18.697_374_558 + 24.065_709_824_419_08 * n)
            .truncatingRemainder(dividingBy: 24)
        let localSiderealDegrees = gmst * 15 + coordinate.longitude
        let hourAngle = radians(localSiderealDegrees) - rightAscension

        let latitude = radians(coordinate.latitude)
        let altitude = asin(sin(latitude) * sin(declination)
                            + cos(latitude) * cos(declination) * cos(hourAngle))
        return degrees(altitude)
    }

    /// Just into civil twilight — the sky is visibly dark and headlights are on.
    public static let nightThreshold = -3.0
    /// Hysteresis, so the map cannot flap back and forth through dusk.
    public static let dayThreshold = 0.0

    /// Whether it is dark enough for the night treatment, given what it was a moment ago.
    public static func isNight(at coordinate: Coordinate, on date: Date, wasNight: Bool) -> Bool {
        let altitude = altitudeDegrees(at: coordinate, on: date)
        return wasNight ? altitude < dayThreshold : altitude < nightThreshold
    }

    private static func radians(_ degrees: Double) -> Double { degrees * .pi / 180 }
    private static func degrees(_ radians: Double) -> Double { radians * 180 / .pi }
}
