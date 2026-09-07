import SwiftUI
import RoadCore

/// One row per source: what it said, when, and the query behind it.
///
/// Extracted from the map screen so the full report and the ⋯ menu render the same rows from the
/// same code — two renderings of provenance would drift, and provenance is the one thing in this
/// app that has to be exactly right.
struct SourceReceiptRow: View {
    let receipt: SourceReceipt

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(receipt.sourceName, systemImage: Self.icon(for: receipt.outcome))
                .font(.headline)
                .foregroundStyle(Self.tint(for: receipt.outcome))

            if let detail = receipt.detail {
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
            if let summary = contribution {
                Text(summary).font(.caption).foregroundStyle(.secondary)
            }
            if let fetchedAt = receipt.fetchedAt {
                // `Provenance` documents that this must be disclosed. Until now nothing did.
                Text(receipt.isBundled
                     ? "Bundled snapshot, captured \(CalendarDate.medium(fetchedAt))"
                     : "Asked \(fetchedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            if let url = receipt.url {
                // The exact query, so any claim on the screen above can be re-run and checked.
                Link(destination: url) {
                    Label("Open the query", systemImage: "arrow.up.right.square")
                        .font(.caption)
                }
            }
        }
        .padding(.vertical, 2)
    }

    /// "3 fields · read directly, inferred" — what it gave and how firmly it is tied to the road.
    private var contribution: String? {
        guard receipt.fieldCount > 0 else { return nil }
        let fields = "\(receipt.fieldCount) field\(receipt.fieldCount == 1 ? "" : "s")"
        let how = MatchConfidence.allCases
            .filter { receipt.confidences.contains($0) }
            .map(Self.describe)
        return how.isEmpty ? fields : "\(fields) \u{00B7} \(how.joined(separator: ", "))"
    }

    static func describe(_ confidence: MatchConfidence) -> String {
        switch confidence {
        case .direct: "read directly"
        case .spatial: "matched by location"
        case .nameMatch: "matched by name"
        case .derived: "inferred"
        }
    }

    static func icon(for outcome: SourceNote.Outcome?) -> String {
        switch outcome {
        case .contributed: "checkmark.circle.fill"
        case .foundNothing: "minus.circle"
        case .failed: "exclamationmark.triangle.fill"
        case .skipped: "arrow.turn.down.right"
        case nil: "circle"
        }
    }

    static func tint(for outcome: SourceNote.Outcome?) -> Color {
        switch outcome {
        case .contributed: .green
        case .failed: .orange
        case .foundNothing, .skipped, nil: .secondary
        }
    }
}

/// The ⋯ menu's standalone view of the same rows.
struct SourceLog: View {
    let record: RoadRecord
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(record.receipts) { SourceReceiptRow(receipt: $0) }
                .navigationTitle("Sources consulted")
                .inlineNavigationTitle()
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        .presentationDetents([.medium, .large])
    }
}
