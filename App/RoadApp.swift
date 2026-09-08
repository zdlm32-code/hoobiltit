import SwiftUI
import RoadUI

@main
struct RoadApp: App {
    /// Runs once, ever. Removing the road-rating feature dropped the `StoredReport` model, and a
    /// dropped model leaves its SwiftData file sitting on disk holding what people wrote — a
    /// coordinate, a time and a note per report — with nothing left in the app able to read it or
    /// erase it. Orphaning personal data is not the same as deleting it, so this deletes it.
    ///
    /// It takes the road-lookup cache with it: `ReportStore` and `SwiftDataFragmentCache` both
    /// used the default `ModelConfiguration`, so both live in `default.store`. That is an
    /// acceptable price — the cache is an optimisation with a thirty-day life that rebuilds
    /// itself on the next lookup — and the alternative, migrating the file to drop one table,
    /// is a lot of machinery to avoid re-fetching some road names.
    @AppStorage("didRemoveRatingStore") private var didRemoveRatingStore = false

    var body: some Scene {
        WindowGroup {
            RoadMapScreen()
                .task { removeRatingStoreIfPresent() }
        }
    }

    private func removeRatingStoreIfPresent() {
        guard !didRemoveRatingStore else { return }
        didRemoveRatingStore = true

        // SwiftData's default store, and the journal files it keeps beside it.
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory,
                                                     in: .userDomainMask).first
        else { return }
        for name in ["default.store", "default.store-shm", "default.store-wal"] {
            try? FileManager.default.removeItem(at: support.appendingPathComponent(name))
        }
    }
}
