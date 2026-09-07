import Foundation

/// Which jurisdictions this build can read, and how.
///
/// Ships in the app bundle and is refreshable from a static JSON file, so a state whose
/// endpoint moves can be fixed without an App Store release. That is the whole reason it is
/// data: adding a state on either generic adapter is a catalog edit, and only a county needing
/// Maricopa-depth judgement requires a build.
///
/// The honest boundary, which belongs in the catalog's own comment as well as here: the
/// catalog can **name, order, configure and disable** sources. It cannot **define** one.
public struct CoverageCatalog: Sendable, Codable {
    /// The highest schema this build understands. Entries asking for more are skipped
    /// individually — see `usable`.
    public static let supportedSchema = 1

    public var schemaVersion: Int
    /// Increases every publish. A downloaded catalog older than the bundled one is ignored,
    /// which is what stops an app update being undone by a stale file on disk.
    public var catalogVersion: Int
    public var capturedOn: String
    /// Keyed by two-digit state FIPS.
    public var states: [String: CoverageProfile]
    /// Keyed by five-digit county FIPS. Wins over the state entry where both apply.
    public var counties: [String: CoverageProfile]

    /// Entries this build can actually read.
    ///
    /// Per-entry rather than per-catalog on purpose: rejecting the whole file because one new
    /// state uses a field this build predates would turn a single addition into a total
    /// outage everywhere. A future entry degrades one jurisdiction.
    public func profile(forState fips: String) -> CoverageProfile? {
        usable(states[fips])
    }

    public func profile(forCounty fips: String) -> CoverageProfile? {
        usable(counties[fips])
    }

    private func usable(_ profile: CoverageProfile?) -> CoverageProfile? {
        guard let profile, profile.requiredSchema <= Self.supportedSchema else { return nil }
        // A catalog may only point the app at HTTPS. It decides which hosts the app calls,
        // so an entry carrying a plaintext URL is a redirect primitive, not a typo.
        if let service = profile.service,
           URL(string: service)?.scheme?.lowercased() != "https" { return nil }
        return profile
    }

    public var capturedDate: Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.date(from: capturedOn)
    }

    /// The copy compiled into the app. Always present, so a lookup never depends on the
    /// network having produced a catalog first.
    public static let bundled: CoverageCatalog = {
        guard let url = Bundle.module.url(forResource: "coverage", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(CoverageCatalog.self, from: data)
        else {
            // An empty catalog still runs: every pin falls to the national tier and the card
            // says so. Trapping here would take the whole app down over a resource problem.
            return CoverageCatalog(schemaVersion: supportedSchema, catalogVersion: 0,
                                   capturedOn: "1970-01-01", states: [:], counties: [:])
        }
        return decoded
    }()

    /// Picks between a downloaded catalog and the bundled one.
    ///
    /// Bundled wins on a tie or when it is newer, which is the case after an app update has
    /// shipped a fresher catalog than the file already on disk.
    public static func newer(_ downloaded: CoverageCatalog?, than bundled: CoverageCatalog) -> CoverageCatalog {
        guard let downloaded, downloaded.catalogVersion > bundled.catalogVersion else { return bundled }
        return downloaded
    }
}
