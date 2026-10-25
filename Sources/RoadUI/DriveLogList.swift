import SwiftUI
import UniformTypeIdentifiers
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
                    List {
                        ForEach(Array(driven.enumerated()), id: \.offset) {
                            DrivenRoadRow(road: $0.element)
                        }
                    }
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
                    ToolbarItem(placement: .primaryAction) {
                        ShareLink(item: DriveLogCSV(roads: roads),
                                  preview: SharePreview("Roads this drive")) {
                            Label("Export", systemImage: "square.and.arrow.up")
                        }
                    }
                }
            }
        }
    }

    /// The same strings past drives keep, so this drive and an old one read identically.
    private var driven: [DrivenRoad] { roads.compactMap { DrivenRoad(record: $0, city: nil) } }
}

/// One road in a drive's list, this drive's or a past one's.
struct DrivenRoadRow: View {
    let road: DrivenRoad

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(road.name).font(.headline)

            if let owner = road.owner {
                Text(owner).font(.subheadline).foregroundStyle(.secondary)
            }
            if let between = road.between {
                Text(between).font(.footnote).foregroundStyle(.secondary)
            }
            if !road.years.isEmpty {
                Text(road.years.joined(separator: "  \u{00B7}  "))
                    .font(.subheadline.weight(.medium))
            }

            // The two things the driving card deliberately drops, restored now there is time
            // to read them.
            if let project = road.project {
                Label(project, systemImage: "hammer.fill")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if let explanation = road.explanation {
                Text(explanation).font(.caption).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}


/// The drive log as a CSV.
///
/// **Carries no coordinates, deliberately.** The log is an ordered trace of the roads somebody
/// drove, in order — which is useful to look at yourself and is a movement record the moment it
/// is one tap from a group chat. Road names and what the app found out about them are the useful
/// part; the positions are the part that turns a list into a track.
struct DriveLogCSV: Transferable {
    let roads: [DrivenRoad]

    let fileName: String

    init(roads: [RoadRecord]) {
        self.roads = roads.compactMap { DrivenRoad(record: $0, city: nil) }
        fileName = "roads-this-drive.csv"
    }

    /// A past drive, which is already kept as `DrivenRoad`s.
    init(driven: [DrivenRoad], fileName: String) {
        self.roads = driven
        self.fileName = fileName
    }

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .commaSeparatedText) { document in
            Data(document.text.utf8)
        }
        .suggestedFileName { $0.fileName }
    }

    var text: String {
        CSVWriter.document(
            columns: ["Road", "Between", "Maintained by", "Years", "Jurisdiction"],
            rows: roads.map { road in
                [road.name,
                 road.between,
                 road.owner,
                 road.years.isEmpty ? nil : road.years.joined(separator: " · "),
                 road.jurisdiction]
            })
    }
}
