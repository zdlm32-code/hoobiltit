import Foundation

/// Decides when a moving car deserves a fresh answer.
///
/// A full resolve asks every source in the pipeline and takes seconds; running one per GPS fix
/// would be unusable and rude to the agencies. Running one too rarely leaves the card showing
/// the road you were on a mile ago. This is that judgement, pulled out of the view model so it
/// can be tested without a location manager, a network or a map.
public enum DriveTrigger {
    /// Distance beyond which a standing answer is refreshed regardless of the probe, so a
    /// stale one cannot persist down a long road the probe cannot name.
    public static let staleDistanceMeters: Double = 250
    /// How close the probe's nearest centreline must be to count as "the road you are on".
    /// Shared with the naming sources, which gate on the same question.
    public static var onRoadMeters: Double { RoadProximity.onRoadMeters }

    public struct Input: Sendable, Hashable {
        /// Comparison key of the road the probe just named, or nil if it named none nearby.
        public var probedRoad: String?
        public var lastProbedRoad: String?
        public var countyFIPS: String?
        public var lastCountyFIPS: String?
        public var metresSinceLastResolve: Double?
        /// Whether the card currently shows a named road at all.
        public var hasStandingAnswer: Bool

        public init(probedRoad: String?, lastProbedRoad: String?, countyFIPS: String?,
                    lastCountyFIPS: String?, metresSinceLastResolve: Double?,
                    hasStandingAnswer: Bool) {
            self.probedRoad = probedRoad
            self.lastProbedRoad = lastProbedRoad
            self.countyFIPS = countyFIPS
            self.lastCountyFIPS = lastCountyFIPS
            self.metresSinceLastResolve = metresSinceLastResolve
            self.hasStandingAnswer = hasStandingAnswer
        }
    }

    /// True when the pipeline should run again.
    public static func shouldResolve(_ input: Input) -> Bool {
        let movedFar = input.metresSinceLastResolve.map { $0 > staleDistanceMeters } ?? true

        // Crossing a county line changes who maintains the road, and often which sources can
        // answer for it, without changing its name. Without this the previous county's answer
        // stands for the rest of the road — and because it cannot happen inside a single
        // county, it is invisible to every test written while the app covered only Maricopa.
        if let county = input.countyFIPS, let last = input.lastCountyFIPS, county != last {
            return true
        }

        guard let probed = input.probedRoad else {
            // The probe could not name the road. Letting that veto the lookup is what once
            // left drive mode stuck on "Looking…" on any road the centreline did not know, so
            // resolve anyway when there is nothing to show or the car has moved on.
            return !input.hasStandingAnswer || movedFar
        }
        return probed != input.lastProbedRoad || movedFar
    }
}
