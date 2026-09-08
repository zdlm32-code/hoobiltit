import Foundation

/// A public-records contact route, loaded from the bundled directory.
///
/// Bundled rather than fetched: none of these agencies publishes a machine-readable contact
/// endpoint, and a stale-but-dated URL is more useful than none. Anything shown from here must
/// carry `isBundled` provenance so the UI can say how old it is.
public struct Agency: Sendable, Hashable, Codable {
    public let id: String
    public let name: String
    /// The state FIPS this agency serves, matched against the state the pin falls in. Without
    /// it a county owner returned MCDOT in all fifty states, and a road in Phoenix, Oregon
    /// returned the records office of Phoenix, Arizona.
    public let stateFIPS: String
    public var shortName: String?
    public var requestURL: URL?
    public var portalURL: URL?
    public var mailingAddress: String?
    public var phone: String?
    public var email: String?
    /// What is worth knowing before writing to this particular agency.
    public var guidance: String?
}

/// The bundled agency directory.
public struct AgencyDirectory: Sendable {
    public let capturedOn: Date
    public let agencies: [Agency]

    private struct Payload: Decodable {
        let capturedOn: String
        let agencies: [Agency]
    }

    public static let bundled: AgencyDirectory = {
        guard let url = Bundle.module.url(forResource: "agencies", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let payload = try? JSONDecoder().decode(Payload.self, from: data)
        else {
            return AgencyDirectory(capturedOn: .distantPast, agencies: [])
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return AgencyDirectory(capturedOn: formatter.date(from: payload.capturedOn) ?? .distantPast,
                               agencies: payload.agencies)
    }()

    public init(capturedOn: Date, agencies: [Agency]) {
        self.capturedOn = capturedOn
        self.agencies = agencies
    }

    /// The agency to write to for a given owner in a given state, or nil when the directory has
    /// no entry — which is the common case and must be said, not papered over with a wrong
    /// address.
    ///
    /// `stateFIPS` is required rather than optional on purpose. Every branch here used to answer
    /// from a four-entry Arizona directory with no idea where the pin was: `.county` returned
    /// MCDOT unconditionally, so a county road in Ohio addressed its records request to Maricopa
    /// County. Nil is the correct answer far more often than not, and `ResultScreen` already
    /// renders it properly.
    public func agency(for owner: RoadOwner, inState stateFIPS: String?) -> Agency? {
        guard let stateFIPS, !stateFIPS.isEmpty else { return nil }
        let here = agencies.filter { $0.stateFIPS == stateFIPS }
        guard !here.isEmpty else { return nil }

        switch owner {
        case .county, .countyCourtesy:
            // Only sound because the directory holds one county per state. A second county in
            // the same state needs matching on the owner's name, as the other branches do.
            return here.first { $0.id == "mcdot" }
        case .state(let agency), .federal(let agency), .tribal(let agency),
             .tollAuthority(let agency):
            return matching(name: agency, in: here)
        case .municipality(let name, _):
            return matching(name: name, in: here)
        case .privateOwner, .notPubliclyMaintained, .undetermined:
            return nil
        }
    }

    /// Case-insensitive containment in either direction, so "Arizona Department of
    /// Transportation" finds the entry named "Arizona Department of Transportation (ADOT)"
    /// and vice versa.
    ///
    /// The length floor is not defensive padding: without it a one- or two-character agency
    /// name matches by accident — "X" is a substring of "CITY OF PHOENIX", and returning
    /// Phoenix's records office for an unnamed state road is exactly the class of confidently
    /// wrong answer this app refuses to give.
    private func matching(name: String, in candidates: [Agency]) -> Agency? {
        let wanted = name.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard wanted.count >= 4 else { return nil }
        return candidates.first {
            let known = $0.name.uppercased()
            return known.contains(wanted) || wanted.contains(known)
        }
    }
}

/// Builds the public-records request the app cannot answer for you.
///
/// This is the fallback path, and it is a first-class answer rather than an apology: the
/// contractor and the award amount genuinely have no API in this county, so a well-formed
/// request citing the segment and whatever identifiers were resolved is the real next step.
public enum RecordsRequest {
    /// Each state's public-records statute, keyed on state FIPS exactly as
    /// `Jurisdiction.stateNames` is.
    ///
    /// This was a single `static let` holding Arizona's citation, printed into every letter the
    /// app drafted. Nineteen states are covered, so eighteen of them were being told that
    /// Arizona law obliged them to answer. Citing a statute is worth doing — it sets the
    /// obligation and the clock — but citing the wrong one is worse than citing none, and the
    /// only honest fallback for a state not listed here is to leave it out.
    ///
    /// Only states this build actually covers are listed. Adding a state to `coverage.json`
    /// without adding it here degrades to the no-citation wording rather than to a wrong one.
    public static let statutes: [String: String] = [
        "04": "A.R.S. § 39-121",              // Arizona
        "10": "29 Del. C. § 10003",           // Delaware
        "13": "O.C.G.A. § 50-18-71",          // Georgia
        "19": "Iowa Code § 22.2",             // Iowa
        "21": "KRS 61.872",                   // Kentucky
        "22": "La. R.S. 44:31",               // Louisiana
        "25": "M.G.L. c. 66, § 10",           // Massachusetts
        "26": "MCL 15.233",                   // Michigan
        "30": "Mont. Code Ann. § 2-6-1003",   // Montana
        "33": "RSA 91-A:4",                   // New Hampshire
        "35": "NMSA 1978, § 14-2-1",          // New Mexico
        "36": "N.Y. Pub. Off. Law § 87",      // New York
        "37": "N.C.G.S. § 132-6",             // North Carolina
        "39": "Ohio Rev. Code § 149.43",      // Ohio
        "42": "65 P.S. § 67.701",             // Pennsylvania
        "46": "SDCL 1-27-1",                  // South Dakota
        "48": "Tex. Gov't Code § 552.021",    // Texas
        "50": "1 V.S.A. § 316",               // Vermont
        "51": "Va. Code § 2.2-3704",          // Virginia
    ]

    /// The statute to cite where the pin is, or nil to cite none.
    public static func statute(forState stateFIPS: String?) -> String? {
        stateFIPS.flatMap { statutes[$0] }
    }

    public static func draft(for record: RoadRecord, agency: Agency?) -> String {
        var lines: [String] = []

        // Travels with the text. The screen says "verify before relying on them" in a footer
        // the user leaves behind the moment they hit share, and the letter reads as finished.
        lines.append("[DRAFT — check the agency, the statute and the contents before sending.]")
        lines.append("")
        lines.append("To: \(agency?.name ?? "the agency responsible for this road")")
        lines.append("Subject: Public records request — construction and contract records for "
                     + (record.segmentName?.value ?? "a road segment"))
        lines.append("")
        // No statute for this state means no citation, not somebody else's citation.
        if let statute = statute(forState: record.coverage?.jurisdiction?.stateFIPS) {
            lines.append("Under \(statute), I request copies of the records described below.")
        } else {
            lines.append("Under your state's public records law, I request copies of the records "
                         + "described below.")
        }
        lines.append("")
        lines.append("Road segment")
        lines.append(contentsOf: segmentLines(record).map { "  \($0)" })
        lines.append("")
        lines.append("Records requested")
        lines.append(contentsOf: [
            "  1. The construction plans and as-built drawings for this segment.",
            "  2. The project file for the most recent construction or reconstruction, including",
            "     the engineer's estimate and the notice to proceed.",
            "  3. The bid tabulation and the contract award for that project, showing the",
            "     awarded contractor, the award amount, and the award date.",
            "  4. Any right-of-way acquisition or road declaration document for this segment.",
        ].map { $0 })

        if let guidance = agency?.guidance {
            lines.append("")
            lines.append("Note: \(guidance)")
        }
        return lines.joined(separator: "\n")
    }

    /// Everything the app resolved that helps an records officer find the file. Identifiers
    /// first — a project number will beat any description.
    static func segmentLines(_ record: RoadRecord) -> [String] {
        var lines: [String] = []
        if let name = record.segmentName?.value ?? record.routeDesignation?.value {
            lines.append("Road: \(name)")
        }
        if let cross = record.crossStreets?.value { lines.append("Between: \(cross)") }
        if let jurisdiction = record.jurisdiction?.value { lines.append("Jurisdiction: \(jurisdiction)") }
        if let project = record.project?.value.projectNumber {
            lines.append("Project number: \(project)")
        }
        if let improvement = record.lastKnownImprovement?.value.projectNumber {
            lines.append("Related project number: \(improvement)")
        }
        if let file = record.declaration?.value.roadFileNumber {
            // MCDOT files by road file number; quoting it beats any description.
            lines.append("County road file: \(file)")
        }
        if let plat = record.plat?.value {
            let book = plat.recorderNumber.map { " (recorded \($0))" } ?? ""
            lines.append("Subdivision: \(plat.subdivisionName)\(book)")
        }
        if let acquisition = record.acquisition?.value, let number = acquisition.recorderNumber {
            lines.append("Right-of-way document: \(number) (\(acquisition.method))")
        }
        if let district = record.maintenanceDistrict?.value {
            lines.append("Maintenance district: \(district)")
        }
        if let district = record.supervisorDistrict?.value {
            lines.append("Board of Supervisors district: \(district)")
        }
        let coordinate = record.query.coordinate
        lines.append("Coordinate: \(String(format: "%.6f, %.6f", coordinate.latitude, coordinate.longitude))")
        return lines
    }
}
