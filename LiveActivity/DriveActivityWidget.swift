import ActivityKit
import WidgetKit
import SwiftUI
import RoadCore

/// The road you are on, on the lock screen and in the Dynamic Island.
///
/// Everything arrives as finished strings from `DriveActivityState`, so there is no logic here
/// to get wrong and nothing to test in a place tests cannot reach.
struct DriveActivityWidget: Widget {
    /// Fixed colours, never adaptive ones.
    ///
    /// The box used to be a 55% black tint with `.primary`/`.secondary` text, on the belief that
    /// the lock screen is always dark. It is not: those styles follow the system appearance, so
    /// in Light mode the text resolved to dark grey on a dark tint — and the tint let the
    /// wallpaper through, so the box took on whatever colours the wallpaper had. An opaque
    /// background and pinned text read the same on every wallpaper, in either mode.
    ///
    /// Mirrors `DriveCardPalette.night` in RoadUI, a step brighter for daylight. Repeated rather
    /// than shared because the extension links only RoadCore.
    private enum Ink {
        static let background = Color(white: 0.07)
        static let headline = Color(white: 0.95)
        static let owner = Color(white: 0.78)
        static let context = Color(white: 0.62)
        static let year = Color(red: 1.00, green: 0.74, blue: 0.40)
    }

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DriveActivityAttributes.self) { context in
            lockScreen(context.state)
                .activityBackgroundTint(Ink.background)
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 1) {
                        if let city = context.state.city {
                            Text(city).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Text(context.state.road)
                            .font(.headline)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                }
                DynamicIslandExpandedRegion(.leading) {
                    if let owner = context.state.owner {
                        Text(owner).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if let years = context.state.years {
                        Text(years).font(.caption2).foregroundStyle(Ink.year).lineLimit(2)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if let context = context.state.context {
                        Text(context).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            } compactLeading: {
                Image(systemName: "car.fill").foregroundStyle(Ink.year)
            } compactTrailing: {
                // About four characters fit, so a year or nothing.
                if let year = context.state.compactYear {
                    Text(year).font(.caption2.monospacedDigit()).foregroundStyle(Ink.year)
                }
            } minimal: {
                Image(systemName: "car.fill").foregroundStyle(Ink.year)
            }
        }
    }

    @ViewBuilder
    private func lockScreen(_ state: DriveActivityState) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            // Where you are, first. iOS decides where the banner sits on the lock screen — at
            // the bottom, with notifications — so the city leads the banner instead.
            HStack(spacing: 5) {
                Image(systemName: state.city == nil ? "car.fill" : "mappin.and.ellipse")
                Text(state.city ?? "Drive mode")
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Ink.headline)
            .lineLimit(1)
            .minimumScaleFactor(0.7)

            Text(state.road)
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .foregroundStyle(Ink.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            if let years = state.years {
                Text(years).font(.subheadline.weight(.medium)).foregroundStyle(Ink.year)
                    .lineLimit(1)
            }
            if let owner = state.owner {
                Text(owner).font(.footnote).foregroundStyle(Ink.owner).lineLimit(1)
            }
            if let context = state.context {
                Text(context).font(.caption).foregroundStyle(Ink.context).lineLimit(1)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Belt and braces: anything adaptive left in here resolves against the dark box.
        .environment(\.colorScheme, .dark)
    }
}
