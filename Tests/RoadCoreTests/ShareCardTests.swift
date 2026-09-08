import Foundation
import Testing
@testable import RoadCore
@testable import RoadUI

private let provenance = Provenance(sourceID: "mcdot.rit", sourceName: "MCDOT",
                                    url: URL(string: "https://gis.maricopa.gov/dot/rest/services/"
                                             + "Maintenance/RoadInformationTool/MapServer/2/query"
                                             + "?geometry=-112.319,33.688,-112.316,33.691")!,
                                    fetchedAt: Date(timeIntervalSince1970: 1_757_000_000))

private func williamsDrive() -> RoadRecord {
    var record = RoadRecord(query: RoadQuery(latitude: 33.689441, longitude: -112.317668))
    record.segmentName = Attributed("Williams Dr", provenance: provenance)
    record.owner = Attributed(.county(agency: "Maricopa County DOT"), provenance: provenance)
    record.crossStreets = Attributed("El Mirage Rd to Deer Valley Rd", provenance: provenance)
    record.yearLastConstruction = Attributed(CalendarDate.januaryFirst(ofYear: 2009)!,
                                             provenance: provenance)
    return record
}

@MainActor
@Suite("What leaves the app when you share a road")
struct ShareCardTests {
    @Test("The shared text answers the question")
    func textCarriesTheAnswer() {
        let text = ShareCard.text(DriveCardContent(record: williamsDrive()))
        #expect(text.contains("Williams Dr"))
        #expect(text.contains("Built 2009"))
        #expect(text.contains("Maricopa County DOT"))
        #expect(text.contains("hoobiltit.com"))
    }

    @Test("No coordinate ever leaves in the text")
    func textCarriesNoLocation() {
        // The reason a `RoadRecord` is never shared verbatim: every field carries a `Provenance`
        // whose URL embeds the pin's coordinates in the query's geometry parameter, and
        // `fetchedAt` says when somebody was standing there.
        let text = ShareCard.text(DriveCardContent(record: williamsDrive()))
        #expect(!text.contains("33.689"))
        #expect(!text.contains("-112.317"))
        #expect(!text.contains("geometry="))
        #expect(!text.lowercased().contains("gis.maricopa.gov"))
        // Nothing that looks like a decimal degree at all.
        #expect(text.firstMatch(of: /-?\d{1,3}\.\d{4,}/) == nil)
    }

    @Test("A road nobody could identify still shares something honest")
    func handlesAnEmptyRecord() {
        let bare = RoadRecord(query: RoadQuery(latitude: 29.76, longitude: -95.36))
        let text = ShareCard.text(DriveCardContent(record: bare))
        #expect(text.contains("Unidentified road"))
        #expect(text.firstMatch(of: /-?\d{1,3}\.\d{4,}/) == nil)
    }
}

@Suite("Serialising a record stays impossible on purpose")
struct RecordSerialisationTests {
    @Test("Coverage is not Codable, which is what keeps RoadRecord unshareable")
    func coverageIsDeliberatelyNotCodable() {
        // If this ever compiles, someone has added `Codable` to `Coverage` as a tidy-up and
        // removed the guarantee that a record — provenance URLs and all — cannot be serialised
        // and handed to a third party. The comment on the type explains it; this is the alarm.
        #expect(!(Coverage.self is any Decodable.Type))
        #expect(!(Coverage.self is any Encodable.Type))
    }
}

@Suite("The report document and the drive log")
struct SharedDocumentTests {
    private var record: RoadRecord { williamsDrive() }

    @Test("The report carries the answer")
    func reportCarriesTheAnswer() {
        let text = ReportDocument.text(for: record)
        #expect(text.contains("Williams Dr"))
        #expect(text.contains("Maricopa County DOT"))
        #expect(text.contains("hoobiltit.com"))
    }

    @Test("The report carries no coordinate and no query URL")
    func reportLeaksNoLocation() {
        // Same rule as the card. Provenance URLs embed the pin in their geometry parameter and
        // the fetch time beside it, so a document that quoted them would be a location log
        // wearing a report's clothes. Sources are named, never linked.
        let text = ReportDocument.text(for: record)
        #expect(text.contains("MCDOT"), "the source is still named")
        #expect(!text.contains("geometry="))
        #expect(!text.contains("gis.maricopa.gov"))
        #expect(text.firstMatch(of: /-?\d{1,3}\.\d{4,}/) == nil)
    }

    @Test("An empty section never prints a bare heading")
    func noEmptyHeadings() {
        let bare = RoadRecord(query: RoadQuery(latitude: 29.76, longitude: -95.36))
        let text = ReportDocument.text(for: bare)
        for heading in ["THE PROJECT", "THE PAPER TRAIL", "WHEN"] {
            #expect(!text.contains(heading), "\(heading) has nothing to say here")
        }
    }

    @Test("The drive log exports road names, not a track")
    func driveLogHasNoCoordinates() {
        // An ordered list of where somebody drove is a movement record the moment it is one tap
        // from a share sheet. The road names are the useful half.
        let csv = DriveLogCSV(roads: [record]).text
        #expect(csv.contains("Williams Dr"))
        #expect(csv.contains("Road,Between,Maintained by,Years,Jurisdiction"))
        #expect(csv.firstMatch(of: /-?\d{1,3}\.\d{4,}/) == nil)
        #expect(!csv.lowercased().contains("latitude"))
    }
}
