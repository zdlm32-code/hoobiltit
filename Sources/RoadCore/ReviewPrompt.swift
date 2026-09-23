import Foundation

/// Decides when the app may ask for an App Store rating.
///
/// Ratings are most of what ranks a new app, and the people most willing to leave one are those
/// the app has already answered more than once. So the ask waits until a user has had a real
/// answer — a road with a named owner — on several different days, and then comes at a pause
/// they chose: closing a card, never mid-lookup and never while driving. It asks at most once
/// per app version; StoreKit adds its own cap of three a year on top, and may show nothing.
///
/// Pure state, persisted by the caller, so the rule can be tested without StoreKit or a clock.
public struct ReviewPrompt: Codable, Sendable, Equatable {
    /// Distinct days with a real answer before the first ask.
    public static let requiredDays = 3

    /// Local calendar days ("2026-09-23") on which the user got a real answer. Only the most
    /// recent `requiredDays` are kept; older ones cannot change the decision.
    public private(set) var answeredDays: [String] = []
    /// The version the user was last asked in, so an update can ask again and nothing else can.
    public private(set) var askedInVersion: String?

    public init() {}

    /// Records a lookup. Only a record naming an owner counts: an answer with nothing in it is
    /// not the moment to ask someone how they like the app. "Not publicly maintained" and
    /// "private" are real answers — often the most satisfying ones — so they count.
    public mutating func note(_ record: RoadRecord, on date: Date = .now,
                              calendar: Calendar = .current) {
        guard let owner = record.owner?.value, owner != .undetermined else { return }
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        let day = String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
        guard !answeredDays.contains(day) else { return }
        answeredDays = Array((answeredDays + [day]).sorted().suffix(Self.requiredDays))
    }

    public func shouldAsk(appVersion: String, isDriving: Bool) -> Bool {
        !isDriving && answeredDays.count >= Self.requiredDays && askedInVersion != appVersion
    }

    public mutating func markAsked(appVersion: String) {
        askedInVersion = appVersion
    }
}
