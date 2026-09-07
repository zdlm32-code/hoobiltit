import SwiftUI
import RoadCore

/// A scale bar drawn from the region the screen already tracks.
///
/// Replaces `MapScaleView`, which does not refresh when the camera is moved programmatically —
/// so it read "15 mi" while the map sat at 400 m, and it is programmatic camera moves that
/// this app makes constantly while following the device.
struct MapScaleBar: View {
    let span: MapSpan
    let latitude: Double
    /// Width available to the bar; the drawn length is whatever round distance fits inside it.
    var maxWidth: CGFloat = 130

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(measurement.label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
            Capsule()
                .fill(.primary.opacity(0.55))
                .frame(width: barWidth, height: 3)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.background.secondary.opacity(0.85), in: RoundedRectangle(cornerRadius: 7))
        .accessibilityLabel("Scale: \(measurement.label)")
    }

    /// Metres covered by one point of screen width at this latitude.
    private var metresPerPoint: Double {
        let visibleWidth = span.longitudeDelta * 111_320 * cos(latitude * .pi / 180)
        // The span is the whole map width; the bar only gets `maxWidth` of it.
        return visibleWidth / Double(UIScreenWidth)
    }

    private var measurement: (metres: Double, label: String) {
        Geo.scaleBarDistance(fitting: metresPerPoint * Double(maxWidth))
    }

    private var barWidth: CGFloat {
        guard metresPerPoint > 0 else { return maxWidth }
        return min(maxWidth, CGFloat(measurement.metres / metresPerPoint))
    }

    /// Screen width in points, for turning a span into metres-per-point.
    private var UIScreenWidth: CGFloat {
        #if os(iOS)
        UIScreen.main.bounds.width
        #else
        390
        #endif
    }
}

#if os(iOS)
import UIKit
#endif
