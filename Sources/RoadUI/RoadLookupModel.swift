import Foundation
import CoreLocation
import MapKit
import Observation
import RoadCore
import RoadSources
import RoadStore

/// Drives the map screen: a pin goes in, a `RoadRecord` comes out.
///
/// There is no error state for "nothing found". The resolver always returns a record, and a
/// sparse one is a real answer — an empty MCDOT response is how the app learns a city
/// maintains the road. Only a lookup that could not run at all is a failure.
@MainActor
@Observable
public final class RoadLookupModel {
    public enum Phase: Equatable {
        case idle
        case resolving
        case resolved
    }

    public private(set) var phase: Phase = .idle
    public private(set) var record: RoadRecord?
    /// Reverse-geocoded label for the pin. Context only — it never affects the record, and
    /// its failure is not the lookup's failure.
    public private(set) var placeName: String?
    public private(set) var pin: CLLocationCoordinate2D?
    public var searchText: String = ""
    public private(set) var searchFailure: String?
    /// The map's current viewport, so address search is biased to what the user is looking at.
    public var searchRegion: MKCoordinateRegion?
    /// Whether the county last resolved publishes parcels this build can draw.
    public private(set) var parcelsAvailable = false

    /// True while drive mode is identifying roads automatically.
    public private(set) var isDriving = false
    /// A background refresh is in flight behind an answer already on screen. Distinct from
    /// `phase`, so nothing on the card has to react to it.
    public private(set) var isRefreshing = false
    /// What drive mode should display, carried across refreshes so a slot one lookup could not
    /// fill does not blink out and back. Also what the Live Activity publishes, so the card and
    /// the lock screen cannot disagree about the road you are on.
    public private(set) var driveCard = DriveCardContent(record: nil)
    /// Roads identified this drive, newest first, so the trip can be read back afterwards.
    public private(set) var driveLog: [RoadRecord] = []

    private let factory: PipelineFactory
    private let locator: JurisdictionLocator
    private let cache: (any FragmentCache)?
    /// One resolver per county, built on first use. Rebuilding the pipeline per lookup would
    /// be cheap, but keeping them means a drive down one road reuses the same sources.
    private var resolvers: [String: RoadResolver] = [:]
    private var probes: [String: RoadNameProbe] = [:]
    private let geocoder = CLGeocoder()
    private var inFlight: Task<Void, Never>?
    /// Name the probe last saw. A full lookup runs only when this changes.
    private var lastProbedRoad: String?
    /// County the last fix was in. A road that crosses a county line keeps its name and
    /// changes its owner, so the name alone is not enough to decide when to re-resolve.
    private var lastCountyFIPS: String?
    private var lastResolvedAt: Coordinate?
    private var probeInFlight = false

    /// - Parameter cache: pass `.none` to run without one. Tests do, so a stored answer from
    ///   an earlier run cannot make a lookup return instantly and change what is being tested.
    public init(factory: PipelineFactory? = nil, locator: JurisdictionLocator? = nil,
                cache: (any FragmentCache)?? = nil) {
        // A cache is a convenience, never a requirement: if the store cannot be opened the
        // app still works, it just asks the agencies every time.
        self.cache = cache ?? (try? SwiftDataFragmentCache())
        self.factory = factory ?? PipelineFactory()
        self.locator = locator ?? JurisdictionLocator()
    }

    /// Jurisdiction, then the pipeline it selects.
    ///
    /// The locator answers from a held county boundary without touching the network for as
    /// long as the car stays in one county, so this is affordable on every fix.
    private func pipeline(at coordinate: Coordinate) async
        -> (resolver: RoadResolver, probe: RoadNameProbe, coverage: Coverage) {
        let jurisdiction = await locator.locate(coordinate)
        let key = jurisdiction?.countyFIPS ?? "-"
        let built = factory.pipeline(for: jurisdiction)

        parcelsAvailable = factory.hasParcels(jurisdiction)
        let resolver = resolvers[key] ?? RoadResolver(sources: built.sources, cache: cache)
        resolvers[key] = resolver
        let probe = probes[key] ?? factory.probe(for: jurisdiction)
        probes[key] = probe
        return (resolver, probe, built.coverage)
    }

    // MARK: - Drive mode

    public func setDriving(_ on: Bool) {
        isDriving = on
        if !on {
            lastProbedRoad = nil
            lastResolvedAt = nil
            lastCountyFIPS = nil
            driveCard = DriveCardContent(record: nil)
        }
    }

    /// Called for each location fix while driving.
    ///
    /// Runs the cheap probe, and only when the road *name* changes does it spend a full
    /// six-source lookup. Re-resolving on distance or on a timer would re-ask every agency the
    /// same question for the length of a straight road.
    public func handleDrivingFix(_ coordinate: CLLocationCoordinate2D) async {
        guard isDriving, !probeInFlight else { return }
        probeInFlight = true
        defer { probeInFlight = false }

        let point = Coordinate(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let (_, probe, coverage) = await pipeline(at: point)
        let hit = await probe.nearestRoad(to: point)
        let county = coverage.jurisdiction?.countyFIPS
        let onRoad = hit.flatMap { $0.metresAway < DriveTrigger.onRoadMeters ? $0 : nil }
        let probed = onRoad.map { RoadName.comparisonKey($0.name) }

        let decision = DriveTrigger.Input(
            probedRoad: probed,
            lastProbedRoad: lastProbedRoad,
            countyFIPS: county,
            lastCountyFIPS: lastCountyFIPS,
            metresSinceLastResolve: lastResolvedAt.map { Geo.distance($0, point) },
            hasStandingAnswer: record?.segmentName != nil)

        lastCountyFIPS = county ?? lastCountyFIPS
        guard DriveTrigger.shouldResolve(decision) else { return }
        // Read before the assignment below: a road change is what licenses a thin answer to
        // replace a rich one.
        let probedRoadChanged = probed != lastProbedRoad
        lastProbedRoad = probed

        lastResolvedAt = point
        let resolved = await refresh(at: coordinate, probedRoadChanged: probedRoadChanged)
        appendToDriveLog(resolved)
    }

    /// One identification, regardless of whether the car is moving. Used on opening so a
    /// parked phone still says which road it is sitting on.
    public func identifyOnce(at coordinate: CLLocationCoordinate2D) async {
        guard !probeInFlight else { return }
        probeInFlight = true
        defer { probeInFlight = false }
        let point = Coordinate(latitude: coordinate.latitude, longitude: coordinate.longitude)
        lastResolvedAt = point
        let resolved = await resolve(at: coordinate, reverseGeocode: true)
        driveCard = DriveCardContent(record: record, placeName: placeName)
            .sticking(to: driveCard)
        let (_, probe, coverage) = await pipeline(at: point)
        lastCountyFIPS = coverage.jurisdiction?.countyFIPS
        if let hit = await probe.nearestRoad(to: point), hit.metresAway < 60 {
            lastProbedRoad = RoadName.comparisonKey(hit.name)
        }
        if isDriving { appendToDriveLog(resolved) }
    }

    /// One entry per road, not one per lookup. See `DriveLog`.
    private func appendToDriveLog(_ record: RoadRecord) {
        driveLog = DriveLog.appending(record, to: driveLog)
    }

    public func clearDriveLog() { driveLog.removeAll() }

    /// Drops the pin and resolves it, replacing any lookup already running.
    public func drop(at coordinate: CLLocationCoordinate2D) {
        inFlight?.cancel()
        inFlight = Task { _ = await resolve(at: coordinate, reverseGeocode: true) }
    }

    /// Runs the pipeline and publishes the result.
    ///
    /// `phase` reaches `.resolved` as soon as the resolver answers; the reverse geocode that
    /// fills `placeName` happens *after*, and never gates it. It used to be awaited alongside
    /// the resolve, which meant a throttled `CLGeocoder` — and Apple throttles it hard when
    /// called repeatedly, which is exactly what driving does — left the screen on "Looking…"
    /// with a finished answer sitting behind it.
    @discardableResult
    private func resolve(at coordinate: CLLocationCoordinate2D,
                         reverseGeocode: Bool) async -> RoadRecord {
        pin = coordinate
        placeName = nil
        record = nil
        searchFailure = nil
        phase = .resolving

        let resolved = await lookup(at: coordinate)
        record = resolved
        phase = .resolved

        if reverseGeocode {
            placeName = await placeName(for: coordinate)
        }
        return resolved
    }

    /// A drive-mode refresh: the *same* question asked again, a little further down the road.
    ///
    /// Deliberately not `resolve`. That one blanks the screen first, which is right for a pin
    /// drop — a new question deserves a clean slate — and wrong for driving, where it is the
    /// reason the card read "Looking…" for fifteen minutes on one road. Drive mode re-resolves
    /// roughly every 250 m and each lookup takes seconds across a dozen requests, so a card
    /// that blanks on every refresh is blank most of the time.
    ///
    /// The standing answer therefore stays on screen and is replaced only once the new one has
    /// arrived. `phase` is left alone too, which is what stops the aiming reticle flashing over
    /// the blue dot on each refresh.
    @discardableResult
    private func refresh(at coordinate: CLLocationCoordinate2D,
                         probedRoadChanged: Bool) async -> RoadRecord {
        // Deliberately does *not* move `pin`. The map draws a red marker at `model.pin`, and
        // moving it here made one teleport onto the blue dot every 250 m — a refresh tell as
        // obvious as the blanking it replaced. While driving, the blue dot is the pin.
        //
        // Only the genuine first answer of a drive earns "Looking…"; after that there is
        // always something true to show while the next one is fetched.
        if record == nil { phase = .resolving }
        isRefreshing = true
        defer { isRefreshing = false }

        let resolved = await lookup(at: coordinate)
        if DriveAnswer.shouldAdopt(new: resolved, over: record,
                                   probedRoadChanged: probedRoadChanged) {
            record = resolved
        }
        driveCard = DriveCardContent(record: record, placeName: placeName)
            .sticking(to: driveCard)
        phase = .resolved
        // The log sees every result regardless; only the card is protected.
        return resolved
    }

    /// The lookup itself, with no opinion about what the screen should show while it runs.
    private func lookup(at coordinate: CLLocationCoordinate2D) async -> RoadRecord {
        let point = Coordinate(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let (resolver, _, coverage) = await pipeline(at: point)
        var resolved = await resolver.resolve(
            RoadQuery(latitude: coordinate.latitude, longitude: coordinate.longitude))
        // Attached after resolution, never merged: only the factory can tell "no source is
        // mapped for this county" from "a source is mapped and found nothing", and that
        // distinction is the whole content of what the card explains.
        resolved.coverage = coverage
        return resolved
    }

    /// Finds an address and drops a pin on it.
    public func search() async {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        searchFailure = nil

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        // Biased to what the user is looking at rather than to a fixed county, so "Yuma Rd"
        // finds the one on screen. A constant here meant every search in the country was
        // pulled back to Phoenix.
        request.region = searchRegion ?? .continentalUS

        do {
            let response = try await MKLocalSearch(request: request).start()
            guard let match = response.mapItems.first else {
                searchFailure = "No match for \u{201C}\(query)\u{201D} near here."
                return
            }
            drop(at: match.placemark.coordinate)
        } catch {
            searchFailure = "Address search failed: \(error.localizedDescription)"
        }
    }

    public func clear() {
        inFlight?.cancel()
        phase = .idle
        record = nil
        placeName = nil
        pin = nil
        searchFailure = nil
    }

    /// Stays on the main actor: `CLGeocoder` is not `Sendable`, so it cannot cross one.
    private func placeName(for coordinate: CLLocationCoordinate2D) async -> String? {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        guard let placemark = try? await geocoder.reverseGeocodeLocation(location).first else {
            return nil
        }
        let parts = [placemark.name, placemark.locality].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}

public extension MKCoordinateRegion {
    /// Where the map opens before the device has a fix.
    ///
    /// Was Maricopa County, which is now simply one covered place among several — opening a
    /// Boston user onto Phoenix reads as a bug. The camera moves to the device as soon as a
    /// fix arrives; this is only what is behind it in the meantime.
    static var continentalUS: MKCoordinateRegion {
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 39.5, longitude: -98.35),
            span: MKCoordinateSpan(latitudeDelta: 30, longitudeDelta: 45)
        )
    }
}
