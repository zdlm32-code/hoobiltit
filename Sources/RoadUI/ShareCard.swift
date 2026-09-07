import SwiftUI
import UniformTypeIdentifiers
import RoadCore

/// The image handed to the share sheet: one road, answered.
///
/// A fixed 1200×630 rather than `ImageRenderer` over `SegmentCard`, for four reasons. That view's
/// height depends on how much resolved, so the aspect ratio would change with data quality. It
/// renders an "according to X, matched by location" line under every value, which is the point on
/// screen and illegible at thumbnail size. Its on-screen instance is clipped inside a `ScrollView`
/// with a gradient mask. And its background follows the environment, so a card shared at dusk
/// would come out dark — a shared artefact has to be the same every time.
///
/// Composed from `DriveCardContent`, which exists to be exactly this plain-string projection of a
/// record. Using it here means the drive card, the Live Activity and the shared image cannot
/// disagree about what road you are on, and the wording is already covered by tests.
struct ShareCard: View {
    let content: DriveCardContent

    static let size = CGSize(width: 1200, height: 630)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("WHO BUILT THIS ROAD?")
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .tracking(2)

            Spacer(minLength: 24)

            Text(content.roadName ?? "Unidentified road")
                .font(.system(size: 96, weight: .bold, design: .rounded))
                .lineLimit(2)
                .minimumScaleFactor(0.45)

            if let context = content.context {
                Text(context)
                    .font(.system(size: 34))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.top, 6)
            }

            Spacer(minLength: 20)

            // The answer, in the app's own hierarchy: the years first, then who maintains it.
            if !content.years.isEmpty {
                Text(content.years.joined(separator: "   \u{00B7}   "))
                    .font(.system(size: 48, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.accentColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            } else if let note = content.dateNote {
                Text(note)
                    .font(.system(size: 34))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            if let owner = content.owner {
                Text(owner)
                    .font(.system(size: 38, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.top, 10)
            }

            if !content.details.isEmpty {
                Text(content.details.joined(separator: "   \u{00B7}   "))
                    .font(.system(size: 26))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .padding(.top, 8)
            }

            Spacer(minLength: 24)

            HStack {
                Image(systemName: "road.lanes")
                Text("hoobiltit.com")
                Spacer()
            }
            .font(.system(size: 26, weight: .medium))
            .foregroundStyle(.secondary)
        }
        .padding(56)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .background(Color(white: 0.97))
        // Pinned, so the image never inherits the night palette the map may be using.
        .environment(\.colorScheme, .light)
    }

    /// Renders the card to PNG data.
    ///
    /// `ImageRenderer` is `@MainActor`, so this happens at share time rather than on a background
    /// actor. Nil off iOS, which only the macOS test build hits.
    @MainActor
    static func png(_ content: DriveCardContent) -> Data? {
        let renderer = ImageRenderer(content: ShareCard(content: content))
        renderer.scale = 3
        #if canImport(UIKit)
        return renderer.uiImage?.pngData()
        #else
        return nil
        #endif
    }

    /// The plain-text answer, for a target that cannot take an image.
    ///
    /// Carries **no coordinate**, deliberately — see `RoadShare`.
    static func text(_ content: DriveCardContent) -> String {
        var lines = [content.roadName ?? "Unidentified road"]
        if let context = content.context { lines.append(context) }
        if !content.years.isEmpty { lines.append(content.years.joined(separator: " \u{00B7} ")) }
        if let owner = content.owner { lines.append(owner) }
        lines.append("\nWho built this road? \u{2014} https://hoobiltit.com")
        return lines.joined(separator: "\n")
    }
}

/// What leaves the app when you share a road.
///
/// **Never a serialised `RoadRecord`.** Every field on a record carries a `Provenance`, whose
/// `url` is documented as *"the precise request URL… so it can be re-run"* — and `ArcGISClient`
/// builds that query's `geometry` as an envelope centred on the pin, so the exact coordinate is
/// recoverable by averaging the corners, and `fetchedAt` gives the moment somebody was standing
/// there. A resolved record carries a dozen of those. Handing one to a third party is handing
/// them a location log.
///
/// So a rendered card and a plain-text fallback, neither containing a coordinate. `RoadRecord` is
/// also deliberately left non-`Codable` — see the note on `Coverage` — so this cannot be got
/// wrong by accident later.
struct RoadShare: Transferable {
    let png: Data
    let text: String

    static var transferRepresentation: some TransferRepresentation {
        // Order is load-bearing: `Transferable` prefers earlier representations, so Messages,
        // Photos and AirDrop take the image and a plain-text field takes the string.
        DataRepresentation(exportedContentType: .png) { $0.png }
            .suggestedFileName("who-built-this-road.png")
        ProxyRepresentation(exporting: \.text)
    }
}
