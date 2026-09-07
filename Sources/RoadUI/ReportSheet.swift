import SwiftUI
import RoadCore

/// Rate the road here and say what is wrong with it.
struct ReportSheet: View {
    let coordinate: Coordinate
    /// The road as resolved at this spot; copied into the report rather than looked up again.
    let record: RoadRecord?
    /// `share` is the per-report choice, not a remembered preference.
    let onSave: (RoadReport, _ share: Bool) -> Void
    /// Whether this device can contribute at all. Reading the pool never depends on this — the
    /// public database is readable without an iCloud account — so a signed-out user still sees
    /// everyone else's reports and simply cannot add their own.
    var canContribute: Bool = false

    @Environment(\.dismiss) private var dismiss
    @State private var rating: ConditionRating = .fair
    @State private var issue: RoadIssue = .pavement
    @State private var note = ""
    /// Off every time. A remembered preference would make the first accidental "yes" permanent,
    /// and the whole point of asking per report is that the answer is a choice each time.
    @State private var share = false

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

                Section {
                    TextField("Optional", text: $note, axis: .vertical).lineLimit(2...5)
                } header: {
                    Text("Note")
                } footer: {
                    Text("Kept on this device. Your note is never part of a shared report.")
                }

                Section {
                    Toggle("Add to the shared map", isOn: $share)
                        .disabled(!canContribute)
                } footer: {
                    if canContribute {
                        // Says exactly what is published, in the order it is published, so the
                        // choice is informed rather than a shrug.
                        Text("Shares your rating and \(issue.label.lowercased()), the road, and "
                             + "roughly where \u{2014} rounded to about 100 metres, and dated to "
                             + "the day. Your note and the exact spot stay on this device. "
                             + "Shared reports are public and you can remove yours later.")
                    } else {
                        Text("Sharing needs an iCloud account. You can still file this report, "
                             + "and you can still see everyone else's.")
                    }
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
        ), share && canContribute)
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
