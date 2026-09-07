import WidgetKit
import SwiftUI

/// The widget-extension entry point.
///
/// It exists so the app can put the road you are on onto the lock screen and into the Dynamic
/// Island — a Live Activity is the only way iOS lets an app hold a place there, and drive mode
/// is exactly the "ongoing event" the API is for.
@main
struct RoadActivityBundle: WidgetBundle {
    var body: some Widget {
        DriveActivityWidget()
    }
}
