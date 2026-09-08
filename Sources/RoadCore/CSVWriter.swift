import Foundation

/// Writing CSV that survives a spreadsheet.
///
/// Salvaged from the road-report export when that feature was removed. The escaping is the part
/// worth keeping: a value containing a comma, a quote or a newline corrupts every column after it
/// if you get it wrong, and it is wrong in a way that looks fine until somebody opens the file.
/// It is a pure function with tests, and the drive-log export needs exactly it.
public enum CSVWriter {
    /// RFC 4180: wrap in quotes when the value contains a comma, quote or newline, and double
    /// any quotes inside.
    ///
    /// Tested over **unicode scalars, not characters** — and that is a bug fix, not a stylistic
    /// choice. Swift treats CRLF as a single `Character`, so `"a\r\nb"` contains neither `"\n"`
    /// nor `"\r"` when you iterate characters, and the version this was salvaged from therefore
    /// emitted a Windows line ending unquoted, splitting the row and shifting every column after
    /// it. The file still opens, which is why nobody noticed.
    public static func escape(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "" }
        let needsQuoting = value.unicodeScalars.contains {
            $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r"
        }
        guard needsQuoting else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    public static func row(_ values: [String?]) -> String {
        values.map(escape).joined(separator: ",")
    }

    /// A whole document, header first. Trailing newline, because a file without one confuses
    /// about half the tools that will read it.
    public static func document(columns: [String], rows: [[String?]]) -> String {
        ([row(columns.map { $0 })] + rows.map(row)).joined(separator: "\n") + "\n"
    }
}
