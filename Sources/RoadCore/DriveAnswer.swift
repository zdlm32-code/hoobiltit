import Foundation

/// Whether a refreshed lookup is allowed to replace the answer already on screen.
///
/// Not blanking the card was only half the problem. Sources fail independently — a dead
/// endpoint is recorded in `notes` and the pipeline carries on — so a refresh 250 m down the
/// same road can come back with nothing but a name because one ArcGIS server blinked. Assigned
/// unconditionally, that empties the owner, the years and the detail line and shrinks the card,
/// which at the wheel is the original complaint wearing a different hat.
///
/// So: **on the same road, an answer never loses information to a failed request. On a
/// different road, the truth always wins, however thin it is.** The second half matters as much
/// as the first — a guard that only ever kept the richer record would show the previous road's
/// data after a turn.
public enum DriveAnswer {
    public static func shouldAdopt(new: RoadRecord, over standing: RoadRecord?,
                                   probedRoadChanged: Bool) -> Bool {
        // A different road. Whatever we now know about it is what is true, and holding the
        // previous road's richer record would be a confident lie.
        if probedRoadChanged { return true }
        guard let standing, standing.segmentName != nil || standing.routeDesignation != nil
        else { return true }   // nothing worth protecting

        // The same road, and this pass knows at least as much: take it, so genuinely new
        // facts — a project the first lookup missed — reach the screen.
        if DriveLog.detailCount(new) >= DriveLog.detailCount(standing) { return true }

        // Thinner. Only believable if every source actually answered; otherwise it is a
        // network blip and the standing answer is the better one.
        return new.failures.isEmpty
    }
}
