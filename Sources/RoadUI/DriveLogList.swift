import SwiftUI
import RoadCore

/// The roads identified on this drive, newest first.
///
/// The drive card can only ever show the road under the car, and at 45 mph it deliberately
/// shows very little of what was found. This is where the rest of it goes — the project, the
/// full coverage explanation, everything that would be unreadable at speed — to be read once
/// stopped. `README` has claimed this screen existed for some time; until now it did not.
struct DriveLogList: View {
    let roads: [RoadRecord]
    let onClear: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if roads.isEmpty {
                    ContentUnavailableView(
                        "No roads yet",
                        systemImage: "car",
                        description: Text("Drive mode adds every road it identifies. Start "
                                          + "driving and they will appear here."))
                } else {
                    List { ForEach(Array(roads.enumerated()), id: \.offset) { row($0.element) } }
                }
            }
            .navigationTitle("This drive")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                if !roads.isEmpty {
                    ToolbarItem(placement: .destructiveAction) {
                        Button("Clear", role: .destructive) { onClear(); dismiss() }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func row(_ record: RoadRecord) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(record.segmentName?.value ?? record.routeDesignation?.value ?? "Unidentified road")
                .font(.headline)

            if let owner = record.owner?.value.displayName {
                Text(owner).font(.subheadline).foregroundStyle(.secondary)
            }
            if let between = record.crossStreets?.value {
                Text(between).font(.footnote).foregroundStyle(.secondary)
            }

            // Reads the shared content rules directly. This used to build a whole SwiftUI view
            // and throw it away just to call one computed property on it.
            let years = DriveCardContent(record: record).years
            if !years.isEmpty {
                Text(years.joined(separator: "  \u{00B7}  "))
                    .font(.subheadline.weight(.medium))
            }

            // The two things the driving card deliberately drops, restored now there is time
            // to read them.
            if let project = record.project?.value ?? record.lastKnownImprovement?.value {
                Label(SegmentCard.describe(project), systemImage: "hammer.fill")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if let explanation = record.coverage?.explanation(for: record) {
                Text(explanation).font(.caption).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}
