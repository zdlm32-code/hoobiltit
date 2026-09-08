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

    @Test("Every shipped profile is named somewhere in the checklist")
    func everyProfileListed() throws {
        let text = try #require(checklist)
        let catalog = CoverageCatalog.bundled
        // Matched on the display name's distinctive word rather than the whole string, since
        // the table phrases entries for a reader rather than quoting the catalog.
        let expected = ["Arizona", "Texas", "North Carolina", "Massachusetts", "Ohio",
                        "Pennsylvania", "Louisiana", "Virginia", "Maricopa", "Cameron",
                        "Dallas", "San Antonio", "Arlington", "Laredo", "Denver", "Edinburg",
                        "Pharr", "Irving", "Weslaco", "Brownsville", "McAllen"]
        #expect(expected.count == catalog.states.count + catalog.counties.count
                                  + catalog.placeProfiles.count)
        for name in expected {
            #expect(text.contains(name), "\(name) is shipped but not in the checklist")
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
