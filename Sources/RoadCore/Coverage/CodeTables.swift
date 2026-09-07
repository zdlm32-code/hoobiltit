import Foundation

/// Decode tables for the coded values state DOTs publish.
///
/// **No service publishes its own domains.** Every layer checked — ADOT layer 29, Iowa, TxDOT,
/// Louisiana, PennDOT — returns `domain: null` on its ownership field, and TxDOT says
/// `ADMIN: NO DOMAIN` outright. So the meaning of a `4` has to ship with the app; the agency
/// will not tell you.
///
/// Two code spaces genuinely standardise across states that share no field names, because
/// both are what FHWA requires in a state's annual HPMS submission. Everything else about a
/// state's schema is bespoke, and a profile that guesses the shared table applies is the most
/// likely source of a confidently wrong answer in this app — see `PennDOT` below.
public enum CodeTables {

    // MARK: - HPMS ownership

    /// FHWA HPMS Field Manual, "Ownership". Verified live: Louisiana's ownership layer emits
    /// `1,2,3,4,11,21,25,26,32,63,64,66,70,72,73,74,80` and the National Highway System emits
    /// `1,2,4`. Louisiana ships them as strings and the NHS as integers, so lookup normalises.
    ///
    /// Deliberately kept apart from `NBIBridgeSource.ownerNames`, which decodes NBI item 22.
    /// The two code spaces overlap almost entirely and it is tempting to merge them, but they
    /// are separately specified documents with their own wording, and the bridge source's
    /// phrasing is already shipped and tested. Merging would churn user-visible text to save
    /// a few lines.
    public static let hpmsOwnership: [Int: String] = [
        1: "State highway agency",
        2: "County highway agency",
        3: "Town or township highway agency",
        4: "City or municipal highway agency",
        11: "State park, forest or reservation agency",
        12: "Local park, forest or reservation agency",
        21: "Other state agency",
        25: "Other local agency",
        26: "Private owner",
        27: "Railroad",
        31: "State toll authority",
        32: "Local toll authority",
        40: "Other public instrumentality",
        50: "Indian tribe nation",
        60: "Other federal agency",
        62: "Bureau of Indian Affairs",
        63: "Bureau of Fish and Wildlife",
        64: "US Forest Service",
        66: "National Park Service",
        67: "Tennessee Valley Authority",
        68: "Bureau of Land Management",
        69: "Bureau of Reclamation",
        70: "Corps of Engineers",
        72: "Air Force",
        73: "Navy or Marines",
        74: "Army",
        80: "Other",
    ]

    /// The owner an HPMS code resolves to, or nil for a code this build does not know.
    ///
    /// Nil rather than a fallback: an unrecognised code means the app cannot say who owns the
    /// road, and `RoadOwner.undetermined` at least reports that honestly. Guessing "state"
    /// because most roads are state-owned would be wrong precisely where it matters.
    public static func owner(hpms code: Int) -> RoadOwner? {
        guard let name = hpmsOwnership[code] else { return nil }
        switch code {
        case 1, 11, 21:      return .state(agency: name)
        case 2:              return .county(agency: name)
        case 3, 4, 12, 25:   return .municipality(name: name, fullName: name)
        case 26, 27:         return code == 26 ? .privateOwner : .notPubliclyMaintained
        case 31, 32:         return .tollAuthority(agency: name)
        case 50, 62:         return .tribal(agency: name)
        case 60, 63, 64, 66, 67, 68, 69, 70, 72, 73, 74:
            return .federal(agency: name)
        default:             return nil   // 40 and 80 name no actual agency
        }
    }

    // MARK: - FHWA functional class

    /// FHWA functional system, 1–7. Verified as exactly `1...7` on Louisiana's layer 84, and
    /// seen with the same meanings on Texas `F_SYSTEM`, Iowa `FED_FUNCTIONAL_CLASS`, Ohio
    /// `FUNCTION_C` and CDOT.
    ///
    /// New York is the known exception and must not use this table: it publishes a two-digit
    /// extended scheme (`"19-Urban Local"`), so a NY profile needs its own map.
    public static let functionalClass: [Int: String] = [
        1: "Interstate",
        2: "Other freeway or expressway",
        3: "Other principal arterial",
        4: "Minor arterial",
        5: "Major collector",
        6: "Minor collector",
        7: "Local",
    ]

    // MARK: - PennDOT

    /// PennDOT `JURIS`. **Not HPMS**, and the trap this type exists to warn about.
    ///
    /// PennDOT also publishes `MAINT_RESPON_IND`, whose values are
    /// `10,19,20,29,30,39,40,49,50,60,69,70,80` — close enough to HPMS-times-ten to look
    /// usable, and it is not. Every segment in downtown Philadelphia returns `40`, including
    /// I-676, the Vine Street Expressway, at 64,768 AADT. Reading that as HPMS 4 would tell
    /// the user a state expressway is city-maintained. `MAINT_RESPON_IND` is also populated
    /// only on `JURIS = 1` rows, so it is not an ownership field at all.
    ///
    /// `JURIS` is: 1 = PennDOT (101,354 segments), 2 = Turnpike Commission (685),
    /// 5 = local (11,737), 6 = interstate bridge commission (51). Counts verified live.
    public static let penndotJurisdiction: [Int: String] = [
        1: "Pennsylvania Department of Transportation",
        2: "Pennsylvania Turnpike Commission",
        5: "Local government",
        6: "Interstate bridge commission",
    ]

    public static func owner(penndot code: Int) -> RoadOwner? {
        guard let name = penndotJurisdiction[code] else { return nil }
        switch code {
        case 1: return .state(agency: name)
        case 2: return .tollAuthority(agency: name)
        // PennDOT says only "somebody local", never which borough or township. Naming the
        // level of government without naming the body is the honest amount to claim.
        case 5: return .municipality(name: name, fullName: name)
        case 6: return .tollAuthority(agency: name)
        default: return nil
        }
    }

    // MARK: - Lookup

    /// Reads a code that may arrive as `4`, `"4"`, `"04"` or `"04-Municipal or City Hwy
    /// Agency"`, which are all forms observed across the states probed.
    public static func code(_ value: AttributeValue) -> Int? {
        if case .number(let d) = value, d.isFinite { return Int(d) }
        guard let text = value.text else { return nil }
        if let direct = Int(text) { return direct }
        // "04-Municipal or City Hwy Agency" and "70-Interstate" both lead with the code.
        let leading = text.prefix { $0.isNumber }
        return leading.isEmpty ? nil : Int(leading)
    }
}
