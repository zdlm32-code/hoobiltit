import Foundation

/// A public-records contact route, loaded from the bundled directory.
///
/// Bundled rather than fetched: none of these agencies publishes a machine-readable contact
/// endpoint, and a stale-but-dated URL is more useful than none. Anything shown from here must
/// carry `isBundled` provenance so the UI can say how old it is.
public struct Agency: Sendable, Hashable, Codable {
    public let id: String
    public let name: String
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

    /// The agency to write to for a given owner, or nil when the directory has no entry —
    /// which is the common case for the valley's smaller towns and must be said, not papered
    /// over with a wrong address.
    public func agency(for owner: RoadOwner) -> Agency? {
        switch owner {
        case .county, .countyCourtesy:
            return agencies.first { $0.id == "mcdot" }
        case .state(let agency), .federal(let agency), .tribal(let agency),
             .tollAuthority(let agency):
            // Matched on the agency's own name rather than a fixed id. `.state` used to
            // return ADOT unconditionally, which was right while the app covered one state
            // and would hand a Pennsylvania driver Arizona's records office the moment it
            // did not. Nil is the correct answer for an agency this build has no address
            // for, and the records screen already says so rather than inventing one.
            return matching(name: agency)
        case .municipality(let name, _):
            return matching(name: name)
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
    private func matching(name: String) -> Agency? {
        let wanted = name.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard wanted.count >= 4 else { return nil }
        return agencies.first {
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
    /// Arizona's public records statute, worth citing because it sets the obligation.
    public static let statute = "A.R.S. § 39-121"

    public static func draft(for record: RoadRecord, agency: Agency?) -> String {
        var lines: [String] = []

        lines.append("To: \(agency?.name ?? "the agency responsible for this road")")
        lines.append("Subject: Public records request — construction and contract records for "
                     + (record.segmentName?.value ?? "a road segment"))
        lines.append("")
        lines.append("Under \(statute), I request copies of the records described below.")
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
        lines.append("")
        lines.append("This request is for a non-commercial purpose.")

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
