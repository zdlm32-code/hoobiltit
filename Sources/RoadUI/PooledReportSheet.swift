import SwiftUI
import RoadCore

/// One of everyone else's reports.
///
/// Shows what was published and nothing more — there is no author, no note and no exact time,
/// because none of those were shared. The flag button is the whole of the moderation surface,
/// which is small because the content is: two closed vocabularies, no free text, so there is
/// nothing objectionable a stranger can put here in the first place.
struct PooledReportSheet: View {
    let report: PooledReport
    let onFlag: (UUID) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var flagged = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabelledValue(label: "Rated", value: report.rating.label, attributed: nil)
                    LabelledValue(label: "Issue", value: report.issue.label, attributed: nil)
                    if let county = report.countyRating,
                       let disagreement = ConditionRating.disagreement(mine: report.rating,
                                                                       county: county) {
                        Text(disagreement).font(.footnote).foregroundStyle(.secondary)
                    }
                } header: {
                    Text(report.roadName ?? "A road here")
                } footer: {
                    Text("Reported \(CalendarDate.medium(report.reportedOn)). Shared reports "
                         + "carry a date but no time, and a location rounded to about 100 metres.")
                }

                if report.maintainedBy != nil || report.jurisdiction != nil {
                    Section("The road") {
                        if let owner = report.maintainedBy {
                            LabelledValue(label: "Maintained by", value: owner, attributed: nil)
                        }
                        if let jurisdiction = report.jurisdiction {
                            LabelledValue(label: "Jurisdiction", value: jurisdiction, attributed: nil)
                        }
                    }
                }

                Section {
                    Button(flagged ? "Reported" : "Report this marker", systemImage:
                            flagged ? "checkmark" : "flag") {
                        flagged = true
                        Task { await onFlag(report.id) }
                    }
                    .disabled(flagged)
                } footer: {
                    Text("A marker reported by several people stops being shown. "
                         + "Questions: support@hoobiltit.com")
                }
            }
            .navigationTitle("Shared report")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium])
    }
}
