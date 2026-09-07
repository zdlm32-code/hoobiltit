import Foundation
import RoadCore
#if os(iOS)
import ActivityKit
#endif

/// Owns the Live Activity that puts the current road on the lock screen and in the Dynamic
/// Island.
///
/// Declared unconditionally with no-op bodies off iOS. Guarding the whole type instead would
/// break `RoadMapScreen`'s compilation under `swift test` on macOS, which is where every test
/// in this project runs.
///
/// Worth knowing about the device this was built for: **an iPhone 15 has no Always-On Display**,
/// so with the screen asleep the activity is not visible at all — it is there when the screen
/// wakes, and in the Dynamic Island whenever the phone is unlocked and this app is not
/// frontmost. The thing that keeps the map itself in front of a driver is
/// `isIdleTimerDisabled`, which is separate and much cheaper.
///
/// Deliberately **not** `@MainActor`. `Activity` is not `Sendable` and its `update`/`end` are
/// nonisolated and async, so holding the handle in any isolated context makes every call a
/// "sending" violation under Swift 6 strict concurrency — there is no spelling of `Task` that
/// avoids it. Standing outside isolation removes the boundary rather than fighting it, and a
/// lock guards the small mutable state, which is the honest trade.
public final class DriveActivityController: @unchecked Sendable {
    private let lock = NSLock()
    #if os(iOS)
    private var activity: Activity<DriveActivityAttributes>?
    #endif
    private var lastPushed: DriveActivityState?
    private var lastPushAt: Date?
    /// `Activity.request` throws from the background, and drive mode can begin there — the
    /// motion check runs on a location fix. So a start that cannot happen now is held.
    private var pendingStart: DriveActivityState?
    private var inFlight: Task<Void, Never>?

    /// Two updates a second would be throttled and would tell the driver nothing. A road change
    /// bypasses this; only same-road churn waits.
    public static let minimumUpdateInterval: TimeInterval = 2
    /// After this the widget greys itself out rather than presenting a stale road as current.
    /// It matters because the app can be jetsammed mid-drive and simply stop updating.
    public static let staleAfter: TimeInterval = 300

    public init() {}

    public var isAvailable: Bool {
        #if os(iOS)
        return ActivityAuthorizationInfo().areActivitiesEnabled
        #else
        return false
        #endif
    }

    public func start(_ state: DriveActivityState, foreground: Bool) {
        lock.lock(); defer { lock.unlock() }
        #if os(iOS)
        guard isAvailable, activity == nil else { return }
        guard foreground else { pendingStart = state; return }
        pendingStart = nil
        do {
            activity = try Activity.request(
                attributes: DriveActivityAttributes(),
                content: content(state),
                // Never an alert. A banner and a haptic every time the road changes, while
                // driving, is actively dangerous.
                pushType: nil)
            lastPushed = state
            lastPushAt = Date()
        } catch {
            // A refused activity is not an error the driver can do anything about.
            activity = nil
        }
        #endif
    }

    public func update(_ state: DriveActivityState) {
        lock.lock(); defer { lock.unlock() }
        #if os(iOS)
        guard let activity else { return }
        // The payload is `Hashable` and made of finished strings, so an unchanged road produces
        // a byte-identical state and costs nothing. That is what makes the 250 m re-resolve
        // cadence free for the lock screen.
        guard state != lastPushed else { return }
        if state.road == lastPushed?.road, let last = lastPushAt,
           Date().timeIntervalSince(last) < Self.minimumUpdateInterval { return }

        lastPushed = state
        lastPushAt = Date()
        // Last write wins: cancelling the previous update stops two refreshes landing out of
        // order and leaving the island showing the road before last.
        inFlight?.cancel()
        let payload = content(state)
        // Stays on the main actor: the activity handle is isolated here, and hopping off just
        // to await would be sending it across an isolation boundary.
        inFlight = Task { await activity.update(payload) }
        #endif
    }

    public func end() {
        lock.lock(); defer { lock.unlock() }
        #if os(iOS)
        inFlight?.cancel()
        inFlight = nil
        pendingStart = nil
        lastPushed = nil
        lastPushAt = nil
        guard let activity else { return }
        self.activity = nil
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
        #endif
    }

    /// Clears anything a crash, a force-quit, or a drive that ended while the app was dead left
    /// behind. Without this the lock screen can show a road from yesterday.
    public func endStrayActivities() {
        #if os(iOS)
        Task {
            for stray in Activity<DriveActivityAttributes>.activities {
                await stray.end(nil, dismissalPolicy: .immediate)
            }
        }
        #endif
    }

    /// Called when the app comes to the foreground, to run a start that was refused earlier.
    public func resumePendingStart() {
        #if os(iOS)
        // Read under the lock, then release it — `start` takes the same lock and NSLock is
        // not recursive.
        lock.lock()
        let pending = pendingStart
        lock.unlock()
        guard let pending else { return }
        start(pending, foreground: true)
        #endif
    }

    #if os(iOS)
    private func content(_ state: DriveActivityState) -> ActivityContent<DriveActivityState> {
        ActivityContent(state: state, staleDate: Date().addingTimeInterval(Self.staleAfter))
    }
    #endif
}
