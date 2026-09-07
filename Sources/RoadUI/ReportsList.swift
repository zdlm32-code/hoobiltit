import SwiftUI
import UniformTypeIdentifiers
import RoadCore

/// Everything you have logged, newest first, with the export.
struct ReportsList: View {
    let reports: [RoadReport]
    let onDelete: (UUID) -> Void
    /// Which of these reached the shared map. Answered from local storage — the pool is never
    /// queried, and no identity is involved.
    var sharedIDs: Set<UUID> = []
    var onWithdraw: (UUID) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if reports.isEmpty {
                    ContentUnavailableView(
                        "No reports yet",
                        systemImage: "exclamationmark.bubble",
                        description: Text("Identify a road, then use Report an issue to rate it "
                                          + "and mark what is wrong."))
                } else {
                    List {
                        ForEach(reports) { report in
                            row(report)
                                .swipeActions(edge: .leading) {
                                    if sharedIDs.contains(report.id) {
                                        Button("Unshare", systemImage: "person.2.slash") {
                                            onWithdraw(report.id)
                                        }
                                        .tint(.orange)
                                    }
                                }
                                .badge(sharedIDs.contains(report.id) ? "Shared" : nil)
                        }
                        .onDelete { offsets in
                            for index in offsets { onDelete(reports[index].id) }
                        }
                    }
                }
            }
            .navigationTitle("Your reports")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    if !reports.isEmpty {
                        ShareLink(item: CSVDocument(reports: reports),
                                  preview: SharePreview("Road reports")) {
                            Label("Export", systemImage: "square.and.arrow.up")
                        }
                    }
                }
            }
        }
    }

    private func row(_ report: RoadReport) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: report.issue.symbol)
                    .foregroundStyle(report.rating.tint)
                Text(report.roadName ?? "Unidentified road")
                    .font(.headline)
                Spacer()
                Text(report.rating.label)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(report.rating.tint.opacity(0.22), in: Capsule())
            }
            Text(report.issue.shortLabel + (report.crossStreets.map { " · \($0)" } ?? ""))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let note = report.note {
                Text(note).font(.footnote)
            }
            if let disagreement = report.disagreesWithCounty {
                Label(disagreement, systemImage: "arrow.triangle.branch")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(report.createdAt.formatted(date: .abbreviated, time: .shortened))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}

/// The CSV, wrapped so `ShareLink` hands over a real file rather than a wall of text.
struct CSVDocument: Transferable {
    let reports: [RoadReport]

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .commaSeparatedText) { document in
            Data(ReportCSV.document(document.reports).utf8)
        }
        .suggestedFileName("road-reports.csv")
    }
}
