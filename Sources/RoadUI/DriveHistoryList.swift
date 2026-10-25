import SwiftUI
import RoadCore

/// Every drive this phone remembers, newest first.
///
/// Saved on the device only, and with no coordinates in it — see `DrivenRoad`. The footer says
/// so where the list is, since this is the one place the app keeps anything about the user.
struct DriveHistoryList: View {
    let history: DriveHistoryStore

    @Environment(\.dismiss) private var dismiss
    @State private var confirmingDeleteAll = false

    var body: some View {
        NavigationStack {
            Group {
                if history.trips.isEmpty {
                    ContentUnavailableView(
                        "No past drives",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("The roads from each drive are saved here, on this "
                                          + "iPhone only and without your location."))
                } else {
                    List {
                        Section {
                            ForEach(history.trips) { trip in
                                NavigationLink {
                                    DriveTripDetail(trip: trip)
                                } label: {
                                    DriveTripRow(trip: trip)
                                }
                            }
                            .onDelete { offsets in
                                // Read the ids first: deleting reorders what the offsets index.
                                let ids = offsets.map { history.trips[$0].id }
                                ids.forEach(history.delete)
                            }
                        } footer: {
                            Text("Saved on this iPhone only, with road names and no locations. "
                                 + "Swipe a drive to delete it.")
                        }
                    }
                }
            }
            .navigationTitle("Past drives")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                if !history.trips.isEmpty {
                    ToolbarItem(placement: .destructiveAction) {
                        Button("Delete All", role: .destructive) { confirmingDeleteAll = true }
                    }
                }
            }
            .confirmationDialog("Delete all past drives?", isPresented: $confirmingDeleteAll,
                                titleVisibility: .visible) {
                Button("Delete All Drives", role: .destructive) { history.deleteAll() }
            } message: {
                Text("This cannot be undone.")
            }
        }
    }
}

private struct DriveTripRow: View {
    let trip: DriveTrip

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(trip.startedAt, format: .dateTime.weekday(.wide).month().day())
                .font(.headline)
            Text("\(trip.timeRange)  \u{00B7}  \(trip.roadCountLabel)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let route = trip.routeSummary {
                Text(route)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }
}

/// One past drive's roads, in the order they were driven.
private struct DriveTripDetail: View {
    let trip: DriveTrip

    var body: some View {
        List {
            Section {
                ForEach(Array(trip.roads.enumerated()), id: \.offset) {
                    DrivenRoadRow(road: $0.element)
                }
            } header: {
                Text("\(trip.timeRange)  \u{00B7}  \(trip.roadCountLabel), in the order driven")
            } footer: {
                if let route = trip.routeSummary { Text("Through \(route)") }
            }
        }
        .navigationTitle(Text(trip.startedAt, format: .dateTime.month().day()))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                ShareLink(item: DriveLogCSV(driven: trip.roads, fileName: trip.exportFileName),
                          preview: SharePreview("Roads from this drive")) {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
            }
        }
    }
}

private extension DriveTrip {
    var timeRange: String {
        let start = startedAt.formatted(date: .omitted, time: .shortened)
        let end = lastActiveAt.formatted(date: .omitted, time: .shortened)
        return start == end ? start : "\(start)\u{2013}\(end)"
    }
}
