import Foundation
import CoreLocation
import Observation

/// A one-shot location fix, wrapped so the map screen can await a coordinate.
///
/// `MapUserLocationButton` recentres the map but never hands back a coordinate, and this app
/// needs the coordinate — the whole point of the locate button is to run a lookup on where you
/// are standing. So this owns a `CLLocationManager` directly.
@MainActor
@Observable
public final class LocationProvider: NSObject {
    public enum Availability: Equatable {
        case notYetAsked
        case authorized
        /// The user said no, or the device forbids it. Either way the button must explain
        /// itself rather than appear broken.
        case unavailable(reason: String)
    }

    public private(set) var availability: Availability = .notYetAsked
    public private(set) var isLocating = false
    /// Latest fix while streaming. Nil until updates start producing.
    public private(set) var currentFix: CLLocationCoordinate2D?
    /// Direction of travel in degrees, or nil when stationary. GPS course is meaningless below
    /// walking pace, so it is only published when the fix says it is valid.
    public private(set) var currentCourse: Double?
    /// Metres per second from the last fix, or nil when the fix reports no valid speed.
    public private(set) var currentSpeed: Double?

    /// Whether the device is being driven, from speed alone.
    ///
    /// Deliberately not Core Motion: activity classification needs the Motion & Fitness
    /// permission and a second prompt, and speed off a fix the app already receives is enough
    /// to tell a car from a parked phone.
    public enum Motion: Equatable { case stationary, driving }
    public private(set) var motion: Motion = .stationary

    /// Hysteresis, so a stop light does not flip modes and a fast walk does not start one.
    /// Enter at ~11 mph, leave below ~2 mph sustained for `stillnessBeforeStationary`.
    nonisolated static let drivingEntrySpeed: Double = 5.0
    nonisolated static let drivingExitSpeed: Double = 1.0
    nonisolated static let stillnessBeforeStationary: TimeInterval = 45

    private var slowSince: Date?
    public private(set) var isStreaming = false
    /// Called for every fix that clears `distanceFilter`, so drive mode can react.
    public var onFix: (@MainActor (CLLocationCoordinate2D) -> Void)?

    /// `requestLocation()` can simply never call back where the sky is blocked, and a spinner
    /// that never stops reads as a hang.
    static let fixTimeout: Duration = .seconds(15)

    private let manager = CLLocationManager()
    private var authorizationWaiters: [CheckedContinuation<Void, Never>] = []
    private var fixWaiters: [CheckedContinuation<CLLocationCoordinate2D?, Never>] = []

    public override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        availability = Self.availability(for: manager.authorizationStatus)
    }

    /// Centre-of-the-road accuracy is what matters here; the resolver searches 150 m anyway.
    public func requestFix() async -> CLLocationCoordinate2D? {
        if case .notYetAsked = availability {
            manager.requestWhenInUseAuthorization()
            await withCheckedContinuation { authorizationWaiters.append($0) }
        }
        guard case .authorized = availability else { return nil }

        isLocating = true
        defer { isLocating = false }

        return await withCheckedContinuation { continuation in
            fixWaiters.append(continuation)
            manager.requestLocation()
            // Resuming clears the waiter list, so whichever of the fix and this timeout
            // arrives first wins and the other becomes a no-op.
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: Self.fixTimeout)
                self?.resumeFixWaiters(with: nil)
            }
        }
    }

    /// Starts continuous updates for drive mode.
    ///
    /// Asks for "Always" so identification survives the screen locking — a phone on a dash
    /// sleeps, and "while in use" stops the moment it does. `allowsBackgroundLocationUpdates`
    /// requires the location background mode in Info.plist; without it this call traps.
    public func startStreaming() async -> Bool {
        if case .notYetAsked = availability {
            manager.requestWhenInUseAuthorization()
            await withCheckedContinuation { authorizationWaiters.append($0) }
        }
        guard case .authorized = availability else { return false }

        // Escalating to Always is a second prompt, and iOS only offers it once the app has
        // When-In-Use. Streaming still works without it, just not with the screen locked.
        manager.requestAlwaysAuthorization()

        manager.activityType = .automotiveNavigation
        manager.desiredAccuracy = kCLLocationAccuracyBest
        // A road change cannot happen in less than this, and it keeps the probe off the
        // network while stopped at a light.
        manager.distanceFilter = 25
        manager.pausesLocationUpdatesAutomatically = false
        manager.allowsBackgroundLocationUpdates = true
        manager.startUpdatingLocation()
        isStreaming = true
        return true
    }

    public func stopStreaming() {
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        manager.distanceFilter = kCLDistanceFilterNone
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        isStreaming = false
        currentFix = nil
    }

    private func updateMotion(speed: Double?) {
        guard let speed else { return }
        if speed >= Self.drivingEntrySpeed {
            slowSince = nil
            motion = .driving
            return
        }
        guard speed <= Self.drivingExitSpeed else { return }   // in between: hold the state
        let now = Date()
        let since = slowSince ?? now
        slowSince = since
        if now.timeIntervalSince(since) >= Self.stillnessBeforeStationary {
            motion = .stationary
        }
    }

    /// Pure mapping, deliberately not actor-isolated so it can be tested without a main
    /// actor and without a real location manager.
    nonisolated static func availability(for status: CLAuthorizationStatus) -> Availability {
        switch status {
        case .notDetermined:
            return .notYetAsked
        case .authorizedAlways:
            return .authorized
        #if os(iOS)
        case .authorizedWhenInUse:
            return .authorized
        #endif
        case .denied:
            return .unavailable(reason: "Location access is off for this app. Turn it on in "
                                        + "Settings to identify the road you are standing on.")
        case .restricted:
            return .unavailable(reason: "Location access is restricted on this device.")
        @unknown default:
            return .unavailable(reason: "Location is unavailable on this device.")
        }
    }

    private func resumeAuthorizationWaiters() {
        let waiters = authorizationWaiters
        authorizationWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
    }

    private func resumeFixWaiters(with coordinate: CLLocationCoordinate2D?) {
        let waiters = fixWaiters
        fixWaiters.removeAll()
        for waiter in waiters { waiter.resume(returning: coordinate) }
    }
}

extension LocationProvider: CLLocationManagerDelegate {
    public nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        MainActor.assumeIsolated {
            availability = Self.availability(for: status)
            // Only unblock once the user has actually answered the prompt.
            if status != .notDetermined { resumeAuthorizationWaiters() }
        }
    }

    public nonisolated func locationManager(_ manager: CLLocationManager,
                                            didUpdateLocations locations: [CLLocation]) {
        let coordinate = locations.last?.coordinate
        MainActor.assumeIsolated {
            resumeFixWaiters(with: coordinate)
            if let coordinate, isStreaming {
                currentFix = coordinate
                if let location = locations.last, location.course >= 0, location.speed > 1.5 {
                    currentCourse = location.course
                } else {
                    currentCourse = nil
                }
                currentSpeed = (locations.last?.speed).flatMap { $0 >= 0 ? $0 : nil }
                updateMotion(speed: currentSpeed)
                onFix?(coordinate)
            }
        }
    }

    public nonisolated func locationManager(_ manager: CLLocationManager,
                                            didFailWithError error: Error) {
        MainActor.assumeIsolated { resumeFixWaiters(with: nil) }
    }
}
