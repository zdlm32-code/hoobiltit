import Foundation

/// How close a centreline has to be before a source may call it "the road here".
///
/// Every naming source finds the *nearest* road it knows about, and until this existed none of
/// them asked whether that road was plausibly the one under the pin. The failure is silent and
/// looks like a calibration fault: the county's countywide centreline does not contain
/// E Athena Ave in Gilbert, so a pin on Athena Ave was named **E Germann Rd, 76 m away** — a
/// block over — while Census TIGER, which has Athena Ave 5.9 m from the same pin, was skipped
/// because the road had "already been named".
///
/// A source with partial coverage must decline rather than answer with whatever it happens to
/// hold nearby. Declining is not a loss: the next source in the pipeline gets its turn, and the
/// national tier covers all 16.1 million US road segments.
public enum RoadProximity {
    /// Roughly a wide arterial's half-width plus centreline generalisation and a hand-placed
    /// pin's error. Comfortably includes the road you meant; comfortably excludes the next
    /// street over.
    public static let onRoadMeters: Double = 60

    /// Whether a candidate at this distance can be called the road at the point.
    public static func isOnRoad(_ metres: Double?) -> Bool {
        guard let metres, metres.isFinite else { return false }
        return metres <= onRoadMeters
    }
}
