import SwiftUI
import Foundation
import UniformTypeIdentifiers
import RoadCore

/// The whole answer for one road, as plain text.
///
/// Text rather than PDF on purpose: it is greppable, it pastes into an email or a planning
/// objection without ceremony, it survives every share target, and it is the form somebody
/// actually filing something wants. A PDF would look better and be less useful.
///
/// Follows the same rule as `ShareCard`: **no coordinate, and no provenance URLs.** Those URLs
/// embed the pin in their geometry parameter and the moment it was fetched, so a document that
/// quoted them would be a location log wearing a report's clothes. Sources are named — that is
/// the app's whole claim to being trustworthy — but not linked.
public enum ReportDocument {
    public static func text(for record: RoadRecord, placeName: String? = nil) -> String {
        let content = DriveCardContent(record: record, placeName: placeName)
        var lines: [String] = []

        lines.append(content.roadName ?? "Unidentified road")
        lines.append(String(repeating: "=", count: (content.roadName ?? "Unidentified road").count))
        if let context = content.context { lines.append(context) }
        lines.append("")

        section("WHO MAINTAINS IT", into: &lines, rows: [
            ("Maintained by", content.owner),
            ("Jurisdiction", record.jurisdiction?.value),
            ("Classification", record.classification?.value),
            ("Also known as", record.routeDesignation?.value == content.roadName
                              ? nil : record.routeDesignation?.value),
        ])

        section("WHEN", into: &lines, rows: [
            ("Last constructed", record.yearLastConstruction.map { CalendarDate.medium($0.value) }),
            ("Last improved", record.yearLastImprovement.map { CalendarDate.medium($0.value) }),
            ("Declared a public road",
             record.declaration.map { CalendarDate.medium($0.value.effectiveDate) }),
            ("Platted", record.plattedDate.map { CalendarDate.medium($0.value) }),
        ] + (content.years.isEmpty ? [("Note", content.dateNote)] : []))

        section("THE PROJECT", into: &lines, rows: [
            ("Built under", record.project.map { SegmentCard.describe($0.value) }),
            ("Most recent work", record.lastKnownImprovement.map { SegmentCard.describe($0.value) }),
            // Cost was missing from the shared report entirely, so the one figure the app can
            // now sometimes answer could not survive being sent to anyone.
            ("Estimated construction cost", record.funding?.value.programmedAmount.map {
                $0.formatted(.currency(code: "USD").precision(.fractionLength(0)))
            }),
            ("Contractor", record.funding?.value.contractor),
        ])

        if let works = record.works?.value, !works.isEmpty {
            lines.append("WORK ON THIS ROAD")
            lines.append("  Dates are when the contract was let, not when work finished.")
            for work in works {
                var parts = [work.letDate.map { String(CalendarDate.year($0)) } ?? "undated",
                             work.title]
                if let cost = work.cost {
                    parts.append(cost.formatted(.currency(code: "USD").precision(.fractionLength(0))))
                }
                if work.isPlanned { parts.append("(planned, not yet let)") }
                lines.append("  - " + parts.joined(separator: " \u{00B7} "))
                if let contractor = work.contractor { lines.append("      built by \(contractor)") }
                if let location = work.location { lines.append("      \(location)") }
                if let number = work.projectNumber { lines.append("      project \(number)") }
            }
            lines.append("")
        }

        section("THE PAPER TRAIL", into: &lines, rows: [
            ("Subdivision", record.plat?.value.subdivisionName),
            ("Recorded plat", record.plat?.value.recorderNumber),
            ("County road file", record.declaration?.value.roadFileNumber),
            ("Right of way acquired by", record.acquisition?.value.method),
        ])

        // Named, never linked — see the type comment.
        let consulted = record.receipts.map { receipt -> String in
            let outcome = receipt.fieldCount > 0
                ? "\(receipt.fieldCount) field\(receipt.fieldCount == 1 ? "" : "s")"
                : (receipt.detail ?? "nothing")
            return "  - \(receipt.sourceName): \(outcome)"
        }
        if !consulted.isEmpty {
            lines.append("SOURCES CONSULTED")
            lines += consulted
            lines.append("")
        }

        lines.append("Read from public county, state and federal records by hoobiltit.")
        lines.append("https://hoobiltit.com")
        return lines.joined(separator: "\n")
    }

    private static func section(_ title: String, into lines: inout [String],
                                rows: [(String, String?)]) {
        let present = rows.compactMap { label, value in value.map { "  \(label): \($0)" } }
        guard !present.isEmpty else { return }   // never an empty heading
        lines.append(title)
        lines += present
        lines.append("")
    }
}

/// The report as a shareable file.
struct RoadReportFile: Transferable {
    let name: String
    let text: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .plainText) { Data($0.text.utf8) }
            .suggestedFileName { "\($0.name).txt" }
        ProxyRepresentation(exporting: \.text)
    }
}
