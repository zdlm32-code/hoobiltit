import SwiftUI
import RoadCore

/// What drive mode shows while the car is moving.
///
/// Deliberately not the result card. At the wheel you have about half a second of attention, so
/// the road name, who maintains it and the years stay in large type and everything else is
/// arranged underneath in decreasing size — legible at a glance, readable at a light, ignorable
/// at speed. Anything needing a tap waits until you have stopped, which is what the drive log
/// and the result screen are for.
struct DriveSummary: View {
    let record: RoadRecord?
    let isResolving: Bool
    let logCount: Int
    /// A background refresh behind an answer already on screen. Deliberately not rendered —
    /// kept because the Live Activity controller wants to know.
    var isRefreshing: Bool = false
    var palette: DriveCardPalette = .day
    /// Opens the drive log. Defaulted so the existing tests construct the card unchanged.
    var onOpenLog: () -> Void = {}
    /// Opens the full detail for the road on the card.
    var onOpenDetail: () -> Void = {}
    /// Content carried across refreshes, so a slot one lookup could not fill does not blink.
    var sticky: DriveCardContent? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header

            // The road. Everything else on the card qualifies this line.
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(headline)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(record?.segmentName == nil && !isResolving
                                     ? palette.context : palette.headline)
                // The only sign the card is tappable. A full-width button would have cost the
                // height the card was just tuned to keep.
                if record?.segmentName != nil || record?.routeDesignation != nil {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(palette.context)
                }
            }

            // The answer to the question the app asks, so it sits second and it is the only
            // coloured thing on the card. Reserved height: this is the row that comes and goes
            // most between refreshes, and a card that changes height under a driver's eyes is
            // the thing being fixed.
            Group {
                if !years.isEmpty {
                    Text(years.joined(separator: "  \u{00B7}  "))
                        .foregroundStyle(palette.year)
                } else if let dateNote {
                    // Never a hole. A missing year is a fact about what agencies publish, and
                    // saying so is more useful than a blank space that reads as a bug.
                    Text(dateNote).foregroundStyle(palette.detail)
                } else {
                    Text(" ")
                }
            }
            .font(.system(size: 22, weight: .medium, design: .rounded))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(height: 26, alignment: .leading)

            if let owner = record?.owner?.value.displayName {
                Text(owner)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(palette.owner)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            // Which stretch of a long road the rest of the card is describing.
            if let between = record?.crossStreets?.value {
                Text(between)
                    .font(.system(size: 15))
                    .foregroundStyle(palette.context)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            // One line, truncated rather than wrapped. `details` is ordered classification,
            // lanes, condition, traffic — which is also the right order to lose them in on a
            // narrow screen, so the pinned test order doubles as the responsive rule.
            if !details.isEmpty {
                Text(details.joined(separator: "  \u{00B7}  "))
                    .font(.system(size: 13))
                    .foregroundStyle(palette.detail)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            if let project = record?.project?.value ?? record?.lastKnownImprovement?.value {
                Label(SegmentCard.describe(project), systemImage: "hammer.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(palette.detail)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 168, alignment: .topLeading)
        .background(palette.background, in: RoundedRectangle(cornerRadius: 18))
        .shadow(color: .black.opacity(palette.shadow > 0 ? 0.12 : 0), radius: palette.shadow, y: 1)
        // The content swap on a refresh must not animate; only a genuine road change should
        // read as a change.
        .transaction { $0.animation = nil }
        // `.onTapGesture` rather than wrapping the card in a Button: the road-count chip in the
        // header is already a Button, and a child Button consumes the tap before an ancestor
        // gesture sees it. Nested Buttons would make that precedence ambiguous, and getting it
        // wrong means the road count silently opens the wrong screen.
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpenDetail)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Opens everything known about this road")
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "car.fill").font(.footnote)
            Text("Drive mode").font(.footnote.weight(.semibold))
            // Deliberately no spinner for `isRefreshing`. A background check runs roughly
            // every 12 s and the ask was for it to be invisible; a pulsing indicator is
            // the same complaint at a tenth the scale. Only the first answer shows one.
            if isResolving { ProgressView().controlSize(.mini) }
            Spacer()
            if let tier = coverageTier {
                Text(tier)
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }
            if logCount > 0 {
                // Was inert text. It is the obvious way into the drive log, and now that
                // `DriveLog` collapses consecutive lookups the number it shows is honest
                // enough to be worth tapping.
                Button(action: onOpenLog) {
                    Label("\(logCount) road\(logCount == 1 ? "" : "s")", systemImage: "chevron.right")
                        .labelStyle(.titleAndIcon)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 6)
                        .padding(.leading, 8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(logCount) roads this drive. Open the drive log.")
            }
        }
        .foregroundStyle(palette.context)
    }

    /// "Looking…" only while something is actually running. A finished lookup that found no
    /// road has to say so — an indefinite "Looking…" is indistinguishable from a hang, which
    /// is exactly how this failed on the road.
    var headline: String {
        if let name = content.roadName { return name }
        if isResolving { return "Looking\u{2026}" }
        return record == nil ? "Waiting for a fix\u{2026}" : "No road identified here"
    }

    /// The card's content, from the shared rules in `RoadCore`. `sticky` is the live one the
    /// model maintains across refreshes; tests construct the card without it and get a plain
    /// reading of the record, which is why every existing assertion still holds.
    var content: DriveCardContent {
        sticky ?? DriveCardContent(record: record)
    }

    var years: [String] { content.years }
    var details: [String] { content.details }
    var coverageTier: String? { content.tier }
    var dateNote: String? { content.dateNote }
}
