import ActivityKit
import WidgetKit
import SwiftUI
import RoadCore

/// The road you are on, on the lock screen and in the Dynamic Island.
///
/// Everything arrives as finished strings from `DriveActivityState`, so there is no logic here
/// to get wrong and nothing to test in a place tests cannot reach.
struct DriveActivityWidget: Widget {
    /// The lock screen is dark whatever the system appearance is, so this uses the night
    /// palette unconditionally rather than branching on `colorScheme`.
    private static let year = Color(red: 1.00, green: 0.74, blue: 0.40)

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DriveActivityAttributes.self) { context in
            lockScreen(context.state)
                .activityBackgroundTint(Color.black.opacity(0.55))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.road)
                        .font(.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                DynamicIslandExpandedRegion(.leading) {
                    if let owner = context.state.owner {
                        Text(owner).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if let years = context.state.years {
                        Text(years).font(.caption2).foregroundStyle(Self.year).lineLimit(2)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if let context = context.state.context {
                        Text(context).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            } compactLeading: {
                Image(systemName: "car.fill").foregroundStyle(Self.year)
            } compactTrailing: {
                // About four characters fit, so a year or nothing.
                if let year = context.state.compactYear {
                    Text(year).font(.caption2.monospacedDigit()).foregroundStyle(Self.year)
                }
            } minimal: {
                Image(systemName: "car.fill").foregroundStyle(Self.year)
            }
        }
    }

    @ViewBuilder
    private func lockScreen(_ state: DriveActivityState) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: "car.fill").font(.caption2)
                Text("Drive mode").font(.caption2.weight(.semibold))
            }
            .foregroundStyle(.secondary)

            Text(state.road)
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            if let years = state.years {
                Text(years).font(.subheadline.weight(.medium)).foregroundStyle(Self.year)
                    .lineLimit(1)
            }
            if let owner = state.owner {
                Text(owner).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
            }
            if let context = state.context {
                Text(context).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
