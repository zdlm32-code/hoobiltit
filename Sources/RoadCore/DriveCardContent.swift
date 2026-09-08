import Foundation

/// What drive mode says about the road you are on, as plain strings.
///
/// Pulled out of the view for two reasons. It is the content of the drive card *and* of the
/// Live Activity on the lock screen, and those two must never be able to disagree about what
/// road you are on. And it is pure Foundation, so it crosses into the widget extension without
/// dragging SwiftUI or MapKit with it, and it is testable on macOS where neither ActivityKit
/// nor UIKit exists.
public struct DriveCardContent: Sendable, Hashable, Codable {
    /// Road identity, for deciding whether two readings are the same road.
    public var key: String?
    public var roadName: String?
    /// Which stretch: cross streets, else the place.
    public var context: String?
    public var owner: String?
    /// Construction and improvement, kept apart. Never fused.
    public var years: [String]
    /// Why there is no year, when there is none.
    public var dateNote: String?
    public var details: [String]
    public var tier: String?

    public init(record: RoadRecord?, placeName: String? = nil) {
        guard let record else {
            self.init(key: nil, roadName: nil, context: nil, owner: nil, years: [],
                      dateNote: nil, details: [], tier: nil)
            return
        }
        let name = record.segmentName?.value ?? record.routeDesignation?.value
        let years = Self.years(of: record)
        self.init(
            key: name.map { RoadName.comparisonKey($0) },
            roadName: name,
            context: record.crossStreets?.value ?? placeName
                ?? record.coverage?.jurisdiction?.description,
            owner: record.owner?.displayNameWithConfidence,
            years: years,
            dateNote: years.isEmpty ? record.coverage?.shortDateNote(for: record) : nil,
            details: Self.details(of: record),
            tier: Self.tier(of: record))
    }

    public init(key: String?, roadName: String?, context: String?, owner: String?,
                years: [String], dateNote: String?, details: [String], tier: String?) {
        self.key = key
        self.roadName = roadName
        self.context = context
        self.owner = owner
        self.years = years
        self.dateNote = dateNote
        self.details = details
        self.tier = tier
    }

    /// Construction and improvement kept apart, and both shown. Laying a road is not repaving
    /// it, and a card that silently picks one hides half the road's history.
    ///
    /// Says "Buildings", never "Frontage". "Frontage road" is a road *type*, so a card reading
    /// "Frontage built 2010" states what kind of road you are on, which is not what the number
    /// means — it is the year the buildings along the road went up.
    static func years(of record: RoadRecord) -> [String] {
        var found: [String] = []
        let builtYear = record.yearLastConstruction.map { CalendarDate.year($0.value) }
        let improvedYear = record.yearLastImprovement.map { CalendarDate.year($0.value) }
        if let builtYear { found.append("Built \(builtYear)") }
        // Only when it says something new. ADOT frequently records the same year for both — a
        // road built and surfaced in one season — and "Built 2004 · Resurfaced 2004" is two
        // facts' worth of space spent on one.
        if let improvedYear, improvedYear != builtYear {
            found.append("Resurfaced \(improvedYear)")
        }
        // A state that dates its roads only through its construction register, as Texas does,
        // reaches the card here. The date is when the contract was *let*, so the wording never
        // claims more than that — a job let in December was not finished in December.
        if found.isEmpty, let works = record.works?.value {
            if let built = works.first(where: { $0.kind == .built && !$0.isPlanned }),
               let year = built.letDate.map({ CalendarDate.year($0) }) {
                found.append("Built under a \(year) contract")
            }
            if let kept = works.first(where: { $0.kind == .maintained && !$0.isPlanned }),
               let year = kept.letDate.map({ CalendarDate.year($0) }),
               !found.contains(where: { $0.hasSuffix("\(year) contract") }) {
                found.append("Resurfaced \(year)")
            }
        }
        if found.isEmpty, let declared = record.declaration?.value.effectiveDate {
            found.append("Public road since \(CalendarDate.year(declared))")
        }
        if found.isEmpty, let bridge = record.bridge?.value, let built = bridge.yearBuilt {
            found.append("Bridge built \(built)")
            // NBI writes 0, not null, for "never rebuilt".
            if let rebuilt = bridge.yearReconstructed, rebuilt > 0 {
                found.append("Rebuilt \(rebuilt)")
            }
        }
        if found.isEmpty, let range = record.parcel?.value.constructionYearRange {
            found.append("Buildings built \(range.lowerBound)\u{2013}\(range.upperBound)")
        } else if found.isEmpty, let year = record.parcel?.value.constructionYear {
            found.append("Buildings built \(year)")
        }
        return found
    }

    /// The smaller facts, in the order a driver would care about them: what kind of road this
    /// is, how it is built, how busy it is. That is also the right order to lose them in when
    /// the line has to truncate, so the pinned order doubles as the responsive rule.
    static func details(of record: RoadRecord) -> [String] {
        var parts: [String] = []
        if let classification = record.classification?.value { parts.append(classification) }
        if let surface = record.surface?.value {
            if let lanes = surface.laneCount { parts.append("\(lanes) lanes") }
            if let phrase = surface.conditionPhrase {
                parts.append(phrase)
            }
        }
        if let traffic = record.trafficCount?.value {
            parts.append("\(traffic.formatted(.number)) vehicles a day")
        }
        return parts
    }

    /// How deeply this place is covered. Named for the place, not the tier: "Harris County"
    /// means something to a driver and "national" does not.
    static func tier(of record: RoadRecord) -> String? {
        guard let coverage = record.coverage else { return nil }
        switch coverage.level {
        case .county, .state: return coverage.jurisdiction.map { $0.placeName ?? $0.countyName }
        case .national:       return "Name only"
        }
    }

    /// Carries forward any slot this reading could not fill — but only on the same road.
    ///
    /// Sources fail independently, so between two refreshes on one road the assessor may answer
    /// and the traffic count may not, and a row would blink out and back. On a *different* road
    /// every slot resets, which is what stops the previous road's data bleeding onto the next.
    public func sticking(to previous: DriveCardContent) -> DriveCardContent {
        guard key != nil, key == previous.key else { return self }
        var merged = self
        merged.context = context ?? previous.context
        merged.owner = owner ?? previous.owner
        merged.tier = tier ?? previous.tier
        if years.isEmpty { merged.years = previous.years }
        if details.isEmpty { merged.details = previous.details }
        if merged.years.isEmpty { merged.dateNote = dateNote ?? previous.dateNote }
        return merged
    }
}
