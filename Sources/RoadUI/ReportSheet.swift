import SwiftUI
import RoadCore

/// Rate the road here and say what is wrong with it.
struct ReportSheet: View {
    let coordinate: Coordinate
    /// The road as resolved at this spot; copied into the report rather than looked up again.
    let record: RoadRecord?
    let onSave: (RoadReport) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var rating: ConditionRating = .fair
    @State private var issue: RoadIssue = .pavement
    @State private var note = ""

    /// What the county says about this road, when it says anything. Most city streets have no
    /// published rating, and the sheet must not imply otherwise.
    private var countyRating: ConditionRating? {
        ConditionRating.county(record?.surface?.value.conditionRating)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Condition", selection: $rating) {
                        ForEach(ConditionRating.allCases.reversed(), id: \.self) {
                            Text($0.label).tag($0)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text("How is this road?")
                } footer: {
                    // The payoff of borrowing the county's scale.
                    if let disagreement = ConditionRating.disagreement(mine: rating,
                                                                       county: countyRating) {
                        Text(disagreement)
                    } else if let countyRating {
                        Text("The county rates this \(countyRating.label) too.")
                    } else {
                        Text("This is the same five-point scale Maricopa County uses, though it "
                             + "publishes no rating for this road.")
                    }
                }

                Section {
                    Picker("Issue", selection: $issue) {
                        ForEach(RoadIssue.allCases, id: \.self) {
                            Label($0.label, systemImage: $0.symbol).tag($0)
                        }
                    }
                    .labelsHidden()
                } header: {
                    Text("What is wrong")
                } footer: {
                    if let category = issue.countyCategory {
                        Text("Filed under the county's own maintenance category, \(category).")
                    } else {
                        Text("No county maintenance category matches this one.")
                    }
                }

                Section("Note") {
                    TextField("Optional", text: $note, axis: .vertical).lineLimit(2...5)
                }

                Section {
                    LabelledValue(label: "Road",
                                  value: record?.segmentName?.value ?? "Not identified",
                                  attributed: nil)
                    if let cross = record?.crossStreets?.value {
                        LabelledValue(label: "Between", value: cross, attributed: nil)
                    }
                    if let owner = record?.owner?.value.displayName {
                        LabelledValue(label: "Maintained by", value: owner, attributed: nil)
                    }
                } header: {
                    Text("Where")
                } footer: {
                    Text("Recorded as it reads now. The report keeps this even if the sources "
                         + "later answer differently.")
                }
            }
            .navigationTitle("Report an issue")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
            }
        }
    }

    private func save() {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        onSave(RoadReport(
            coordinate: coordinate,
            rating: rating,
            issue: issue,
            note: trimmed.isEmpty ? nil : trimmed,
            roadName: record?.segmentName?.value ?? record?.routeDesignation?.value,
            crossStreets: record?.crossStreets?.value,
            maintainedBy: record?.owner?.value.displayName,
            jurisdiction: record?.jurisdiction?.value,
            segmentIdentifier: record?.segmentIdentifier?.value,
            countyRating: countyRating
        ))
        dismiss()
    }
}

public extension ConditionRating {
    /// Red through green, so a bad stretch reads at a glance on the map.
    var tint: Color {
        switch self {
        case .veryPoor: .red
        case .poor: .orange
        case .fair: .yellow
        case .good: .mint
        case .veryGood: .green
        }
    }
}
