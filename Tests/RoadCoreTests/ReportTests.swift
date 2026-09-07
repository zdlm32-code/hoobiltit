import Foundation
import Testing
@testable import RoadCore
@testable import RoadSources
@testable import RoadStore

@Suite("Condition rating — the county's own scale")
struct ConditionRatingTests {
    @Test("Parses the county's exact strings")
    func parsesCountyValues() {
        // These are the live values from EstimatedOcr.
        for value in ["Very Poor", "Poor", "Fair", "Good", "Very Good"] {
            #expect(ConditionRating.county(value) != nil, "failed on \(value)")
        }
        #expect(ConditionRating.county("Very Poor") == .veryPoor)
        #expect(ConditionRating.county(nil) == nil)
        #expect(ConditionRating.county("Excellent") == nil)
    }

    @Test("Tolerates the casing and whitespace drift this data always has")
    func tolerantParsing() {
        #expect(ConditionRating.county("  very good ") == .veryGood)
        #expect(ConditionRating.county("FAIR") == .fair)
    }

    @Test("Orders worst to best")
    func ordering() {
        #expect(ConditionRating.veryPoor < ConditionRating.poor)
        #expect(ConditionRating.poor < ConditionRating.fair)
        #expect(ConditionRating.veryGood > ConditionRating.good)
        #expect(ConditionRating.allCases.sorted().first == .veryPoor)
    }

    @Test("States the disagreement the right way round")
    func disagreementDirection() {
        // The whole point of borrowing the county's scale: saying how far apart you are.
        let harsher = ConditionRating.disagreement(mine: .veryPoor, county: .good)
        #expect(harsher?.contains("3 steps worse") == true)
        #expect(harsher?.contains("county rates this Good") == true)

        let kinder = ConditionRating.disagreement(mine: .good, county: .poor)
        #expect(kinder?.contains("2 steps better") == true)
    }

    @Test("Says nothing when there is nothing to say")
    func noDisagreement() {
        #expect(ConditionRating.disagreement(mine: .fair, county: .fair) == nil)
        // Most city streets: the county publishes no rating, so there is no comparison.
        #expect(ConditionRating.disagreement(mine: .veryPoor, county: nil) == nil)
    }

    @Test("One step reads as singular")
    func singular() {
        #expect(ConditionRating.disagreement(mine: .fair, county: .good)?.contains("1 step ") == true)
    }
}

@Suite("Issue categories")
struct RoadIssueTests {
    /// Read live from the county's MIP layers.
    private let countyCategories: Set<String> = [
        "Bridge", "Cattle Guard", "Concrete", "Drainage", "Drainage Improvement (Water)",
        "Dust Mitigation", "Guardrail", "Intersection", "Pavement Preservation", "Road",
    ]

    @Test("Every issue maps to a category the county actually files work under")
    func categoriesAreReal() {
        for issue in RoadIssue.allCases {
            guard let category = issue.countyCategory else {
                #expect(issue == .other, "\(issue) should map to a county category")
                continue
            }
            #expect(countyCategories.contains(category),
                    "\(issue) maps to \(category), which the county does not use")
        }
    }

    @Test("Every case is presentable")
    func labels() {
        for issue in RoadIssue.allCases {
            #expect(!issue.label.isEmpty)
            #expect(!issue.shortLabel.isEmpty)
            #expect(!issue.symbol.isEmpty)
        }
        #expect(Set(RoadIssue.allCases.map(\.shortLabel)).count == RoadIssue.allCases.count)
    }
}

@Suite("CSV export")
struct ReportCSVTests {
    private func report(note: String?) -> RoadReport {
        RoadReport(coordinate: Coordinate(latitude: 33.689441, longitude: -112.317668),
                   createdAt: Date(timeIntervalSince1970: 1_757_000_000),
                   rating: .veryPoor, issue: .pavement, note: note,
                   roadName: "Williams Dr", crossStreets: "El Mirage Rd to Deer Valley Rd",
                   maintainedBy: "Maricopa County Department of Transportation",
                   segmentIdentifier: "1065", countyRating: .good)
    }

    @Test("A comma in a note does not shift every column after it")
    func quotesCommas() {
        // The classic silent CSV failure: no error, just a corrupted file.
        let row = ReportCSV.row(report(note: "deep, wide pothole"))
        #expect(row.contains("\"deep, wide pothole\""))
        #expect(row.components(separatedBy: "\"").count == 3)
    }

    @Test("Quotation marks are doubled, per RFC 4180")
    func quotesQuotes() {
        let row = ReportCSV.row(report(note: #"a "quoted", comma"#))
        #expect(row.contains(#""a ""quoted"", comma""#))
    }

    @Test("Newlines survive")
    func quotesNewlines() {
        #expect(ReportCSV.escape("line one\nline two") == "\"line one\nline two\"")
    }

    @Test("Ordinary values are left alone")
    func leavesPlainValuesBare() {
        #expect(ReportCSV.escape("Williams Dr") == "Williams Dr")
        #expect(ReportCSV.escape(nil) == "")
        #expect(ReportCSV.escape("") == "")
    }

    @Test("Every row has as many fields as the header")
    func columnCount() {
        let document = ReportCSV.document([report(note: "a, b"), report(note: nil)])
        let lines = document.split(separator: "\n")
        #expect(lines.count == 3)
        // Counting commas is only valid outside quotes, so check the unquoted row.
        #expect(ReportCSV.row(report(note: nil)).components(separatedBy: ",").count
                == ReportCSV.columns.count)
    }

    @Test("Carries the county's rating so the disagreement survives export")
    func exportsComparison() {
        let row = ReportCSV.row(report(note: nil))
        #expect(row.contains("Very Poor"))
        #expect(row.contains("Good"))
        #expect(row.contains("Pavement Preservation"))
    }
}

@Suite("Report store")
struct ReportStoreTests {
    private func sample(_ rating: ConditionRating) -> RoadReport {
        RoadReport(coordinate: Coordinate(latitude: 33.68, longitude: -112.31),
                   rating: rating, issue: .drainage, note: "ponding after rain",
                   roadName: "Williams Dr", segmentIdentifier: "1065", countyRating: .good)
    }

    @Test("Round-trips a report through SwiftData")
    func roundTrip() async throws {
        let store = try ReportStore(inMemory: true)
        await store.save(sample(.poor))
        let all = await store.all()

        let stored = try #require(all.first)
        #expect(stored.rating == .poor)
        #expect(stored.issue == .drainage)
        #expect(stored.note == "ponding after rain")
        #expect(stored.segmentIdentifier == "1065")
        #expect(stored.countyRating == .good)
        #expect(stored.disagreesWithCounty != nil)
    }

    @Test("Newest first")
    func ordering() async throws {
        let store = try ReportStore(inMemory: true)
        let older = RoadReport(coordinate: Coordinate(latitude: 33.6, longitude: -112.3),
                               createdAt: Date(timeIntervalSince1970: 1000),
                               rating: .fair, issue: .pavement)
        let newer = RoadReport(coordinate: Coordinate(latitude: 33.6, longitude: -112.3),
                               createdAt: Date(timeIntervalSince1970: 2000),
                               rating: .poor, issue: .pavement)
        await store.save(older)
        await store.save(newer)

        #expect(await store.all().first?.rating == .poor)
    }

    @Test("Deletes one without touching the rest")
    func delete() async throws {
        let store = try ReportStore(inMemory: true)
        let keep = sample(.fair)
        let drop = sample(.veryPoor)
        await store.save(keep)
        await store.save(drop)

        await store.delete(id: drop.id)
        let remaining = await store.all()
        #expect(remaining.count == 1)
        #expect(remaining.first?.id == keep.id)
    }
}

@Suite("Wording that could be misread")
struct ParcelWordingTests {
    private func parcel(range: ClosedRange<Int>?) -> ParcelReference {
        ParcelReference(apn: "500-90-125", constructionYear: range == nil ? 2010 : nil,
                        constructionYearRange: range, containsPin: false)
    }

    @Test("Never describes a parcel year as 'frontage'")
    func avoidsFrontage() {
        // "Frontage road" is a road type, so "Frontage built 2010" on the driving card reads
        // as a claim about what kind of road you are on. It is the year the buildings beside
        // the road went up.
        for text in [MaricopaParcelSource.summary(parcel(range: 2008...2009)),
                     MaricopaParcelSource.summary(parcel(range: nil))] {
            #expect(!text.lowercased().contains("frontage"), "still says frontage: \(text)")
        }
    }

    @Test("Says buildings, so the number is attached to the right thing")
    func namesBuildings() {
        let ranged = MaricopaParcelSource.summary(parcel(range: 2008...2009))
        #expect(ranged.contains("buildings alongside built 2008\u{2013}2009"))
        #expect(MaricopaParcelSource.summary(parcel(range: nil)).contains("built 2010"))
    }
}
