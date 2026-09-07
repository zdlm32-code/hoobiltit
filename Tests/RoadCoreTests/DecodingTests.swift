import Foundation
import Testing
@testable import RoadCore

private func attribute(_ json: String) throws -> AttributeValue {
    try JSONDecoder().decode([String: AttributeValue].self, from: Data(#"{"v":\#(json)}"#.utf8))["v"]!
}

@Suite("Attribute decoding — the county's and ADOT's string habits")
struct AttributeValueTests {
    @Test("roadName strips the padded route ordinal the project layers append")
    func routeSuffix() throws {
        // Real value from BOS/Transportation layer 770 (ENDPOINTS.md §5.3).
        let padded = try attribute(#""Williams Dr                             01""#)
        #expect(padded.roadName == "Williams Dr")
        #expect(padded.rawString == "Williams Dr                             01")
        // The ordinal is not always "01" — 02, 03, 04, 10, 14, 1001 … all occur.
        #expect(try attribute(#""Bethany Home Rd          1002""#).roadName == "Bethany Home Rd")
        #expect(try attribute(#""Olive Ave     10""#).roadName == "Olive Ave")
    }

    @Test("Drops a jurisdiction appended after the ordinal")
    func trailingJurisdiction() throws {
        // 68 of 438 distinct values in layer 770 look like this. Left in place they defeat
        // the name gate: "52nd Pl 01 Mesa" matches no segment called "52nd Pl".
        #expect(try attribute(#""52nd Pl                                 01 Mesa""#).roadName == "52nd Pl")
        #expect(try attribute(#""Buttonwood Dr                           01 Maricopa County""#).roadName
                == "Buttonwood Dr")
        #expect(try attribute(#""78th St                                 01 Mesa""#).roadName == "78th St")
        #expect(try attribute(#""Chandler Blvd                           01 Sun Lakes""#).roadName
                == "Chandler Blvd")
    }

    @Test("Real road names ending in numbers survive both accessors")
    func doesNotMangleNumericRoadNames() throws {
        // All four are genuine OnRoad values on the maintained-roads layer. An earlier cut of
        // `text` stripped any trailing two-digit token and turned "MC 85" into "MC".
        // A single space before the digits is what keeps these safe from the ordinal rule.
        for name in ["MC 85", "Old US 80", "Old SR 87", "FR 206"] {
            let value = try attribute("\"\(name)\"")
            #expect(value.text == name)
            #expect(value.roadName == name)
        }
    }

    @Test("text keeps trailing digits; only roadName removes padded ordinals")
    func accessorsDiffer() throws {
        let padded = try attribute(#""Deer Valley Rd                          01""#)
        #expect(padded.text == "Deer Valley Rd 01")
        #expect(padded.roadName == "Deer Valley Rd")
    }

    @Test("Collapses ADOT's leading and internal padding")
    func adotPadding() throws {
        #expect(try attribute(#""  I 010                         ""#).text == "I 010")
    }

    @Test("Leaves ordinary street names alone")
    func doesNotOverStrip() throws {
        #expect(try attribute(#""Sarival Ave""#).text == "Sarival Ave")
        #expect(try attribute(#""99th Ave""#).text == "99th Ave")
        #expect(try attribute(#""99th Ave""#).roadName == "99th Ave")
    }

    @Test("Treats the 1900-01-01 epoch sentinel as absent")
    func nullDateSentinel() throws {
        #expect(try attribute("-2208988800000").epochMillisecondsDate == nil)
        let real = try attribute("1537747200000").epochMillisecondsDate
        #expect(real == Date(timeIntervalSince1970: 1_537_747_200))
    }

    @Test("Parses ADOT's string-typed compact dates")
    func compactDates() throws {
        // ADOT ships every date as a string: "20110130", "20160624070000" (§5.3).
        let date = try #require(try attribute(#""20110130""#).compactStringDate)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        #expect(calendar.component(.year, from: date) == 2011)
        #expect(calendar.component(.month, from: date) == 1)
        #expect(calendar.component(.day, from: date) == 30)

        #expect(try attribute(#""20160624070000""#).compactStringDate != nil)
        #expect(try attribute(#""notadate""#).compactStringDate == nil)
    }

    @Test("Reads numbers that arrive as strings, since ADOT types measures that way")
    func numbersAsStrings() throws {
        #expect(try attribute(#""127.7180882""#).double == 127.7180882)
        #expect(try attribute("2").int == 2)
        #expect(try attribute(#""-4e-7""#).double == -4e-7)
    }

    @Test("Maps empty and whitespace-only values to nil")
    func emptyIsNil() throws {
        // Buckeye's Contractor column is populated with a single space on every row.
        #expect(try attribute(#"" ""#).text == nil)
        #expect(try attribute(#""""#).text == nil)
        #expect(try attribute("null").text == nil)
    }
}

@Suite("Geometry")
struct GeoTests {
    @Test("Measures to the nearest point on a segment, not the nearest vertex")
    func perpendicularDistance() {
        // A pin beside the midpoint of a long east-west line: the vertices are far away,
        // the perpendicular foot is not.
        let line = [[Coordinate(latitude: 33.5, longitude: -112.5),
                     Coordinate(latitude: 33.5, longitude: -112.4)]]
        let pin = Coordinate(latitude: 33.5009, longitude: -112.45)

        let d = try! #require(Geo.distance(from: pin, toPolyline: line))
        #expect(d > 90 && d < 110)   // ~100 m of latitude offset

        let toVertex = Geo.distance(pin, line[0][0])
        #expect(toVertex > 4000)     // and the nearest vertex is kilometres off
    }

    @Test("Clamps to the segment ends rather than extending the line")
    func clampsToEnds() {
        let line = [[Coordinate(latitude: 33.5, longitude: -112.5),
                     Coordinate(latitude: 33.5, longitude: -112.4)]]
        let beyond = Coordinate(latitude: 33.5, longitude: -112.6)

        let d = try! #require(Geo.distance(from: beyond, toPolyline: line))
        #expect(abs(d - Geo.distance(beyond, line[0][0])) < 1)
    }

    @Test("Envelope is wider in longitude than latitude at Arizona's latitude")
    func envelopeShape() {
        let e = Geo.envelope(around: Coordinate(latitude: 33.5, longitude: -112.5), radiusMeters: 150)
        #expect((e.xmax - e.xmin) > (e.ymax - e.ymin))
        // 150 m of latitude is about 0.00135 degrees.
        #expect(abs((e.ymax - e.ymin) / 2 - 0.001347) < 0.0001)
    }

    @Test("Picks the nearest feature and tolerates features without geometry")
    func nearestFeature() throws {
        let json = """
        {"features":[
          {"attributes":{"OnRoad":"Far Rd"},"geometry":{"paths":[[[-112.40,33.50],[-112.39,33.50]]]}},
          {"attributes":{"OnRoad":"Near Rd"},"geometry":{"paths":[[[-112.50,33.50],[-112.49,33.50]]]}},
          {"attributes":{"OnRoad":"No Geometry Rd"}}
        ]}
        """
        let set = try JSONDecoder().decode(ArcGISFeatureSet.self, from: Data(json.utf8))
        let pin = Coordinate(latitude: 33.5001, longitude: -112.495)
        #expect(set.nearest(to: pin)?["OnRoad"].text == "Near Rd")
    }
}


@Suite("Record dates are calendar dates")
struct CalendarDateTests {
    /// 2014-09-24T00:00:00Z — the county's declaration date for Lone Mountain Rd.
    private let utcMidnight = Date(timeIntervalSince1970: 1_411_516_800)

    @Test("A day named by a record does not shift with the device's time zone")
    func doesNotShiftWestOfGreenwich() {
        // Agencies store these as UTC midnight. Rendered in Phoenix local time they land on
        // the previous evening, and the app would report a legal document as recorded a day
        // earlier than it was.
        #expect(CalendarDate.medium(utcMidnight).contains("24"))
        #expect(CalendarDate.medium(utcMidnight).contains("2014"))
        #expect(CalendarDate.year(utcMidnight) == 2014)
    }

    @Test("Formatting is stable regardless of the ambient time zone")
    func matchesAnExplicitUTCFormatter() {
        let reference = DateFormatter()
        reference.timeZone = TimeZone(identifier: "UTC")
        reference.dateFormat = "yyyy-MM-dd"
        #expect(reference.string(from: utcMidnight) == "2014-09-24")
        // The medium form must name the same day as the ISO form.
        #expect(CalendarDate.medium(utcMidnight).contains("24"))
    }

    @Test("A New Year boundary keeps the right year")
    func yearBoundary() {
        // 1966-01-24, Sun City's 103rd Ave declaration — early January is where a
        // local-time shift would also move the year.
        let january = Date(timeIntervalSince1970: -125_452_800)
        #expect(CalendarDate.year(january) == 1966)
    }
}
