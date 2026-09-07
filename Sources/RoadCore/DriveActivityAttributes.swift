// `canImport(ActivityKit)` is true on macOS — the module exists there but its types are
// unavailable — so the guard has to be the platform, not the import.
#if os(iOS)
import ActivityKit
import Foundation

/// The Live Activity's identity. Its state is `DriveActivityState`, which lives outside this
/// file precisely so it — and every rule that produces it — stays compilable and testable on
/// macOS, where ActivityKit's types are unavailable.
public struct DriveActivityAttributes: ActivityAttributes {
    public typealias ContentState = DriveActivityState

    public let startedAt: Date

    public init(startedAt: Date = .now) {
        self.startedAt = startedAt
    }
}
#endif
