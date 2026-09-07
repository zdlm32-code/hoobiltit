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
        guard let field = mapping.ownership,
              let code = CodeTables.code(feature[field])
        else { return nil }
        switch mapping.ownershipTable {
        case .hpmsOwnership:        return CodeTables.owner(hpms: code)
        case .penndotJurisdiction:  return CodeTables.owner(penndot: code)
        case .fhwaFunctionalClass, .none: return nil
        }
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

    /// Applies everything a mapping describes onto a fragment.
    ///
    /// Only fills empty slots, so the caller controls precedence by the order it applies
    /// layers — which is how Louisiana's dedicated ownership table beats the copy of the same
    /// field on its route layer.
    public static func apply(_ feature: ArcGISFeature,
                             mapping: FieldMapping,
                             provenance: Provenance,
                             confidence: MatchConfidence,
                             to fragment: inout RoadFragment) {
        if fragment.segmentName == nil, let name = text(feature, mapping.name, mapping) {
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
        if fragment.yearLastImprovement == nil, let improved = date(feature, mapping.yearImproved, mapping) {
            fragment.yearLastImprovement = Attributed(improved, provenance: provenance, confidence: confidence)
        }
        if fragment.trafficCount == nil, let aadt = number(feature, mapping.aadt, mapping), aadt > 0 {
            fragment.trafficCount = Attributed(Int(aadt), provenance: provenance, confidence: confidence)
        }
        if fragment.crossStreets == nil,
           let from = mapping.crossStreetFrom.flatMap({ feature[$0].text }),
           let to = mapping.crossStreetTo.flatMap({ feature[$0].text }) {
            fragment.crossStreets = Attributed("\(from) and \(to)", provenance: provenance,
                                               confidence: confidence)
        }
    }
}
