import Foundation

/// Cleaning for prose that agencies store as markup.
public enum AgencyText {
    /// MCDOT's `ProjectDescription` is raw HTML with `\r\n` and entities
    /// (docs/ENDPOINTS.md §2.2). Renders it as plain text with paragraph breaks preserved.
    public static func strippingHTML(_ html: String) -> String {
        var text = html
        // Turn block boundaries into breaks before dropping the tags.
        text = text.replacing(/<\s*br\s*\/?\s*>/.ignoresCase(), with: "\n")
        text = text.replacing(/<\s*\/\s*(p|div|li|tr|h[1-6])\s*>/.ignoresCase(), with: "\n")
        text = text.replacing(/<[^>]+>/, with: "")

        for (entity, replacement) in [("&nbsp;", " "), ("&amp;", "&"), ("&lt;", "<"),
                                      ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"),
                                      ("&rsquo;", "\u{2019}"), ("&ndash;", "\u{2013}")] {
            text = text.replacingOccurrences(of: entity, with: replacement)
        }

        let paragraphs = text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ") }
            .filter { !$0.isEmpty }
        return paragraphs.joined(separator: "\n\n")
    }

    /// Shortens prose to a readable lead, breaking on a sentence where possible.
    public static func summary(_ text: String, limit: Int = 320) -> String {
        guard text.count > limit else { return text }
        let head = text.prefix(limit)
        if let stop = head.lastIndex(where: { $0 == "." || $0 == "\n" }) {
            return String(head[..<stop]) + "."
        }
        return String(head).trimmingCharacters(in: .whitespaces) + "\u{2026}"
    }
}
