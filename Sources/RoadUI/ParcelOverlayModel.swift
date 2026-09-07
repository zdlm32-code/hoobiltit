import Foundation
import MapKit
import Observation
import RoadCore
import RoadSources

/// Keeps the parcel boundaries the map is currently showing.
///
/// This is the app's first feature that spends network while you merely move the map, so it is
/// built around not fetching: a zoom gate, and a containment cache that makes panning within a
/// block free. `.onMapCameraChange(frequency: .onEnd)` is the debounce — it fires when panning
/// stops, not during — so no timer is needed.
@MainActor
@Observable
public final class ParcelOverlayModel {
    public private(set) var outlines: [ParcelOutline] = []
    public private(set) var isLoading = false
    /// Set when the viewport is too wide to draw, so the map can say why rather than going
    /// mysteriously blank.
    public private(set) var hiddenBecauseZoomedOut = false
    public private(set) var possiblyTruncated = false

    /// Fetched region, grown a little so a nudge does not immediately refetch.
    private var coveredEnvelope: Envelope?
    /// What the in-flight request will cover. Without this, every camera event cancels the
    /// request started by the previous one and the fetch never finishes — `onMapCameraChange`
    /// fires several times for a single settle.
    private var pendingEnvelope: Envelope?
    private var inFlight: Task<Void, Never>?
    private let service: ParcelBoundaryService

    /// How many requests this model has actually issued. Exposed for verifying that panning
    /// inside a covered block is free.
    public private(set) var requestCount = 0

    public init(service: ParcelBoundaryService = ParcelBoundaryService()) {
        self.service = service
    }

    /// Whether the county in view publishes parcels this build can draw. Set from the
    /// coverage catalog; false everywhere no profile claims them, so the overlay costs
    /// nothing outside the counties that actually have one.
    public var isAvailable = false

    public func update(for region: MKCoordinateRegion) {
        guard isAvailable else {
            inFlight?.cancel()
            outlines = []
            coveredEnvelope = nil
            pendingEnvelope = nil
            hiddenBecauseZoomedOut = false
            possiblyTruncated = false
            return
        }
        let span = region.mapSpan
        guard Geo.parcelsWorthDrawing(at: span) else {
            inFlight?.cancel()
            hiddenBecauseZoomedOut = true
            outlines = []
            coveredEnvelope = nil
            pendingEnvelope = nil
            possiblyTruncated = false
            return
        }
        hiddenBecauseZoomedOut = false

        let visible = Self.envelope(of: region)
        if let covered = coveredEnvelope, covered.contains(visible) { return }
        // A request already on its way that will cover this view is not worth restarting.
        if let pending = pendingEnvelope, pending.contains(visible) { return }

        // Fetch a little more than is on screen so small pans stay inside the cache.
        let target = visible.expanded(by: 0.25)
        inFlight?.cancel()
        pendingEnvelope = target
        inFlight = Task { [service] in
            isLoading = true
            requestCount += 1
            defer { isLoading = false }
            do {
                let result = try await service.outlines(in: target, span: span)
                guard !Task.isCancelled else { return }
                pendingEnvelope = nil
                outlines = result?.outlines ?? []
                possiblyTruncated = result?.possiblyTruncated ?? false
                coveredEnvelope = result == nil ? nil : target
            } catch {
                // A failed overlay is cosmetic; the road answer does not depend on it. Leave
                // whatever is on screen rather than blanking the map.
                guard !Task.isCancelled else { return }
                pendingEnvelope = nil
                coveredEnvelope = nil
            }
        }
    }

    public func clear() {
        inFlight?.cancel()
        outlines = []
        coveredEnvelope = nil
        pendingEnvelope = nil
        possiblyTruncated = false
    }

    static func envelope(of region: MKCoordinateRegion) -> Envelope {
        Envelope(xmin: region.center.longitude - region.span.longitudeDelta / 2,
                 ymin: region.center.latitude - region.span.latitudeDelta / 2,
                 xmax: region.center.longitude + region.span.longitudeDelta / 2,
                 ymax: region.center.latitude + region.span.latitudeDelta / 2)
    }
}
