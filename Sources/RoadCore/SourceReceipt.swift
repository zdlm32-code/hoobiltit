import Foundation

/// What one source contributed to a record, and the receipt for it.
///
/// `Provenance` carries the exact query URL and the moment it was fetched — its own doc comment
/// says *"The UI must disclose this, along with `fetchedAt`"* — and until now nothing did. Per
/// field, the app showed only "according to X"; there was no screen anywhere that could tell you
/// when a claim was made or let you re-run the query behind it.
///
/// A receipt is per *source* rather than per field because that is the unit a reader reasons
/// about: not "who said the surface was asphalt" but "what did MCDOT actually answer, when, and
/// can I check it".
public struct SourceReceipt: Sendable, Hashable, Identifiable {
    public let sourceID: String
    public let sourceName: String
    /// Nil for a source that answered but contributed no field — it still has a note worth
    /// showing, and saying nothing about it would hide the fact that it was asked at all.
    public let url: URL?
    public let fetchedAt: Date?
    public let isBundled: Bool
    /// How many of the record's fields came from here.
    public let fieldCount: Int
    /// How those fields were tied to the segment. More than one is normal: MCDOT reads a name
    /// directly and concludes ownership.
    public let confidences: Set<MatchConfidence>
    public let outcome: SourceNote.Outcome?
    public let detail: String?

    public var id: String { sourceID }

    public init(sourceID: String, sourceName: String, url: URL?, fetchedAt: Date?,
                isBundled: Bool, fieldCount: Int, confidences: Set<MatchConfidence>,
                outcome: SourceNote.Outcome?, detail: String?) {
        self.sourceID = sourceID
        self.sourceName = sourceName
        self.url = url
        self.fetchedAt = fetchedAt
        self.isBundled = isBundled
        self.fieldCount = fieldCount
        self.confidences = confidences
        self.outcome = outcome
        self.detail = detail
    }
}

public extension RoadRecord {
    /// Every source that was asked, what it gave, and the receipt for it.
    ///
    /// Ordered by contribution — the sources that actually answered first, then the ones that
    /// found nothing or failed, which are listed rather than hidden. An empty MCDOT response is
    /// how the app learns a city maintains the road, and that is worth reading.
    var receipts: [SourceReceipt] {
        var byID: [String: (provenance: Provenance, fields: Int, confidences: Set<MatchConfidence>)] = [:]

        for (provenance, confidence) in attributions {
            if var existing = byID[provenance.sourceID] {
                existing.fields += 1
                existing.confidences.insert(confidence)
                // Keep the most recent receipt: a later query is the better thing to re-run.
                if provenance.fetchedAt > existing.provenance.fetchedAt {
                    existing.provenance = provenance
                }
                byID[provenance.sourceID] = existing
            } else {
                byID[provenance.sourceID] = (provenance, 1, [confidence])
            }
        }

        var seen = Set<String>()
        var receipts: [SourceReceipt] = []

        // Contributors first, in the order the notes list them so the pipeline's own order shows.
        for note in notes where byID[note.sourceID] != nil {
            let entry = byID[note.sourceID]!
            seen.insert(note.sourceID)
            receipts.append(SourceReceipt(
                sourceID: note.sourceID, sourceName: note.sourceName,
                url: entry.provenance.url, fetchedAt: entry.provenance.fetchedAt,
                isBundled: entry.provenance.isBundled, fieldCount: entry.fields,
                confidences: entry.confidences, outcome: note.outcome, detail: note.detail))
        }

        // A source that contributed a field but left no note. Should not happen — the resolver
        // writes one either way — but dropping the receipt silently would be worse than showing it.
        for (sourceID, entry) in byID where !seen.contains(sourceID) {
            receipts.append(SourceReceipt(
                sourceID: sourceID, sourceName: entry.provenance.sourceName,
                url: entry.provenance.url, fetchedAt: entry.provenance.fetchedAt,
                isBundled: entry.provenance.isBundled, fieldCount: entry.fields,
                confidences: entry.confidences, outcome: nil, detail: nil))
            seen.insert(sourceID)
        }

        // Then everything that was asked and had nothing to say.
        for note in notes where !seen.contains(note.sourceID) {
            seen.insert(note.sourceID)
            receipts.append(SourceReceipt(
                sourceID: note.sourceID, sourceName: note.sourceName,
                url: nil, fetchedAt: nil, isBundled: false, fieldCount: 0,
                confidences: [], outcome: note.outcome, detail: note.detail))
        }
        return receipts
    }

    /// Every attributed field's receipt, flattened.
    ///
    /// Listed explicitly rather than by reflection: a field added to `RoadRecord` and forgotten
    /// here goes unattributed, and a compile-time list is at least greppable. `contributesAnything`
    /// in `RoadResolver` is the same list for the same reason.
    private var attributions: [(Provenance, MatchConfidence)] {
        var found: [(Provenance, MatchConfidence)] = []
        func take<T>(_ field: Attributed<T>?) {
            guard let field else { return }
            found.append((field.provenance, field.confidence))
        }
        take(segmentName); take(owner); take(jurisdiction); take(annexation)
        take(classification); take(surface); take(plat); take(crossStreets)
        take(maintenanceDistrict); take(segmentIdentifier); take(supervisorDistrict)
        take(plattedDate); take(declaration); take(acquisition); take(parcel)
        take(bridge); take(funding); take(lastKnownImprovement)
        take(yearLastConstruction); take(yearLastImprovement); take(trafficCount)
        take(routeDesignation); take(project)
        return found
    }
}
