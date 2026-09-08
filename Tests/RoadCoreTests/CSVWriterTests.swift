import Foundation
import Testing
@testable import RoadCore

@Suite("CSV that survives a spreadsheet")
struct CSVWriterTests {
    @Test("A comma is quoted rather than allowed to split the row")
    func quotesCommas() {
        // The failure this guards is silent: every column after the comma shifts by one, and
        // the file still opens.
        #expect(CSVWriter.escape("El Mirage Rd, Deer Valley Rd") == "\"El Mirage Rd, Deer Valley Rd\"")
    }

    @Test("Quotes are doubled, per RFC 4180")
    func doublesQuotes() {
        #expect(CSVWriter.escape("a \"quoted\" thing") == "\"a \"\"quoted\"\" thing\"")
    }

    @Test("A newline inside a value is quoted, not emitted raw")
    func quotesNewlines() {
        #expect(CSVWriter.escape("first\nsecond") == "\"first\nsecond\"")
    }

    @Test("A Windows line ending is quoted too")
    func quotesCarriageReturnNewline() {
        // Swift treats CRLF as one Character, so a characterwise `contains` finds neither "\n"
        // nor "\r" in "a\r\nb". The version this was salvaged from tested characters and so let
        // a CRLF through unquoted, splitting the row. Scalars are what the check must use.
        #expect("first\r\nsecond".contains(where: { $0 == "\n" }) == false, "the trap itself")
        #expect(CSVWriter.escape("first\r\nsecond") == "\"first\r\nsecond\"")
    }

    @Test("An ordinary value is left alone")
    func leavesPlainValuesAlone() {
        #expect(CSVWriter.escape("Williams Dr") == "Williams Dr")
        #expect(CSVWriter.escape(nil) == "")
        #expect(CSVWriter.escape("") == "")
    }

    @Test("Every row has as many fields as the header")
    func rowsMatchTheHeader() {
        let document = CSVWriter.document(
            columns: ["Road", "Owner", "Built"],
            rows: [["Williams Dr", "Maricopa County DOT", "2009"],
                   ["Bullard Ave, north", nil, nil]])
        let lines = document.split(separator: "\n", omittingEmptySubsequences: true)
        #expect(lines.count == 3)
        // Counted on the escaped text, so the quoted comma must not read as a separator.
        #expect(lines[2] == "\"Bullard Ave, north\",,")
    }

    @Test("The document ends with a newline")
    func trailingNewline() {
        // A file without one confuses about half the tools that will read it.
        #expect(CSVWriter.document(columns: ["A"], rows: [["b"]]).hasSuffix("\n"))
    }
}
