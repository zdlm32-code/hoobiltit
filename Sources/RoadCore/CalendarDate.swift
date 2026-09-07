import Foundation

/// Formatting for dates that are *calendar dates*, not instants.
///
/// A road declaration, a plat recording and a bridge's build year name a day, not a moment.
/// The agencies store them as UTC midnight, so rendering them in the device's time zone
/// shifts them backwards a day everywhere west of Greenwich — a road declared on 24 September
/// displays as the 23rd in Phoenix. That is wrong about a legal record, so these are always
/// formatted in UTC.
public enum CalendarDate {
    public static var utc: TimeZone { TimeZone(identifier: "UTC")! }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeZone = utc
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    /// "24 Sep 2014" — the day the record names, in every time zone.
    public static func medium(_ date: Date) -> String {
        dayFormatter.string(from: date)
    }

    public static func year(_ date: Date) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        return calendar.component(.year, from: date)
    }

    /// A bare year as a date, for agencies that publish only the year.
    ///
    /// PennDOT's `YR_BUILT` and Louisiana's `YearLastConst` are integers — 1916, 1959 — with
    /// no month or day. Anchoring at UTC midnight on 1 January keeps them round-tripping
    /// through `year(_:)` unchanged in every time zone, which is the property the UI needs:
    /// the card renders these as a year and must never show 1915 to a driver in Phoenix.
    public static func januaryFirst(ofYear year: Int) -> Date? {
        var components = DateComponents()
        components.year = year
        components.month = 1
        components.day = 1
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        return calendar.date(from: components)
    }
}
