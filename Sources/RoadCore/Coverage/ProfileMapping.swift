import Foundation

/// Turns a mapped feature into record fields.
///
/// Shared by both generic adapters so that a decode rule — a null sentinel, a code table, a
/// year encoding — behaves identically whether a state publishes one fat polyline or a dozen
/// event tables.
public enum ProfileMapping {

    /// Reads a numeric field, honouring the profile's null sentinels.
    ///
    /// The sentinels are the whole reason this is not `feature[field].double`. PennDOT writes
    /// `YR_BUILT = 0` on every locally owned segment; Maricopa writes `-2208988800000`.
    public static func number(_ feature: ArcGISFeature, _ field: String?,
                              _ mapping: FieldMapping) -> Double? {
        guard let field, let value = feature[field].double, value.isFinite,
              !mapping.isNull(value)
        else { return nil }
        return value
    }

    /// A year, in whichever of the three observed encodings the profile declares.
    public static func date(_ feature: ArcGISFeature, _ field: String?,
                           _ mapping: FieldMapping) -> Date? {
        guard let field else { return nil }
        switch mapping.yearEncoding ?? .yearNumber {
        case .yearNumber:
            guard let year = number(feature, field, mapping), year > 1500, year < 2200
            else { return nil }
            return CalendarDate.januaryFirst(ofYear: Int(year))
        case .compactString:
            return feature[field].compactStringDate
        case .epochMilliseconds:
            // The accessor already rejects Esri's 1900-01-01 sentinel.
            guard let value = feature[field].double, !mapping.isNull(value) else { return nil }
            return feature[field].epochMillisecondsDate
        }
    }

    /// The first of the candidate name fields that yields text.
    ///
    /// Ordered rather than a single field because splitting a name across candidates is
    /// normal: King County and Cook County carry left- and right-of-centreline variants, and
    /// PennDOT's route designation is a prefix field plus a number field.
    public static func text(_ feature: ArcGISFeature, _ fields: [String]?,
                            _ mapping: FieldMapping) -> String? {
        guard let fields else { return nil }
        for field in fields {
            if let value = feature[field].text, !mapping.isNull(value) { return value }
        }
        return nil
    }

    /// Joins candidate fields into one string, for designations assembled from parts.
    ///
    /// A part that is a null sentinel drops out, and if nothing survives the whole
    /// designation is absent rather than a string of sentinels.
    public static func joined(_ feature: ArcGISFeature, _ fields: [String]?,
                              _ mapping: FieldMapping) -> String? {
        guard let fields else { return nil }
        let parts = fields.compactMap { field -> String? in
            guard let value = feature[field].text, !mapping.isNull(value) else { return nil }
            return value
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    /// Decodes an ownership field through whichever shipped table the profile names.
    ///
    /// Returns nil for a code the table does not contain, rather than falling back to a
    /// likeliest guess. An unrecognised code means the app does not know who owns this road,
    /// and `RoadOwner` has a case that says exactly that.
    public static func owner(_ feature: ArcGISFeature, _ mapping: FieldMapping) -> RoadOwner? {
        if let rules = mapping.ownershipRules {
            for rule in rules {
                if let owner = self.owner(feature, rule: rule, mapping) { return owner }
            }
            return nil
        }
        guard let field = mapping.ownership else { return nil }
        // Read before the numeric decode: this field holds "Bexar County", not a code, and
        // `CodeTables.code` would take the leading digits of a name and invent an owner.
        if mapping.ownershipTable == .ohioJurisdiction {
            return feature[field].text.flatMap { CodeTables.owner(ohio: $0) }
        }
        if mapping.ownershipTable == .adotOwnership {
            guard let text = feature[field].text, !mapping.isNull(text) else { return nil }
            return CodeTables.owner(adot: text)
        }
        if mapping.ownershipTable == .dallasMaintenance {
            return CodeTables.owner(dallas: feature[field].text)
        }
        if mapping.ownershipTable == .namedAgency {
            guard var text = feature[field].text, !mapping.isNull(text) else { return nil }
            if let renamed = mapping.ownerNames?[text] {
                guard !renamed.isEmpty else { return nil }
                text = renamed
            }
            return CodeTables.owner(named: text)
        }
        guard let code = CodeTables.code(feature[field]) else { return nil }
        switch mapping.ownershipTable {
        case .hpmsOwnership:        return CodeTables.owner(hpms: code)
        case .penndotJurisdiction:  return CodeTables.owner(penndot: code)
        case .txdotAdmin:           return CodeTables.owner(txdot: code)
        case .fhwaFunctionalClass, .dallasRehabType, .namedAgency, .dallasMaintenance,
             .adotOwnership, .ncdotImprovement, .ohioJurisdiction, .none:
            return nil
        }
    }

    /// One rule's answer, or nil so the next may try.
    static func owner(_ feature: ArcGISFeature, rule: OwnershipRule,
                      _ mapping: FieldMapping) -> RoadOwner? {
        var kind: RoadOwner?
        if rule.table == .namedAgency {
            guard var text = feature[rule.field].text, !mapping.isNull(text) else { return nil }
            if let renamed = rule.names?[text] {
                guard !renamed.isEmpty else { return nil }
                text = renamed
            }
            kind = CodeTables.owner(named: text)
        } else if rule.table == .adotOwnership {
            kind = feature[rule.field].text.flatMap { CodeTables.owner(adot: $0) }
        } else if rule.table == .hpmsOwnership {
            kind = CodeTables.code(feature[rule.field]).flatMap { CodeTables.owner(hpms: $0) }
        } else if rule.table == .penndotJurisdiction {
            kind = CodeTables.code(feature[rule.field]).flatMap { CodeTables.owner(penndot: $0) }
        } else if rule.table == .ohioJurisdiction {
            kind = feature[rule.field].text.flatMap { CodeTables.owner(ohio: $0) }
        } else if rule.table == .txdotAdmin {
            kind = CodeTables.code(feature[rule.field]).flatMap { CodeTables.owner(txdot: $0) }
        }
        guard let kind else { return nil }
        // The code gave the level; a name field, where the layer has one, gives the body.
        guard let nameField = rule.nameField,
              let body = feature[nameField].text, !mapping.isNull(body)
        else { return kind }
        return kind.renamed(to: body)
    }

    public static func functionalClass(_ feature: ArcGISFeature, _ mapping: FieldMapping) -> String? {
        guard let field = mapping.functionalClass else { return nil }
        guard mapping.functionalClassTable == .fhwaFunctionalClass else {
            // Not a coded field, or coded in a scheme this build does not ship — New York's
            // two-digit extended classes, for instance. The agency's own text is better than
            // a wrong decode.
            return feature[field].text
        }
        guard let code = CodeTables.code(feature[field]) else { return nil }
        return CodeTables.functionalClass[code]
    }

    /// Pavement as a city layer publishes it.
    ///
    /// Requires a type: a bare condition score with nothing it describes is not worth a row on
    /// the card, and `SurfaceDescription.type` is non-optional for that reason.
    public static func surface(_ feature: ArcGISFeature, _ mapping: FieldMapping) -> SurfaceDescription? {
        guard let field = mapping.surface, let published = feature[field].text,
              !mapping.isNull(published)
        else { return nil }
        let type = mapping.surfaceNames?[published] ?? published
        return SurfaceDescription(
            type: type,
            widthFeet: number(feature, mapping.widthFeet, mapping).map { Int($0) },
            conditionIndex: number(feature, mapping.conditionIndex, mapping),
            conditionRating: mapping.condition.flatMap { feature[$0].text }
                .flatMap { mapping.isNull($0) ? nil : $0 })
    }

    /// The one dated job a city pavement layer records against a segment.
    ///
    /// Returns nil when the layer says no work was done, which is a real answer and not a gap:
    /// Dallas writes `rehab_type = "None"` on 11,007 of its 38,564 segments.
    public static func work(_ feature: ArcGISFeature, _ mapping: FieldMapping,
                            now: Date = Date()) -> RoadWork? {
        guard let typeField = mapping.workType,
              let published = feature[typeField].text, !mapping.isNull(published)
        else { return nil }
        var title = published
        // A pavement survey codes what was done and the code decides; a capital-project
        // register does not, because every row in it is a project. `workKindDefault` is how a
        // profile says which of the two it is.
        let kind: RoadWorkKind
        switch mapping.workTypeTable {
        case .dallasRehabType:
            guard let decoded = CodeTables.workKind(dallas: title) else { return nil }
            kind = decoded
        case .ncdotImprovement:
            // The layer stores a two-letter code; the agency's own domain spells it out.
            guard let decoded = CodeTables.work(ncdot: title) else { return nil }
            title = decoded.label
            kind = decoded.kind
        default:
            guard let declared = mapping.workKindDefault else { return nil }
            kind = declared
        }
        // Undated work is not worth a row. The entire point of a work entry is to date the
        // road, and "Crack Sealing, undated" tells a reader nothing they did not already know
        // from standing on it.
        guard let when = date(feature, mapping.workYear, mapping) else { return nil }
        return RoadWork(projectNumber: nil,
                        title: title,
                        detail: text(feature, mapping.workDetail.map { [$0] }, mapping),
                        location: text(feature, mapping.workLocation.map { [$0] }, mapping)
                            ?? crossStreets(feature, mapping),
                        letDate: when,
                        cost: number(feature, mapping.workCost, mapping).flatMap { $0 >= 100 ? $0 : nil },
                        contractor: text(feature, mapping.workContractor.map { [$0] }, mapping),
                        kind: kind,
                        // A city's project register carries work that has not happened yet,
                        // exactly as the state's does, and it must be labelled the same way.
                        isPlanned: when > now)
    }

    /// Nil when both ends name the same street, which a cul-de-sac or a loop does: Dallas
    /// writes `from_name == to_name` there, and "between Shadow Ridge Dr and Shadow Ridge Dr"
    /// reads as a bug rather than as a dead end.
    static func crossStreets(_ feature: ArcGISFeature, _ mapping: FieldMapping) -> String? {
        guard let from = mapping.crossStreetFrom.flatMap({ feature[$0].text }),
              let to = mapping.crossStreetTo.flatMap({ feature[$0].text }),
              from != to
        else { return nil }
        return "\(from) to \(to)"
    }

    /// Applies everything a mapping describes onto a fragment.
    ///
    /// Only fills empty slots, so the caller controls precedence by the order it applies
    /// layers — which is how Louisiana's dedicated ownership table beats the copy of the same
    /// field on its route layer.
    public static func apply(_ feature: ArcGISFeature,
                             mapping: FieldMapping,
                             provenance: Provenance,
                             confidence: MatchConfidence,
                             now: Date = Date(),
                             to fragment: inout RoadFragment) {
        if fragment.segmentName == nil,
           let name = joined(feature, mapping.nameParts, mapping) ?? text(feature, mapping.name, mapping) {
            fragment.segmentName = Attributed(name, provenance: provenance, confidence: confidence)
        }
        if fragment.routeDesignation == nil, let route = joined(feature, mapping.routeDesignation, mapping) {
            fragment.routeDesignation = Attributed(route, provenance: provenance, confidence: confidence)
        }
        if fragment.owner == nil, let owner = owner(feature, mapping) {
            fragment.owner = Attributed(owner, provenance: provenance, confidence: confidence)
        }
        if fragment.classification == nil, let classification = functionalClass(feature, mapping) {
            fragment.classification = Attributed(classification, provenance: provenance, confidence: confidence)
        }
        if fragment.yearLastConstruction == nil, let built = date(feature, mapping.yearBuilt, mapping) {
            fragment.yearLastConstruction = Attributed(built, provenance: provenance, confidence: confidence)
        }
        if fragment.yearLastImprovement == nil, let improved = date(feature, mapping.yearImproved, mapping),
           improved != fragment.yearLastConstruction?.value {
            // Only when it says something new. Arlington records a street rebuilt in one go as
            // installed and replaced on the same day, and "built 5 Dec 2005, improved 5 Dec
            // 2005" is two rows spent on one fact — the rule the drive card already follows.
            fragment.yearLastImprovement = Attributed(improved, provenance: provenance, confidence: confidence)
        }
        if fragment.trafficCount == nil, let aadt = number(feature, mapping.aadt, mapping), aadt > 0 {
            fragment.trafficCount = Attributed(Int(aadt), provenance: provenance, confidence: confidence)
        }
        if fragment.annexation == nil {
            let ordinance = text(feature, mapping.annexationOrdinance.map { [$0] }, mapping)
            let when = date(feature, mapping.annexationDate, mapping)
            if ordinance != nil || when != nil {
                fragment.annexation = Attributed(
                    AnnexationReference(ordinance: ordinance, ordinanceDate: when),
                    provenance: provenance, confidence: confidence)
            }
        }
        if fragment.surface == nil, let surface = surface(feature, mapping) {
            fragment.surface = Attributed(surface, provenance: provenance, confidence: confidence)
        }
        if fragment.works == nil, let work = work(feature, mapping, now: now) {
            fragment.works = Attributed([work], provenance: provenance, confidence: confidence)
        }
        if fragment.structureNumber == nil,
           let number = mapping.structureNumber.flatMap({ feature[$0].text }),
           !mapping.isNull(number) {
            fragment.structureNumber = Attributed(number, provenance: provenance,
                                                  confidence: confidence)
        }
        if fragment.crossStreets == nil, let pair = crossStreets(feature, mapping) {
            fragment.crossStreets = Attributed(pair.replacingOccurrences(of: " to ", with: " and "),
                                               provenance: provenance, confidence: confidence)
        }
    }
}
