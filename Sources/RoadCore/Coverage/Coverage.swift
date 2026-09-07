import Foundation

/// What this build could bring to bear where the pin is, and what it could not.
///
/// Deliberately a fact about *the app*, not about the road, which is why it lives on
/// `RoadRecord` and not on `RoadFragment`: it must never pass through `merge`, where
/// first-writer-wins could let one source's view of coverage stand for the pipeline's.
///
/// It is also the only thing that can tell "no source is mapped for this county" apart from
/// "a source is mapped and found nothing" — a distinction no individual source can draw, and
/// the entire content of the sentence the card shows.
public struct Coverage: Sendable, Hashable {
    public enum Leg: String, Sendable, Hashable, CaseIterable {
        case name, owner, date
    }

    public let level: CoverageLevel
    public let jurisdiction: Jurisdiction?
    /// Profiles consulted, deepest first. Empty at the national tier.
    public let profileNames: [String]
    /// A profile's own warning about what it cannot date, shown when no date was found.
    public let dateCaveats: [String]
    public let catalogCapturedOn: Date?

    public init(level: CoverageLevel, jurisdiction: Jurisdiction?, profileNames: [String] = [],
                dateCaveats: [String] = [], catalogCapturedOn: Date? = nil) {
        self.level = level
        self.jurisdiction = jurisdiction
        self.profileNames = profileNames
        self.dateCaveats = dateCaveats
        self.catalogCapturedOn = catalogCapturedOn
    }

    /// Which of the three legs the record is still missing.
    public func missing(in record: RoadRecord) -> Set<Leg> {
        var gaps: Set<Leg> = []
        if record.segmentName == nil && record.routeDesignation == nil { gaps.insert(.name) }
        if record.owner == nil { gaps.insert(.owner) }
        if record.yearLastConstruction == nil && record.yearLastImprovement == nil
            && record.bridge == nil && record.plattedDate == nil && record.declaration == nil {
            gaps.insert(.date)
        }
        return gaps
    }

    /// Why there is no construction year, in one line short enough to read at speed.
    ///
    /// `explanation(for:)` is the paragraph version, and it belongs on the result screen where
    /// there is time to read it. This is the glance version, and it exists because a missing
    /// year currently renders as *nothing at all* — the row simply vanishes, which reads as a
    /// broken app rather than as the edge of what any agency publishes. Verified: neither the
    /// Arizona nor the Maricopa profile carries a `dateCaveat`, so a Phoenix city street shows
    /// a hole today.
    ///
    /// Returns nil when a date was found, so the caller can show the date instead.
    public func shortDateNote(for record: RoadRecord) -> String? {
        guard missing(in: record).contains(.date) else { return nil }
        switch level {
        case .national:
            return "No local road source mapped here"
        case .state, .county:
            if let caveat = dateCaveats.first {
                return AgencyText.summary(caveat, limit: 52)
            }
            return "No construction date published"
        }
    }

    /// The sentence the card shows, or nil when nothing needs explaining.
    ///
    /// Written to name the gap and its cause in the user's terms. A blank field with no
    /// explanation reads as a broken app; "Pennsylvania publishes a construction year only for
    /// roads it maintains itself" reads as an answer.
    public func explanation(for record: RoadRecord) -> String? {
        let gaps = missing(in: record)
        guard !gaps.isEmpty else { return nil }
        let place = jurisdiction?.description

        switch level {
        case .national:
            guard gaps.contains(.owner) else { break }
            let where_ = place.map { "for \($0)" } ?? "for this area"
            return "No local road source is mapped \(where_) yet."
                + (record.segmentName != nil ? " The name comes from Census TIGER/Line, which"
                   + " carries no ownership or construction date." : "")
        case .state, .county:
            if gaps.contains(.date), !dateCaveats.isEmpty {
                return dateCaveats.joined(separator: " ")
            }
            if gaps.contains(.owner), let place {
                return "No source consulted for \(place) names a maintaining agency for this road."
            }
        }
        return nil
    }
}
