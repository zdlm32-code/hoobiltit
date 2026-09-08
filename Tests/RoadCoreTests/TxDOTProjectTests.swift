import Foundation
import Testing
@testable import RoadCore
@testable import RoadSources

/// After every project in the recorded fixtures, so "planned" means planned.
private let fixedNow = Date(timeIntervalSince1970: 1_757_000_000)   // 2025-09-04

@Suite("TxDOT construction register")
struct TxDOTProjectTests {
    /// The pin used throughout the Texas work: mid-block, with 22 projects on the stretch.
    let i35 = RoadQuery(latitude: 30.490050, longitude: -97.676922)
    /// A city street with state-owned Loop 343 55 m away — the false positive to refuse.
    let sanJacinto = RoadQuery(latitude: 30.263227, longitude: -97.741957)

    private func source(_ transport: FixtureTransport) -> TxDOTProjectSource {
        TxDOTProjectSource(client: ArcGISClient(transport: transport), now: { fixedNow })
    }

    private var austin: FixtureTransport {
        FixtureTransport([
            "TxDOT_DCIS_All_Projects/FeatureServer/0": .fixture("txdot_dcis_i35"),
            "ProjectTracker_AGO/FeatureServer/1": .fixture("txdot_tracker_i35"),
        ])
    }

    @Test("Reports the biggest completed build, not the biggest cheque")
    func picksTheBuild() async throws {
        let fragment = try await source(austin).fetch(i35)
        let project = try #require(fragment.project?.value)
        // The two largest amounts on this stretch are a $53.5M "Preliminary Engineering" and a
        // $30.1M "Intersection & Operational Imprv". Neither built the road — one is design
        // work billed before a shovel moves — so the answer is the 1988 freeway widening.
        #expect(project.title == "Widen Freeway")
        #expect(project.projectNumber == "001509093")
        #expect(fragment.funding?.value.programmedAmount == 12_567_454.6)
    }

    @Test("A resurfacing is the latest work, never the thing that built the road")
    func maintenanceIsNotConstruction() async throws {
        let fragment = try await source(austin).fetch(i35)
        let latest = try #require(fragment.lastKnownImprovement?.value)
        #expect(latest.title == "Overlay")
        #expect(latest.projectNumber == "001509202")
        #expect(fragment.project?.value.projectNumber != latest.projectNumber)
    }

    @Test("A project not yet let never becomes the thing that built the road")
    func plannedWorkIsExcluded() async throws {
        let fragment = try await source(austin).fetch(i35)
        // The single largest project here is a $1.62bn freeway widening let in 2037. It is
        // build-class and it dwarfs everything else, and it has not happened.
        #expect(fragment.project?.value.projectNumber != "001509178")
        #expect(fragment.funding?.value.programmedAmount != 1_624_890_000)
        let works = try #require(fragment.works?.value)
        let planned = works.filter(\.isPlanned)
        #expect(planned.contains { $0.projectNumber == "001509178" })
        #expect(planned.allSatisfy { ($0.letDate ?? .distantPast) > fixedNow })
    }

    @Test("The whole register is carried, newest first")
    func historyIsComplete() async throws {
        let fragment = try await source(austin).fetch(i35)
        let works = try #require(fragment.works?.value)
        #expect(works.count == 22)
        let dates = works.compactMap(\.letDate)
        #expect(dates == dates.sorted(by: >), "newest first")
        // Fifty years of it, which is the point.
        #expect(CalendarDate.year(try #require(dates.last)) == 1984)
        // A control section is drawn as several features, so one project can come back more
        // than once in an envelope; listed twice it reads as two separate jobs in one year.
        let numbers = works.compactMap(\.projectNumber)
        #expect(numbers.count == Set(numbers).count, "no project is listed twice")
    }

    /// The regression this source's tight gate exists for.
    @Test("A city street is not credited with the state highway's history")
    func refusesTheRoadNextDoor() async throws {
        let transport = FixtureTransport([
            "TxDOT_DCIS_All_Projects/FeatureServer/0": .fixture("txdot_dcis_sanjacinto"),
        ])
        let fragment = try await source(transport).fetch(sanJacinto)
        // DCIS returns exactly one project at this pin: State Loop 343's overlay, 55 m away.
        // That is inside RoadProximity.onRoadMeters (60 m), so the general gate would have
        // let it through and told a resident their street was resurfaced by TxDOT.
        #expect(fragment.project == nil)
        #expect(fragment.works == nil)
        #expect(!fragment.contributesAnything)
        #expect(fragment.notes.first?.detail?.contains("another road") == true)
    }

    @Test("A named contractor reaches the card, joined on the project number")
    func joinsContractor() async throws {
        // The recorded tracker response answers any CSJ, so this tests the join and the
        // extraction, not the coverage. Live, this particular build has no contractor and is
        // not supposed to: Project Tracker holds only live and near-term work, so a 1988
        // widening has no company against it and never will.
        let transport = austin
        let fragment = try await source(transport).fetch(i35)
        #expect(fragment.funding?.value.contractor == "J.D. ABRAMS, L.P.")
        let join = try #require(transport.log.all.first {
            $0.absoluteString.contains("ProjectTracker")
        })
        #expect(join.absoluteString.contains("001509093"))
    }

    @Test("The drive card gets a dated line from the register")
    func driveCardShowsAYear() {
        // Texas sets no `yearLastConstruction` anywhere, so without this rung a driver on a
        // Texas highway sees no date at all — which is what prompted the work.
        var record = RoadRecord(query: i35)
        record.works = Attributed(
            [RoadWork(title: "Overlay", letDate: CalendarDate.januaryFirst(ofYear: 2022),
                      kind: .maintained),
             RoadWork(title: "Widen Freeway", letDate: CalendarDate.januaryFirst(ofYear: 1988),
                      kind: .built)],
            provenance: Provenance(sourceID: "tx.dcis", sourceName: "TxDOT",
                                   url: URL(string: "https://example.com")!, fetchedAt: fixedNow),
            confidence: .spatial)
        let years = DriveCardContent.years(of: record)
        // Worded as a contract, because a let date is not a completion date.
        #expect(years.contains("Built under a 1988 contract"))
        #expect(years.contains("Resurfaced 2022"))
    }

    @Test("A failed contractor lookup costs only the contractor")
    func contractorFailureIsSurvivable() async throws {
        var routes = austin.routes
        routes["ProjectTracker_AGO/FeatureServer/1"] = .status(500)
        let fragment = try await source(FixtureTransport(routes)).fetch(i35)
        #expect(fragment.funding?.value.contractor == nil)
        #expect(fragment.funding?.value.programmedAmount == 12_567_454.6)
        #expect(fragment.project != nil)
        #expect(fragment.works?.value.count == 22)
    }

    @Test("An unrecognised project class is never treated as construction")
    func unknownClassIsNotABuild() {
        // TxDOT can add to the vocabulary at any time. Guessing "built" would credit a road
        // to a job that might have painted its stripes.
        #expect(CodeTables.workKind(txdot: "Something New In 2027") == .ancillary)
        #expect(CodeTables.workKind(txdot: nil) == .ancillary)
        #expect(CodeTables.workKind(txdot: "Seal Coat") == .maintained)
        #expect(CodeTables.workKind(txdot: "Widen Freeway") == .built)
        // Design work, billed before construction starts, is the trap here: it is expensive
        // and it is not construction.
        #expect(CodeTables.workKind(txdot: "Preliminary Engineering") == .ancillary)
        // The live service emits some classes padded: "Corridor Traffic Management ",
        // "Upgrade to Standards Non-Freeway ". Matched raw, a real construction class would
        // silently stop counting as one.
        #expect(CodeTables.workKind(txdot: "Upgrade to Standards Non-Freeway ") == .built)
        #expect(CodeTables.workKind(txdot: " Seal Coat") == .maintained)
    }

    @Test("No project here is a normal answer")
    func emptyIsFine() async throws {
        let empty = FixtureTransport(["TxDOT_DCIS_All_Projects/FeatureServer/0":
                                        .body(#"{"features":[]}"#)])
        let fragment = try await source(empty).fetch(i35)
        #expect(!fragment.contributesAnything)
        #expect(fragment.notes.first?.outcome == .foundNothing)
    }
}
