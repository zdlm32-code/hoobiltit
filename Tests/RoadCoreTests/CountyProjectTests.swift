import Foundation
import Testing
@testable import RoadCore
@testable import RoadSources

private let fixedNow = Date(timeIntervalSince1970: 1_757_000_000)

private func projects(_ transport: FixtureTransport) -> MaricopaCountyProjectSource {
    MaricopaCountyProjectSource(client: ArcGISClient(transport: transport), now: { fixedNow })
}

private let williamsPin = RoadQuery(latitude: 33.689441, longitude: -112.317668)

@Suite("County projects — capital vs maintenance")
struct CountyProjectTests {
    @Test("Reports the capital project that built the segment")
    func capitalProject() async throws {
        let fragment = try await projects(.williamsDrive).fetch(williamsPin)
        let project = try #require(fragment.project?.value)
        #expect(project.projectNumber == "TT0248")
        #expect(project.title.contains("Deer Valley Road"))
    }

    @Test("Keeps maintenance out of the field that answers who built it")
    func maintenanceIsSeparate() async throws {
        // TIP is capital work; MIP is slurry seals and crack seals. Reporting a slurry seal
        // as the thing that built a road would be wrong, so they never share a field.
        let fragment = try await projects(.williamsDrive).fetch(williamsPin)
        #expect(fragment.project != nil)
        #expect(fragment.lastKnownImprovement == nil)   // no MIP record on this segment
    }

    @Test("Strips the padded route ordinal from the project's location")
    func locationUsesRoadName() async throws {
        // Stored as "Williams Dr                             01".
        let fragment = try await projects(.williamsDrive).fetch(williamsPin)
        let location = try #require(fragment.project?.value.location)
        #expect(location == "Williams Dr: 123rd Ave to 117th Ave")
        #expect(!location.contains("01"))
    }
}

@Suite("County projects — the typed join to project status")
struct ProjectStatusJoinTests {
    @Test("Joins on project number rather than guessing again at geometry")
    func joinUpgradesConfidence() async throws {
        // The status table shares TIP's TTxxxx numbering, so this is a matched record.
        let fragment = try await projects(.williamsDrive).fetch(williamsPin)
        #expect(fragment.project?.confidence == .direct)
        #expect(fragment.project?.provenance.url.absoluteString.contains("ProjectStatus") == true)
    }

    @Test("Prefers the status table's public-facing write-up, rendered as plain text")
    func descriptionIsCleaned() async throws {
        let detail = try #require(try await projects(.williamsDrive).fetch(williamsPin).project?.value.detail)
        #expect(detail.contains("connection between the east end of Williams Drive"))
        // The stored value is raw HTML with entities and \r\n (ENDPOINTS.md §2.2).
        #expect(!detail.contains("<p>"))
        #expect(!detail.contains("&nbsp;"))
        #expect(!detail.contains("\r"))
    }

    @Test("Takes the status table's phase over the programme layer's")
    func phaseComesFromStatus() async throws {
        let fragment = try await projects(.williamsDrive).fetch(williamsPin)
        #expect(fragment.project?.value.phase == "Completed")
    }
}

@Suite("County projects — the corridor radius and its name gate")
struct CorridorRadiusTests {
    /// The pin sits ~206 m off the project line, inside the corridor radius but outside the
    /// tight one.
    let pin = RoadQuery(latitude: 33.6836, longitude: -112.2905)

    @Test("Accepts a project beyond the tight radius when the road names agree")
    func acceptsOnNameMatch() async throws {
        var resolved = RoadRecord(query: pin)
        resolved.segmentName = Attributed(
            "Deer Valley Rd",
            provenance: Provenance(sourceID: "t", sourceName: "t",
                                   url: URL(string: "https://example.test")!, fetchedAt: fixedNow)
        )
        let fragment = try await projects(.offCorridorProject).fetch(pin, resolved: resolved)
        #expect(fragment.project?.value.projectNumber == "TT0248")
    }

    @Test("Refuses it when no earlier source identified the road")
    func refusesWithoutAName() async throws {
        // Without a name to check against, a 206 m match could just as easily be the next
        // street over — so the source says nothing rather than guessing.
        let fragment = try await projects(.offCorridorProject).fetch(pin)
        #expect(fragment.project == nil)
        #expect(fragment.notes.first?.outcome == .foundNothing)
    }

    @Test("Refuses it when the road names disagree")
    func refusesOnNameMismatch() async throws {
        var resolved = RoadRecord(query: pin)
        resolved.segmentName = Attributed(
            "Jomax Rd",
            provenance: Provenance(sourceID: "t", sourceName: "t",
                                   url: URL(string: "https://example.test")!, fetchedAt: fixedNow)
        )
        let fragment = try await projects(.offCorridorProject).fetch(pin, resolved: resolved)
        #expect(fragment.project == nil)
    }

    @Test("Compares names insensitively to case and spacing")
    func nameNormalisation() {
        // Shared with the declaration and bridge sources; see RoadNameTests for the full set.
        #expect(RoadName.matches("Deer  Valley   Rd", "deer valley rd"))
    }
}

@Suite("County projects — point-located work")
struct SpotImprovementTests {
    /// A pin on McDowell Rd where the only work here is a drainage project stored as a point.
    let pin = RoadQuery(latitude: 33.466228, longitude: -111.667181)

    private func resolved(_ segment: String) -> RoadRecord {
        var record = RoadRecord(query: pin)
        record.segmentName = Attributed(segment, provenance: Provenance(
            sourceID: "t", sourceName: "t", url: URL(string: "https://example.test")!,
            fetchedAt: fixedNow))
        return record
    }

    @Test("Finds work a line query structurally cannot see")
    func spotProject() async throws {
        let fragment = try await projects(.mcDowellSpotProject)
            .fetch(pin, resolved: resolved("McDowell Rd"))
        let project = try #require(fragment.project?.value)

        #expect(project.projectNumber == "TT0408")
        #expect(project.title.contains("Palm Lane Drainage"))
        // The spot record is the one on this road; its location comes back clean.
        #expect(project.location == "McDowell Rd")
    }

    @Test("Prefers the spot record over the linear one for the same project")
    func rejectsTheLinearRecordOnAnotherStreet() async throws {
        // TT0408 is in both layers. The linear record is 401 m away and named for 78th St in
        // Mesa; taking it would report this segment as being on a street it is not.
        let fragment = try await projects(.mcDowellSpotProject)
            .fetch(pin, resolved: resolved("McDowell Rd"))
        #expect(fragment.project?.value.location != "78th St")
        #expect(fragment.project?.value.location?.contains("Mesa") != true)
    }

    @Test("Point geometry is measured, not silently dropped")
    func pointGeometryDecodes() throws {
        // Spot layers return bare x/y rather than paths; an earlier decoder read only paths
        // and rings, which made every spot feature invisible rather than visibly absent.
        let json = #"{"features":[{"attributes":{"ProjNum":"X"},"geometry":{"x":-111.667181,"y":33.466228}}]}"#
        let set = try JSONDecoder().decode(ArcGISFeatureSet.self, from: Data(json.utf8))
        let distance = try #require(set.features.first?.distance(from: pin.coordinate))
        #expect(distance < 1)
    }
}

@Suite("Full pipeline")
struct PipelineTests {
    @Test("Three sources answer one pin without stepping on each other")
    func williamsDrive() async {
        let transport = FixtureTransport.williamsDrive
        let client = ArcGISClient(transport: transport)
        let record = await RoadResolver(sources: [
            ADOTStateRouteSource(client: client, now: { fixedNow }),
            MCDOTRoadInfoSource(client: client, now: { fixedNow }),
            MaricopaCountyProjectSource(client: client, now: { fixedNow }),
        ]).resolve(RoadQuery(latitude: 33.689441, longitude: -112.317668))

        // ADOT has nothing here and says so, without costing the other sources anything.
        #expect(record.notes.first(where: { $0.sourceID == "adot.atis" })?.outcome == .foundNothing)
        #expect(record.failures.isEmpty)

        guard case .county? = record.owner?.value else {
            Issue.record("expected county ownership, got \(String(describing: record.owner?.value))")
            return
        }
        #expect(record.segmentName?.value == "Williams Dr")
        #expect(record.classification?.value == "Principal Arterial")
        #expect(record.project?.value.projectNumber == "TT0248")
        #expect(record.plat?.value.recorderURL != nil)

        // Every displayed field can name where it came from.
        #expect(record.owner?.provenance.sourceID == "mcdot.rit")
        #expect(record.project?.provenance.sourceID == "mcdot.projects")
    }
}

@Suite("Agency prose")
struct AgencyTextTests {
    @Test("Renders MCDOT's stored HTML as readable text")
    func stripsHTML() {
        let html = "<p>The Maricopa County Department of Transportation (MCDOT) will be "
                 + "conducting a pavement rehabilitation project.&nbsp;&nbsp;</p>\r\n"
                 + "<p>Work includes milling &amp; paving.</p>"
        let text = AgencyText.strippingHTML(html)
        #expect(text.contains("pavement rehabilitation project."))
        #expect(text.contains("milling & paving."))
        #expect(!text.contains("<"))
        #expect(!text.contains("&nbsp;"))
        // Paragraph structure survives as a blank line.
        #expect(text.contains("\n\n"))
    }

    @Test("Breaks a long summary on a sentence")
    func summarises() {
        let long = String(repeating: "One sentence here. ", count: 40)
        let summary = AgencyText.summary(long, limit: 100)
        #expect(summary.count <= 101)
        #expect(summary.hasSuffix("."))
    }

    @Test("Leaves short text untouched")
    func shortTextUnchanged() {
        #expect(AgencyText.summary("Widen roadway.") == "Widen roadway.")
    }
}
