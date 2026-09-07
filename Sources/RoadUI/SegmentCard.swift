import SwiftUI
import RoadCore

/// What the map screen shows once a pin resolves.
///
/// Deliberately compact: it answers "which road is this and whose is it", and leaves the full
/// provenance display and the public-records fallbacks to the result screen. What it does not
/// do is hide the shape of the answer — a road with no project says so rather than showing
/// blank space.
struct SegmentCard: View {
    let record: RoadRecord
    let placeName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if let owner = record.owner {
                Divider()
                LabelledValue(label: "Maintained by",
                              value: owner.value.displayName,
                              attributed: owner)
            }
            if let classification = record.classification {
                LabelledValue(label: "Classification",
                              value: classification.value,
                              attributed: classification)
            }
            if let crossStreets = record.crossStreets {
                LabelledValue(label: "Between",
                              value: crossStreets.value,
                              attributed: crossStreets)
            }
            if let surface = record.surface {
                LabelledValue(label: "Surface",
                              value: surfaceSummary(surface.value),
                              attributed: surface)
            }
            if let traffic = record.trafficCount {
                LabelledValue(label: "Traffic",
                              value: "\(traffic.value.formatted(.number)) vehicles a day",
                              attributed: traffic)
            }

            datesSection
            projectSection
            platSection

            if record.isEmpty {
                Text("No public source identified a road here. Try a pin closer to the centerline.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            // Names the gap and whose gap it is. A blank field with no explanation reads as a
            // broken app; saying that nothing local is mapped for this county, or that a
            // state dates only its own roads, is itself an answer.
            if let explanation = record.coverage?.explanation(for: record) {
                Divider()
                Text(explanation)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(record.segmentName?.value ?? record.routeDesignation?.value ?? "Unidentified road")
                .font(.title2.weight(.semibold))
            if let placeName {
                Text(placeName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var datesSection: some View {
        // Never fused into one "built in YYYY" — they are different facts from different
        // sources, and most roads have neither.
        if let built = record.yearLastConstruction {
            LabelledValue(label: "Last constructed", value: built.value.formatted(.dateTime.month().year()),
                          attributed: built)
        }
        if let improved = record.yearLastImprovement {
            LabelledValue(label: "Last improved", value: improved.value.formatted(.dateTime.month().year()),
                          attributed: improved)
        }
    }

    @ViewBuilder
    private var projectSection: some View {
        if let project = record.project {
            Divider()
            LabelledValue(label: "Built under",
                          value: SegmentCard.describe(project.value),
                          attributed: project)
            if let phase = project.value.phase {
                Text(phase).font(.caption).foregroundStyle(.secondary)
            }
            if let detail = project.value.detail {
                Text(detail).font(.footnote).foregroundStyle(.secondary)
            }
        }
        if let improvement = record.lastKnownImprovement {
            LabelledValue(label: "Last project",
                          value: SegmentCard.describe(improvement.value),
                          attributed: improvement)
        }
    }

    @ViewBuilder
    private var platSection: some View {
        if let plat = record.plat {
            Divider()
            LabelledValue(label: "Platted as", value: plat.value.subdivisionName, attributed: plat)
            if let url = plat.value.recorderURL {
                Link(destination: url) {
                    Label(plat.value.recorderNumber.map { "Recorded plat \($0)" } ?? "Recorded plat",
                          systemImage: "doc.text")
                        .font(.footnote)
                }
            }
        }
    }

    /// ADOT has no project *names*, only TRACS numbers, so its titles are built from the
    /// number itself. Joining the two would read "H729601C \u{2014} ADOT project H729601C".
    static func describe(_ project: ProjectReference) -> String {
        guard let number = project.projectNumber else { return project.title }
        guard !project.title.contains(number) else { return project.title }
        return "\(number) \u{2014} \(project.title)"
    }

    private func surfaceSummary(_ surface: SurfaceDescription) -> String {
        var parts = [surface.type]
        if let depth = surface.depthInches, depth > 0 {
            parts.append("\(depth.formatted(.number.precision(.fractionLength(0...1))))\u{2033}"
                         + (surface.baseType.map { " over \($0)" } ?? ""))
        }
        if let lanes = surface.laneCount { parts.append("\(lanes) lanes") }
        // The county's own words beat its index: "condition very good" reads, "99/100" needs
        // explaining. The index is the fallback for the ~950 segments with no rating.
        if let rating = surface.conditionRating {
            parts.append("condition \(rating.lowercased())")
        } else if let index = surface.conditionIndex {
            parts.append("condition \(Int(index.rounded()))/100")
        }
        return parts.joined(separator: ", ")
    }
}

/// A field and its receipt. Nothing reaches the screen without naming where it came from.
struct LabelledValue: View {
    let label: String
    let value: String
    let attributed: (any AttributedDescribing)?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text(value)
                .font(.body)
            if let attributed {
                Text(attribution(attributed))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func attribution(_ source: any AttributedDescribing) -> String {
        var text = "according to \(source.sourceName)"
        switch source.confidence {
        case .direct: break
        case .spatial: text += ", matched by location"
        case .nameMatch: text += ", matched by name"
        case .derived: text += ", inferred"
        }
        if source.isBundled { text += " (bundled snapshot)" }
        return text
    }
}
