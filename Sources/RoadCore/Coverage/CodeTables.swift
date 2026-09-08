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

    // MARK: - TxDOT

    /// TxDOT `ADMIN`. **Not HPMS**, and the second instance of the trap `penndotJurisdiction`
    /// warns about — made more inviting here because `ADMIN` sits in the same table as
    /// `F_SYSTEM`, which *is* the FHWA code space. Codes run 1...16, and HPMS defines nothing
    /// at 5-10 or 13-16, so reading them as HPMS would silently mint owners out of nothing.
    ///
    /// Derived rather than documented: the service publishes `ADMIN: NO DOMAIN`. Cross-tabbing
    /// every code against `HSYS`, the highway-system field, over all 1,027,891 statewide
    /// segments partitions perfectly — each `ADMIN` maps to exactly one family of systems,
    /// which is what an ownership field should do and what `MAINT_RESPON_IND` conspicuously
    /// did not:
    ///
    /// - `1` (289,274) - every TxDOT-maintained system: IH, US, SH, FM, RM, SL, business and
    ///   spur routes, park and forest roads.
    /// - `2` (302,900) - `CR` and nothing else.
    /// - `4` (427,315) - `LS` and nothing else.
    /// - `5`, `6`, `16` (3,237) - `TL`, whose `HWY` values read `TL0002`, `TL0003`... plus the
    ///   tolled state loops, such as Loop 1's express lanes.
    /// - `3`, `7`-`15` (5,165) - `FD` and nothing else.
    ///
    /// Confirmed against three roads whose owner is independently known: I-35 and Loop 343
    /// read `1`, and San Jacinto Blvd in Austin reads `4` and carries `SYSTEM = Off` on the
    /// companion roadways layer.
    public static let txdotAdmin: [Int: String] = [
        1: "Texas Department of Transportation",
        2: "County highway agency",
        3: "Federal agency",
        4: "City or municipal highway agency",
        5: "Toll authority",
        6: "Toll authority",
        7: "Federal agency",
        8: "Federal agency",
        9: "Federal agency",
        10: "Federal agency",
        11: "Federal agency",
        12: "Federal agency",
        13: "Federal agency",
        14: "Federal agency",
        15: "Federal agency",
        16: "Toll authority",
    ]

    /// TxDOT names the level of government but not the body, so neither does this.
    ///
    /// The nine federal codes are certainly nine *different* federal agencies - the Forest
    /// Service and an Army installation would not share a code - but `HWY` is null on every
    /// one of the 5,165 rows, so which is which is unrecoverable from the service. "Federal
    /// agency" is the whole of what can be shown to be true.
    public static func owner(txdot code: Int) -> RoadOwner? {
        guard let name = txdotAdmin[code] else { return nil }
        switch code {
        case 1:             return .state(agency: name)
        case 2:             return .county(agency: name)
        case 4:             return .municipality(name: name, fullName: name)
        case 5, 6, 16:      return .tollAuthority(agency: name)
        case 3, 7...15:     return .federal(agency: name)
        default:            return nil
        }
    }

    // MARK: - TxDOT project classes

    /// What a TxDOT project actually did, from `PROJ_CLASS`.
    ///
    /// Unlike `TYPE_OF_WORK`, which is free text ranging from "Widen Road - Add Lanes" to
    /// "GR, STRS, ASB, ACP, SIGNALIZATION", `PROJ_CLASS` is a controlled vocabulary of 66
    /// values. That is what makes it safe to decide, mechanically, whether a job built a road
    /// or merely maintained one — and the distinction is the whole product question here.
    /// **Seal Coat is the single largest class in the state at 26,101 projects**, so a rule
    /// that let maintenance answer "who built this road" would answer it wrongly more often
    /// than not.
    /// Verified live against a group-by over all 73,306 projects; counts are that census.
    static let txdotBuildClasses: Set<String> = [
        "New Location Freeway", "New Location Non-Freeway",
        "Convert Non-Freeway To Freeway", "Interchange (New or Reconstructed)",
        "Widen Freeway", "Widen Non-Freeway", "Systemic Widening Projects",
        "Bridge Replacement", "Bridge Widening or Rehabilitation",
        "Rehabilitation of Existing Road", "Restoration", "Super-2 Highway",
        "Upgrade to Standards Freeway", "Upgrade to Standards Non-Freeway",
        "Miscellaneous Construction", "Tunnel Construction",
    ]

    static let txdotMaintenanceClasses: Set<String> = [
        "Seal Coat", "Overlay", "Bridge Maintenance",
        "Bridge Preventative Maintenance", "Bridge Preventative Maintenance - Sealed",
        "Routine Maintenance Project", "Routine Maintenance Project - Sealed",
        "Material Maintenance Project", "Material Maintenance Project - Sealed",
        "Emergency Maintenance Project - Sealed", "Culvert & Storm Drainage Work",
    ]

    /// Classes reviewed and deliberately filed as ancillary, kept as a list so the decision is
    /// recorded rather than inferred from an absence.
    ///
    /// `Intersection & Operational Imprv` is the one worth arguing about: 787 projects, and at
    /// the I-35 test pin it is a **$30.1M** job whose description reads "ADD SHLDRS, AUX & TRN
    /// LNS". That is real roadwork. It stays ancillary because the question on the card is *who
    /// built this road*, and "the road was built by a 1988 freeway widening" is a better answer
    /// than "by a 2015 intersection improvement" even though the latter cost more. It still
    /// appears in the history, with its cost.
    ///
    /// `Preliminary Engineering` is the clearest case: at the same pin it is the single largest
    /// completed amount at **$53.5M**, and it is design work billed before construction starts.
    static let txdotAncillaryClasses: Set<String> = [
        "Safety Improvement Projects", "Hazard Elimination & Safety", "Safety Bond Projects",
        "Traffic Control Devices", "Traffic Signal", "Traffic Protection Devices",
        "Corridor Traffic Management", "Freeway Operational Improvements",
        "Intersection & Operational Imprv", "Landscape & Scenic Enhancement",
        "Pedestrian, Sidewalks & Curb Ramps", "Bicycle Infrastructure Improvements",
        "Preliminary Engineering", "Feasibility Studies", "Environmental Work Activities",
        "Right of Way", "Utility Adjustments", "Emergency Relief Projects", "Default",
        "Rail Hwy Crossing Signals/Structures", "Grade Crossing Protection", "Rail Replanking",
        "Railroad Relocation", "State Owned Rail Line", "Transportation Enhancement",
        "Transportation Non-Roadway", "Safety Rest Area", "Ferry Boat", "Port Infrastructure",
        "Border Crossing Facility", "Abatement Project", "Remove Hazardous Paint (Bridge)",
        "State Use Project", "State Use Project - Sealed", "Texas Park and Wildlife",
        "Military Bases and Federal Campus", "RPV - Legacy project classification",
        "ADD - Legacy project classification",
    ]

    /// An unrecognised class is `ancillary`, never `built`.
    ///
    /// The same rule `owner(hpms:)` follows, for the same reason: TxDOT can add a class to the
    /// vocabulary at any time, and the cost of guessing wrong is telling somebody a road was
    /// built by a job that painted its stripes. `probe.sh` warns when a new class appears.
    public static func workKind(txdot projectClass: String?) -> RoadWorkKind {
        guard let projectClass else { return .ancillary }
        let trimmed = projectClass.trimmingCharacters(in: .whitespacesAndNewlines)
        if txdotBuildClasses.contains(trimmed) { return .built }
        if txdotMaintenanceClasses.contains(trimmed) { return .maintained }
        return .ancillary
    }

    // MARK: - Owners a layer names outright

    /// Reads an owner from a field that names the body instead of coding it.
    ///
    /// City layers routinely do this, and it is *better* than a code: San Antonio's `Owner`
    /// runs to 43 values and includes `Bexar County`, `TxDOT`, `Ft Sam Houston`, `Lackland
    /// AFB`, `Port Authority of San Antonio` and — on 11,017 segments — `Private`. A code
    /// table could not carry that, and "this street is private" is a real answer to who built
    /// it: nobody public did.
    ///
    /// Matching is by shape rather than by an enumerated list, because the list is a register
    /// of every municipality and installation in a metro area and will grow.
    public static func owner(named value: String?) -> RoadOwner? {
        guard let raw = value?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty
        else { return nil }
        // San Antonio's "no value yet" marker, on 61 segments and also used in Surface_Type.
        guard raw != "TBD", raw != "Unknown", raw != "N/A" else { return nil }
        let upper = raw.uppercased()

        if upper.hasSuffix(" COUNTY") { return .county(agency: raw) }
        if upper == "PRIVATE" || upper == "PROPERTY OWNER" { return .privateOwner }
        if upper == "TXDOT" || upper == "STATE" || upper.hasPrefix("STATE ") {
            return .state(agency: raw == "TxDOT" ? "Texas Department of Transportation" : raw)
        }
        // Military installations, which a metro street layer carries a surprising number of.
        // Calling Lackland AFB a municipality would be plainly wrong.
        if upper.hasSuffix(" AFB") || upper.hasPrefix("FT ") || upper.hasPrefix("FORT ")
            || upper.hasPrefix("CAMP ") || upper.hasSuffix(" ARB") {
            return .federal(agency: raw)
        }
        // A layer that shouts its values reads badly as prose: "maintained by MERCEDES".
        let cased = raw == upper && raw.count > 3
            ? raw.capitalized(with: Locale(identifier: "en_US"))
            : raw
        // Everything else is a named local body. `municipality` is approximate for a port or
        // development authority, but the case only decides the wording around the name, and
        // the name itself — which is what the card shows — is exactly right.
        return .municipality(name: cased, fullName: cased)
    }

    // MARK: - Dallas maintenance responsibility

    /// City of Dallas `maint_resp`, seven values over 38,564 segments.
    ///
    /// Kept apart from `owner(named:)` because Dallas writes the *level* — "City", "State" —
    /// where San Antonio writes the body. Passed through `owner(named:)` a state highway in
    /// Dallas would read "maintained by State", which is true and useless; the city tier runs
    /// before the state tier, so this is the wording a Dallas freeway would show.
    public static let dallasMaintenance: [String: RoadOwner] = [
        "City": .municipality(name: "City of Dallas", fullName: "City of Dallas"),
        "City - Other": .municipality(name: "City of Dallas", fullName: "City of Dallas"),
        "City - Park": .municipality(name: "City of Dallas Park and Recreation",
                                     fullName: "City of Dallas Park and Recreation"),
        "State": .state(agency: "Texas Department of Transportation"),
        "State Shared": .state(agency: "Texas Department of Transportation"),
        "County Shared": .county(agency: "County highway agency"),
        "Intermunicipal": .municipality(name: "Shared between municipalities",
                                        fullName: "Shared between municipalities"),
    ]

    public static func owner(dallas value: String?) -> RoadOwner? {
        guard let raw = value?.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        return dallasMaintenance[raw]
    }

    // MARK: - Dallas pavement work

    /// City of Dallas `rehab_type`, a 21-value vocabulary over 38,564 street segments.
    ///
    /// The same build-versus-maintain judgement `PROJ_CLASS` needs, and the same reason for
    /// making it: `Slurry Seal` covers 6,549 segments and `Street Reconstruction` 6,577, so
    /// getting it wrong would mis-answer roughly half the city. `None`, on 11,007 segments,
    /// means no recorded work rather than an unknown kind, and yields no entry at all.
    public static func workKind(dallas rehabType: String?) -> RoadWorkKind? {
        guard let raw = rehabType?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty, raw != "None"
        else { return nil }
        let upper = raw.uppercased()
        // Replacing pavement panels, rebuilding to full depth or restoring the street is
        // construction; sealing, surfacing, overlaying and patching is upkeep of what is
        // already there. `Full-Depth Asphalt` (995 segments) and `Street Restoration` (546)
        // were both filed as upkeep until `probe.sh` flagged them — a full-depth rebuild is
        // the most thorough thing a city does to a street short of a new alignment.
        if upper.contains("RECONSTRUCT") || upper.contains("PANEL REPLACE")
            || upper.contains("REPLACE") || upper.contains("WIDEN")
            || upper.contains("FULL-DEPTH") || upper.contains("FULL DEPTH")
            || upper.contains("RESTORATION") {
            return .built
        }
        // `Alley Improvement` stays upkeep: it is the city's alley resurfacing programme, and
        // "improvement" in that name is a budget category rather than a description of work.
        return .maintained
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
