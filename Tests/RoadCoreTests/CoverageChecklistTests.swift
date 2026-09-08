import Foundation
import Testing
@testable import RoadCore

@Suite("The coverage checklist stays honest")
struct CoverageChecklistTests {
    /// `docs/COVERAGE.md`, found relative to this file so the test does not need a resource
    /// bundle and does not care where the package is checked out.
    private var checklist: String? {
        let here = URL(fileURLWithPath: #filePath)          // Tests/RoadCoreTests/…
        let root = here.deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        return try? String(contentsOf: root.appendingPathComponent("docs/COVERAGE.md"),
                           encoding: .utf8)
    }

    @Test("The count in the checklist matches the catalog it describes")
    func countMatches() throws {
        // A hand-written checklist drifts the moment a profile is added and the doc is not.
        // This is the cheapest possible guard against that, and it fails loudly.
        let text = try #require(checklist, "docs/COVERAGE.md is missing")
        let catalog = CoverageCatalog.bundled
        let shipped = catalog.states.count + catalog.counties.count + catalog.placeProfiles.count
        #expect(text.contains("**\(shipped) profiles shipped"),
                "COVERAGE.md says a different number than the catalog holds (\(shipped))")
    }

    /// The distinctive words of a display name — "City of Dallas pavement management" gives
    /// "Dallas" and "pavement". Used to look a profile up in prose that phrases things for a
    /// reader rather than quoting the catalog.
    private func stems(of displayName: String) -> [String] {
        let noise: Set<String> = ["city", "of", "county", "the", "and", "road", "roads",
                                  "street", "streets", "pavement", "inventory", "management",
                                  "centreline", "centerline", "department", "transportation",
                                  "capital", "projects", "history", "annexation", "treatments",
                                  "characteristics", "route", "master", "highways", "condition"]
        return displayName
            .split(whereSeparator: { !$0.isLetter })
            .map(String.init)
            .filter { $0.count > 2 && !noise.contains($0.lowercased()) }
    }

    @Test("Every shipped profile is named somewhere in the checklist")
    func everyProfileListed() throws {
        // Derived from the catalog rather than hand-listed. The hand-written array this
        // replaced had to be edited for every jurisdiction added, which is exactly the kind of
        // bookkeeping that stops being done around the fifth one.
        let text = try #require(checklist)
        let catalog = CoverageCatalog.bundled
        let all = Array(catalog.states.values) + Array(catalog.counties.values)
                + Array(catalog.placeProfiles.values)
        for profile in all {
            let words = stems(of: profile.displayName)
            #expect(words.contains { text.contains($0) },
                    "\(profile.displayName) is shipped but nothing in COVERAGE.md names it")
        }
    }

    @Test("The README's state list matches the states actually shipped")
    func readmeIsCurrent() throws {
        // It fell three states behind before anyone noticed, because nothing checked it.
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let readme = try #require(try? String(contentsOf: root.appendingPathComponent("README.md"),
                                              encoding: .utf8))
        // Keyed on the state's own name rather than the agency's: the README speaks to a
        // reader ("Ohio"), the catalog to a maintainer ("ODOT road inventory").
        for fips in CoverageCatalog.bundled.states.keys {
            let name = try #require(Jurisdiction.stateNames[fips], "unknown FIPS \(fips)")
            #expect(readme.contains(name),
                    "\(name) is shipped but the README's state list does not mention it")
        }
    }

    @Test("The rejections are recorded too, not just the wins")
    func rejectionsRecorded() throws {
        let text = try #require(checklist)
        // Each of these cost real probing, and the point of writing them down is that nobody
        // re-probes them from scratch. Harlingen especially: it looked shippable.
        for rejected in ["Harlingen", "Houston", "New York", "Seattle", "Chicago",
                         "Florida", "Token Required"] {
            #expect(text.contains(rejected), "\(rejected) was probed and should be recorded")
        }
    }
}
