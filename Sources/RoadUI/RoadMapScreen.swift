import SwiftUI
import MapKit
import CoreLocation
import RoadCore
import RoadSources
import RoadStore
#if os(iOS)
import UIKit
#endif

/// Drop a pin or search an address; the pipeline identifies the segment under it.
public struct RoadMapScreen: View {
    @State private var model: RoadLookupModel
    @State private var location = LocationProvider()
    @State private var parcels = ParcelOverlayModel()
    @State private var camera: MapCameraPosition = .region(.continentalUS)
    /// The map's current viewport, tracked so the crosshair knows what it is aiming at and
    /// the zoom buttons know what to scale.
    @State private var region: MKCoordinateRegion = .continentalUS
    @State private var style: MapStyleChoice = .standard
    @State private var sheet: MapSheet?
    @State private var locationNotice: String?
    /// The camera is tracking the device. Panning breaks it; the recentre button restores it.
    @State private var isFollowing = false
    /// The zoom the follow camera uses. Seeded from `followDistanceMeters` and then owned by
    /// the user: pinching while following changes this rather than breaking the follow.
    @State private var followDistance = RoadMapScreen.followDistanceMeters
    /// When `follow()` last moved the camera, so its own animation is not read as a pan.
    @State private var lastProgrammaticMove: Date?
    /// The camera has been placed on the device at least once, so a zoom now means "while
    /// following" rather than "while looking around before a fix arrived".
    @State private var hasFollowedOnce = false
    /// When the user last changed the zoom themselves, so a recentre does not fight a pinch
    /// that is still in progress.
    @State private var lastUserZoom: Date?
    /// Persisted, because a driver who chose Night should not have to choose it again next
    /// trip. The project had no persistence at all before this.
    @AppStorage("driveAppearance") private var appearance: DriveAppearance = .auto
    /// Whether the driving notice has been shown. Drive mode starts on its own at road speed,
    /// so this is the one moment the app asks the user anything — see `DriveSafetyNotice`.
    @AppStorage("didAcknowledgeDriveSafety") private var didAcknowledgeDriveSafety = false
    /// Set when the notice was declined, so drive mode stays off for the rest of the session
    /// without nagging at every fix.
    @State private var declinedDriveThisSession = false
    /// Derived from `appearance` and the sun. Held rather than recomputed inline so `auto` can
    /// apply hysteresis across dusk.
    @State private var isNight = false
    @State private var driveActivity = DriveActivityController()
    /// Where the reticle actually points, converted from its screen position rather than
    /// inferred from the camera's bounding region. Nil only before the first layout pass.
    @State private var aimCoordinate: CLLocationCoordinate2D?
    @Environment(\.scenePhase) private var scenePhase
    @State private var previousRegion: MKCoordinateRegion?
    @State private var tappedParcel: ParcelReference?
    @State private var loadingParcel = false

    public init(model: RoadLookupModel = RoadLookupModel()) {
        _model = State(initialValue: model)
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                // The map and the reticle must share one frame. The map ignores the bottom
                // safe area, so a reticle laid out in the safe area would sit ~17pt above the
                // camera centre — and would mark a different spot than the one identified.
                ZStack {
                    map
                    crosshair
                }
                .ignoresSafeArea(edges: .bottom)

                VStack(spacing: 0) {
                    overlay
                    Spacer()
                    HStack(alignment: .bottom) {
                        MapScaleBar(span: region.mapSpan, latitude: region.center.latitude)
                            .padding(.leading, 14)
                        Spacer()
                        mapControls
                    }
                }
            }
            .navigationTitle("Who built this road?")
            .inlineNavigationTitle()
            .toolbar { toolbar }
            .searchable(text: $model.searchText, prompt: "Search an address")
            .onSubmit(of: .search) { Task { await model.search() } }
            .task {
                // Default behaviour: find the device, follow it, and keep naming the road
                // under it. Aiming at the map is the fallback for when that is not possible.
                if SamplePin.fromLaunchArguments() == nil {
                    await startFollowing()
                }
                // Lets a launch argument drive the app to a known pin, for screenshots and
                // for checking the pipeline end to end without tapping a map.
                if let sample = SamplePin.fromLaunchArguments() {
                    model.drop(at: sample.coordinate)
                    camera = .region(zoomed(on: sample.coordinate))
                    if ProcessInfo.processInfo.arguments.contains("-report") {
                        // Wait for the pipeline before opening the report on it.
                        while model.phase != .resolved, !Task.isCancelled {
                            try? await Task.sleep(for: .milliseconds(100))
                        }
                        if let record = model.record { sheet = .report(record) }
                    }
                }
            }
            // One presenter. Three stacked `.sheet` modifiers on the same view is a
            // SwiftUI hazard — only one is honoured, so pressing "Full report" could open the
            // tapped-parcel sheet instead, which is its own way of showing parcel information
            // to somebody who asked about a road.
            .sheet(item: $sheet) { which in
                switch which {
                case .report(let record):
                    ResultScreen(record: record, placeName: model.placeName)
                case .sources:
                    if let record = model.record { SourceLog(record: record) }
                case .parcel(let apn):
                    ParcelDetailSheet(apn: apn, parcel: tappedParcel, isLoading: loadingParcel)
                case .driveLog:
                    DriveLogList(roads: model.driveLog) { model.clearDriveLog() }
                case .driveSafety:
                    DriveSafetyNotice(
                        onEnable: {
                            didAcknowledgeDriveSafety = true
                            sheet = nil
                            syncModeWithMotion()
                        },
                        onDecline: {
                            didAcknowledgeDriveSafety = true
                            declinedDriveThisSession = true
                            sheet = nil
                        })
                }
            }
        }
    }

    private var map: some View {
        MapReader { proxy in
            GeometryReader { geometry in
                mapContent
                    .onTapGesture { screenPoint in
                        guard let coordinate = proxy.convert(screenPoint, from: .local) else { return }
                        selectParcel(at: Coordinate(latitude: coordinate.latitude,
                                                    longitude: coordinate.longitude))
                    }
                    // Keeps the reticle's coordinate in step with the camera. Taps have always
                    // gone through `proxy.convert`; Identify used `region.center`, and the two
                    // are not the same point.
                    .onMapCameraChange(frequency: .onEnd) { _ in syncAim(proxy, geometry.size) }
                    .onAppear { syncAim(proxy, geometry.size) }
            }
        }
    }

    /// Converts the reticle's actual screen position into a coordinate.
    ///
    /// `region.center` is the centre of the *bounding region* of what the camera can see, and
    /// that is only the middle of the screen while the camera is looking straight down. Tilt it
    /// — the pitch toggle is right there in the map controls, and `elevation: .realistic` makes
    /// a two-finger drag do it too — and the visible area becomes a trapezoid running off to
    /// the horizon, whose bounding box is centred well beyond where the reticle is drawn. The
    /// app then identified a road the user was not pointing at, which is exactly the reported
    /// symptom: aiming at one street and getting its neighbour.
    ///
    /// Taps never had this bug because they already converted a real screen point. This makes
    /// Identify do the same thing.
    private func syncAim(_ proxy: MapProxy, _ size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        let reticle = CGPoint(x: size.width / 2, y: size.height / 2)
        aimCoordinate = proxy.convert(reticle, from: .local)
    }

    private var mapContent: some View {
        Map(position: $camera) {
            // The blue dot, once the user has allowed it.
            UserAnnotation()

            // Parcel boundaries. The reported parcel is drawn solid and labelled; the rest are
            // dashed, so it stays obvious that the reported one merely fronts the road rather
            // than being singled out by the data.
            let fronting = frontingOutlines
            ForEach(parcels.outlines) { outline in
                let isReported = fronting.contains(outline.apn)
                MapPolygon(coordinates: outline.rings[0].map(\.clLocation))
                    .foregroundStyle(isReported ? .blue.opacity(0.10) : .gray.opacity(0.04))
                    .stroke(isReported ? Color.blue : Color.secondary.opacity(0.7),
                            style: StrokeStyle(lineWidth: isReported ? 2.5 : 1,
                                               dash: isReported ? [] : [4, 4]))
            }
            if let reported = reportedOutline, let anchor = reported.labelAnchor {
                Annotation(reported.apn, coordinate: anchor.clLocation) { EmptyView() }
                    .annotationTitles(.visible)
            }
            if let pin = model.pin, !model.isDriving {
                Annotation("", coordinate: pin) {
                    Image(systemName: "mappin.circle.fill")
                        .font(.title)
                        .foregroundStyle(.red, .white)
                        .accessibilityLabel("Identified location")
                }
            }
        }
        // Stripped back while driving: no terrain shading, no points of interest, muted
        // labels. Glare and clutter at speed, and cheaper on a hot phone.
        .mapStyle(style.mapStyle(reduced: model.isDriving))
        // One modifier removes the title, the search field and the ⋯ menu — none of which is
        // for driving, and the menu's sample pins each drop a pin and fly the camera off the
        // car. Toggling `.searchable` itself would change the NavigationStack's identity.
        #if os(iOS)
        .toolbar(model.isDriving ? .hidden : .visible, for: .navigationBar)
        #endif
        .mapControlVisibility(model.isDriving ? .hidden : .visible)
        .preferredColorScheme(isNight ? .dark : nil)
        .task {
            // The coordinate barely changes on a long straight road, so dusk needs a clock as
            // well as a fix to arrive.
            while !Task.isCancelled {
                refreshAppearance()
                try? await Task.sleep(for: .seconds(300))
            }
        }
        .onChange(of: appearance) { _, _ in refreshAppearance() }
        // A crash or a force-quit can leave one running; without this the lock screen shows a
        // road from a previous drive.
        .task { driveActivity.endStrayActivities() }
        .onChange(of: model.driveCard) { _, card in
            guard model.isDriving, card.roadName != nil else { return }
            let state = DriveActivityState(card: card)
            if driveActivity.isAvailable {
                driveActivity.start(state, foreground: scenePhase == .active)
                driveActivity.update(state)
            }
        }
        .onChange(of: model.isDriving) { _, driving in
            if !driving { driveActivity.end() }
        }
        .onChange(of: scenePhase) { _, phase in
            // `Activity.request` throws from the background, and drive mode often begins there.
            if phase == .active { driveActivity.resumePendingStart() }
        }
        .mapControls {
            MapCompass()
            MapPitchToggle()
        }
        // (Visibility is set above: hidden while driving, visible otherwise. Left adaptive,
        // these appear only mid-gesture and effectively are not there.)
        // Aiming replaces tapping. Every stray tap used to drop a pin and start six network
        // requests, which on a phone in the field is the difference between a tool and a
        // nuisance. Now nothing is looked up until the Identify button is pressed.
        // Continuous, and deliberately separate from the `.onEnd` handler below. Zoom has to
        // be adopted *while* the gesture is happening: the settle window that protects the
        // pan classification is always open while driving, so anything waiting on it never
        // ran. This looks only at distance, which the app always sets to exactly
        // `followDistance` — so a different value can only be the user's.
        .onMapCameraChange(frequency: .continuous) { context in
            guard isFollowing, hasFollowedOnce else { return }
            guard Geo.userChangedZoom(observed: context.camera.distance,
                                      expected: followDistance) else { return }
            followDistance = Geo.clampFollowDistance(context.camera.distance)
            lastUserZoom = Date()
        }
        .onMapCameraChange(frequency: .onEnd) { context in
            region = context.region
            // Address search follows the viewport, so "Main St" finds the one on screen
            // rather than one in a state the user last looked at.
            model.searchRegion = context.region
            // Only the counties whose profile claims parcels; elsewhere the overlay stays
            // dark rather than firing Maricopa assessor requests on every pan.
            // Off while driving: the outlines are near-invisible at speed and on a dark
            // basemap, and drawing them spends assessor requests on every camera settle.
            parcels.isAvailable = model.parcelsAvailable && !model.isDriving
            // `.onEnd` fires when panning stops, which is the debounce for this.
            parcels.update(for: context.region)
            // Classify who moved the camera. The previous rule compared the centre's drift
            // from the device against 35% of the span — 226 m at the follow zoom — so panning
            // to aim at a nearby road did not end the follow, and the next GPS fix snapped the
            // camera back. Identify then resolved the device's position instead of the road
            // under the crosshair, which is how aiming produced parcel data.
            let newCentre = Coordinate(latitude: context.region.center.latitude,
                                       longitude: context.region.center.longitude)
            let previousCentre = previousRegion.map {
                Coordinate(latitude: $0.center.latitude, longitude: $0.center.longitude)
            } ?? newCentre
            let settling = lastProgrammaticMove.map {
                Date().timeIntervalSince($0) < Geo.programmaticSettleWindow
            } ?? false
            if !settling {
                switch Geo.classifyCameraChange(from: previousRegion?.mapSpan ?? context.region.mapSpan,
                                                previousCentre: previousCentre,
                                                to: context.region.mapSpan,
                                                currentCentre: newCentre) {
                case .panned:
                    isFollowing = false
                case .zoomed:
                    // Only while genuinely following the device. A zoom performed before the
                    // first fix is just looking around, and adopting the county-overview
                    // distance strands the follow camera hundreds of kilometres up. Clamped
                    // regardless, so no single bad value can do that again.
                    if isFollowing, hasFollowedOnce {
                        followDistance = Geo.clampFollowDistance(context.camera.distance)
                    }
                case .negligible:
                    break
                }
            }
            previousRegion = context.region
        }
    }

    private var reportedOutline: ParcelOutline? {
        guard let apn = model.record?.parcel?.value.apn else { return nil }
        return parcels.outlines.first { $0.apn == apn }
    }

    /// The lots facing the pin, all of which are drawn solid.
    ///
    /// Was just the one APN the parcel source reports. Standing in a street you are looking at
    /// the lots on both sides of it, and highlighting one while dashing its neighbour implied a
    /// distinction the data does not make. The reported lot is always included, even if the pin
    /// sits far enough inside it to fall outside the fronting radius.
    private var frontingOutlines: Set<String> {
        guard let pin = model.pin else { return [] }
        let point = Coordinate(latitude: pin.latitude, longitude: pin.longitude)
        var apns = Set(ParcelOutline.fronting(parcels.outlines, at: point).map(\.apn))
        if let reported = model.record?.parcel?.value.apn { apns.insert(reported) }
        return apns
    }

    /// A fixed reticle at the centre of the map. Shown only while aiming: once a result card
    /// is up it would sit behind it, and the aiming is already done.
    ///
    /// Never while driving. Aiming has no meaning at speed, and the guard used to be on `phase`
    /// alone — so every background refresh flashed a red target over the blue dot.
    @ViewBuilder
    private var crosshair: some View {
        if model.phase != .resolved && !model.isDriving {
            ZStack {
                Circle()
                    .strokeBorder(.white.opacity(0.9), lineWidth: 3)
                    .frame(width: 30, height: 30)
                Circle()
                    .strokeBorder(.red, lineWidth: 1.5)
                    .frame(width: 30, height: 30)
                Circle()
                    .fill(.red)
                    .frame(width: 4, height: 4)
            }
            .shadow(radius: 2)
            .allowsHitTesting(false)
            .accessibilityLabel("Map centre \u{2014} press Identify this road to look it up here")
        }
    }

    /// Trailing-edge stack. The MapKit compass, scale and pitch controls place themselves.
    private var mapControls: some View {
        VStack(spacing: 10) {
            Menu {
                Picker("Map style", selection: $style) {
                    ForEach(MapStyleChoice.allCases) { choice in
                        Label(choice.name, systemImage: choice.symbol).tag(choice)
                    }
                }
                .pickerStyle(.inline)
                // Same menu rather than a sixth control on the map. Auto follows the sun at
                // the device's own position, which is the only signal that is right at 9 pm
                // for a driver who leaves iOS on Light.
                Section("Appearance") {
                    Picker("Appearance", selection: $appearance) {
                        ForEach(DriveAppearance.allCases) { choice in
                            Label(choice.name, systemImage: choice.symbol).tag(choice)
                        }
                    }
                    .pickerStyle(.inline)
                }
            } label: {
                controlFace(style.symbol)
            }
            .accessibilityLabel("Map style")

            Button { zoom(by: 0.5) } label: { controlFace("plus") }
                .disabled(!Geo.canZoomIn(region.mapSpan))
                .accessibilityLabel("Zoom in")

            Button { zoom(by: 2.0) } label: { controlFace("minus") }
                .disabled(!Geo.canZoomOut(region.mapSpan))
                .accessibilityLabel("Zoom out")

            Button { toggleDriving() } label: {
                controlFace(model.isDriving ? "car.fill" : "car")
                    .foregroundStyle(model.isDriving ? Color.accentColor : .primary)
            }
            .accessibilityLabel(model.isDriving ? "Stop drive mode" : "Identify roads as I drive")

            Button { toggleFollow() } label: {
                if location.isLocating {
                    ProgressView().frame(width: 44, height: 44)
                        .background(.background.secondary, in: Circle())
                } else {
                    controlFace(isFollowing ? "location.fill" : "location")
                        .foregroundStyle(isFollowing ? Color.accentColor : .primary)
                }
            }
            .disabled(location.isLocating)
            .accessibilityLabel("Follow my location")
            .accessibilityValue(isFollowing ? "On" : "Off")
            .accessibilityAddTraits(isFollowing ? [.isSelected] : [])
        }
        .buttonStyle(.plain)
        .padding(.trailing, 12)
    }

    private func controlFace(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 16, weight: .semibold))
            .frame(width: 44, height: 44)
            .background(.background.secondary, in: Circle())
            .shadow(radius: 1, y: 1)
    }

    /// The zoom buttons, which must never end the follow.
    ///
    /// They used to. Two things were wrong. The move was not recorded as the app's own, so the
    /// camera change that followed was classified as a user gesture — and it re-centred on
    /// `region.center`, a value captured before the car had moved on, so the centre drift
    /// cleared the 12 m pan threshold and switched following off. Zooming out to see where you
    /// were going therefore dropped you off the car.
    ///
    /// While following, a zoom is a change of *follow distance*, not a change of where the
    /// camera is pointed. Re-issuing a `MapCamera` on the device also preserves the heading,
    /// which `.region` discards — a button press used to snap a heading-up map back to north.
    private func zoom(by factor: Double) {
        lastProgrammaticMove = Date()

        if isFollowing, let fix = location.currentFix {
            followDistance = Geo.clampFollowDistance(followDistance * factor)
            withAnimation {
                camera = .camera(MapCamera(centerCoordinate: fix,
                                           distance: followDistance,
                                           heading: location.currentCourse ?? 0,
                                           pitch: 0))
            }
            return
        }

        let scaled = Geo.scaledSpan(region.mapSpan, by: factor)
        let next = MKCoordinateRegion(center: region.center, span: scaled.coordinateSpan)
        region = next
        withAnimation { camera = .region(next) }
    }

    /// Opens the parcel whose boundary was tapped, if any.
    ///
    /// The hit test runs against the outlines already on screen rather than asking the server
    /// what is at this point — the app is looking at those polygons, so it can answer itself.
    /// Only the details, which the overlay does not carry, need fetching.
    private func selectParcel(at coordinate: Coordinate) {
        guard let outline = parcels.outlines.first(where: { $0.contains(coordinate) }) else { return }
        tappedParcel = nil
        loadingParcel = true
        sheet = .parcel(outline.apn)
        Task {
            tappedParcel = await MaricopaParcelSource().parcel(forAPN: outline.apn)
            loadingParcel = false
        }
    }


    private func identifyCentre() {
        model.drop(at: aimCoordinate ?? region.center)
    }

    /// Follow the device and keep naming the road under it.
    ///
    /// `.userLocation(followsHeading:)` tracks natively and rotates the map the way the car is
    /// pointing, which is both smoother and better oriented than pushing a fresh region on
    /// every fix.
    private func startFollowing() async {
        locationNotice = nil
        keepScreenAwake(true)
        guard await location.startStreaming() else {
            keepScreenAwake(false)
            // No location: fall back to the county view and the aim-and-identify flow, and
            // say why rather than sitting on an empty map.
            locationNotice = {
                if case .unavailable(let reason) = location.availability { return reason }
                return "Without location access, pan the map and press Identify this road."
            }()
            return
        }
        isFollowing = true
        model.setDriving(location.motion == .driving)
        location.onFix = { coordinate in
            Task { @MainActor in
                // Following is about the camera and happens whether or not the car is moving:
                // a parked phone should still be centred on itself. Motion only decides
                // whether the app keeps *re-identifying*.
                follow(coordinate)
                syncModeWithMotion()
                await model.handleDrivingFix(coordinate)
            }
        }
        // Name the road under the device immediately rather than waiting for the car to move
        // 25 m, which never happens if the app is opened while parked.
        var fix = location.currentFix
        if fix == nil { fix = await location.requestFix() }
        guard let fix else { return }
        follow(fix)
        // Name the road under the device once on opening, even parked. After this, a new
        // answer only comes while actually driving.
        await model.identifyOnce(at: fix)
    }

    private func stopFollowing() {
        model.setDriving(false)
        location.stopStreaming()
        location.onFix = nil
        isFollowing = false
        keepScreenAwake(false)
        driveActivity.end()
    }

    /// Stops iOS sleeping the screen while the car is moving.
    ///
    /// A dash-mounted phone otherwise goes dark on the normal idle timer and the driver has to
    /// wake it by hand to see anything. Background location keeps the lookups running either
    /// way — this is purely about the map still being there when you glance at it.
    ///
    /// Always paired with a `false`: left set, it flattens the battery of a phone the user
    /// walked away from. iOS also clears it when the app backgrounds, so it cannot strand the
    /// screen on, but the explicit clear keeps the intent visible rather than relying on that.
    /// Re-derives the night flag from the setting, the device's position and the time.
    private func refreshAppearance() {
        let here = location.currentFix.map {
            Coordinate(latitude: $0.latitude, longitude: $0.longitude)
        } ?? Coordinate(latitude: region.center.latitude, longitude: region.center.longitude)
        isNight = appearance.isNight(at: here, wasNight: isNight)
    }

    private func keepScreenAwake(_ on: Bool) {
        // Guarded because the package is built and tested on macOS, where there is no
        // UIApplication and no idle timer to disable.
        #if canImport(UIKit)
        UIApplication.shared.isIdleTimerDisabled = on
        #endif
    }

    private func toggleDriving() {
        if model.isDriving {
            stopFollowing()
        } else {
            Task { await startFollowing() }
        }
    }

    /// Put the camera on the device at street level.
    ///
    /// Set explicitly rather than via `.userLocation(followsHeading:)`: that position resolves
    /// to its fallback until MapKit has its own fix, which on launch left the map sitting at
    /// the county overview even though the app already had a location and had identified the
    /// road. Driving the camera means the zoom is ours and it happens on the first fix.
    private func follow(_ coordinate: CLLocationCoordinate2D) {
        guard isFollowing else { return }
        // A pinch emits a stream of camera changes, and recentring in the middle of one drags
        // the map back under the user's fingers — which is what "it keeps zooming into the
        // device when I zoom out" was. Each change refreshes the window, so the app waits
        // until the gesture is over.
        if let lastUserZoom, Date().timeIntervalSince(lastUserZoom) < Geo.userZoomGraceWindow {
            return
        }
        lastProgrammaticMove = Date()
        hasFollowedOnce = true
        withAnimation(.easeInOut(duration: 0.4)) {
            camera = .camera(MapCamera(centerCoordinate: coordinate,
                                       distance: followDistance,
                                       heading: location.currentCourse ?? 0,
                                       pitch: 0))
        }
    }

    /// Close enough to read the street you are on, and inside the parcel overlay's zoom gate.
    static let followDistanceMeters: Double = 420

    /// The location control is a toggle, not a one-shot recentre: on means the camera stays
    /// on the device, off means it stays where you left it.
    private func toggleFollow() {
        if isFollowing {
            isFollowing = false
            return
        }
        isFollowing = true
        locationNotice = nil
        Task {
            var fix = location.currentFix
            if fix == nil { fix = await location.requestFix() }
            guard let fix else {
                isFollowing = false
                locationNotice = {
                    if case .unavailable(let reason) = location.availability { return reason }
                    return "Could not get a location fix. Try again with a clearer view of the sky."
                }()
                return
            }
            follow(fix)
            // Toggling on with nothing on screen should also answer the question the app
            // exists for, rather than just moving the map.
            if model.record == nil { await model.identifyOnce(at: fix) }
        }
    }

    /// Follow and identify whenever the device is actually moving, and stop when it is not.
    ///
    /// The app streams location the whole time it is open — that is the only way to notice
    /// driving has started — but while stationary it holds the last answer, leaves the camera
    /// alone, and asks nobody anything.
    private func syncModeWithMotion() {
        let driving = location.motion == .driving
        guard driving != model.isDriving else { return }
        // The first time the phone is moving at road speed, say what drive mode is before
        // doing it. Taking over the screen of someone who never asked — and who may be the
        // one steering — is the one thing in this app that warrants an interruption.
        if driving, !didAcknowledgeDriveSafety {
            if sheet == nil { sheet = .driveSafety }
            return
        }
        if driving, declinedDriveThisSession { return }
        model.setDriving(driving)
        // Starting to drive implies wanting the map on the car.
        if driving, !isFollowing, let fix = location.currentFix {
            isFollowing = true
            follow(fix)
        }
    }

    @ViewBuilder
    private var overlay: some View {
        VStack(spacing: 10) {
            if let failure = model.searchFailure {
                Banner(text: failure, icon: "magnifyingglass")
            }
            if let locationNotice {
                LocationNotice(text: locationNotice,
                               showsSettings: location.availability.isDenied) {
                    self.locationNotice = nil
                }
            }
            if model.isDriving {
                // Aiming has no meaning while moving, so the whole aim-and-identify UI is
                // replaced rather than stacked on top of.
                DriveSummary(record: model.record,
                             isResolving: model.phase == .resolving,
                             logCount: model.driveLog.count,
                             isRefreshing: model.isRefreshing,
                             palette: isNight ? .night : .day,
                             onOpenLog: { sheet = .driveLog },
                             onOpenDetail: {
                                 // Snapshotted here, so driving on does not rewrite the screen.
                                 if let record = model.record { sheet = .report(record) }
                             },
                             sticky: model.driveCard)
            } else {
                switch model.phase {
                case .idle:
                    identifyButton
                case .resolving:
                    Banner(text: "Identifying the segment\u{2026}",
                           icon: "antenna.radiowaves.left.and.right")
                case .resolved:
                    if let record = model.record { resolvedCard(record) }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
    }

    @ViewBuilder
    private func resolvedCard(_ record: RoadRecord) -> some View {
        // Pinned above the card rather than inside it: the card scrolls, and a dismiss control
        // that scrolls out of reach is worse than none.
        HStack(spacing: 10) {
            // Leading, not trailing: the map control stack runs down the right edge, and a
            // close button directly under the locate button reads as a fifth control rather
            // than a way out of the card.
            Button {
                withAnimation(.easeOut(duration: 0.2)) { model.clear() }
            } label: {
                Image(systemName: "xmark")
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 40, height: 40)
                    .background(.background.secondary, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close road information")

            Button { sheet = .report(record) } label: {
                Label("Full report", systemImage: "doc.text.magnifyingglass")
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background(.background.secondary, in: Capsule())
            }
            .buttonStyle(.plain)
        }

        // Clipped to the card's own shape so a long answer reads as a scrollable panel rather
        // than text running off the bottom of the screen.
        ScrollView {
            SegmentCard(record: record, placeName: model.placeName)
                .padding(.bottom, 4)
        }
        .frame(maxHeight: 400)
        .scrollIndicators(.visible)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        // Fade the last few points so a clipped line reads as "more below".
        .mask(
            LinearGradient(stops: [.init(color: .black, location: 0),
                                   .init(color: .black, location: 0.94),
                                   .init(color: .clear, location: 1)],
                           startPoint: .top, endPoint: .bottom)
        )
    }

    /// The only thing that starts a lookup, so it is deliberate and it is obvious.
    private var identifyButton: some View {
        Button { identifyCentre() } label: {
            Label("Identify this road", systemImage: "scope")
                .font(.headline)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity)
                .background(.tint, in: Capsule())
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                // A development affordance: driving the pipeline to a known answer without
                // hunting for a coordinate on the map. Safe to delete.
                #if DEBUG
                ForEach(SamplePin.all) { sample in
                    Button(sample.name) {
                        model.drop(at: sample.coordinate)
                        withAnimation { camera = .region(zoomed(on: sample.coordinate)) }
                    }
                }
                #endif
                Button("This drive\u{2026}", systemImage: "car") { sheet = .driveLog }
                if model.record != nil {
                    Divider()
                    Button("Source log\u{2026}", systemImage: "list.bullet.rectangle") {
                        sheet = .sources
                    }
                    Button("Clear pin", systemImage: "xmark.circle", role: .destructive) {
                        model.clear()
                    }
                }
                // The app has no settings or about screen, so this menu is the only route to
                // them from inside the app. It is hidden while driving, which is why the
                // driving notice carries its own copy of these links.
                Divider()
                Link(destination: URL(string: "https://hoobiltit.com/terms")!) {
                    Label("Terms of Use", systemImage: "doc.text")
                }
                Link(destination: URL(string: "https://hoobiltit.com/privacy")!) {
                    Label("Privacy", systemImage: "hand.raised")
                }
            } label: {
                Label("Examples", systemImage: "ellipsis.circle")
            }
        }
    }

    private func zoomed(on coordinate: CLLocationCoordinate2D) -> MKCoordinateRegion {
        // Inside Geo.parcelOverlayMaxSpanDegrees, so parcel boundaries are on screen at the
        // zoom the app actually lands on after identifying. About 450 m across.
        MKCoordinateRegion(center: coordinate,
                           span: MKCoordinateSpan(latitudeDelta: 0.004, longitudeDelta: 0.004))
    }
}

private struct Banner: View {
    let text: String
    let icon: String

    var body: some View {
        Label(text, systemImage: icon)
            .font(.subheadline)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.secondary, in: Capsule())
    }
}

/// What every source did, including the ones that found nothing. Partial answers are the
/// normal case, so the app can explain which sources were asked and what each said.

extension View {
    /// The app ships for iOS; the package still builds for macOS so the resolver tests can
    /// run without a simulator, and this modifier does not exist there.
    func inlineNavigationTitle() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
}

/// Coordinates from docs/ENDPOINTS.md §8, each reaching a different path through the pipeline.
struct SamplePin: Identifiable {
    let name: String
    let coordinate: CLLocationCoordinate2D
    var id: String { name }

    /// `-pin williams` on the command line, matched on the leading word of the name.
    static func fromLaunchArguments() -> SamplePin? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flag = arguments.firstIndex(of: "-pin"), arguments.indices.contains(flag + 1)
        else { return nil }
        let wanted = arguments[flag + 1].lowercased()
        return all.first { $0.name.lowercased().replacingOccurrences(of: " ", with: "").hasPrefix(wanted) }
    }

    static let all: [SamplePin] = [
        .init(name: "Williams Dr \u{2014} county + project",
              coordinate: .init(latitude: 33.689441, longitude: -112.317668)),
        .init(name: "I-10 \u{2014} state route",
              coordinate: .init(latitude: 33.4602, longitude: -112.3756)),
        .init(name: "Lone Mountain Rd \u{2014} unincorporated",
              coordinate: .init(latitude: 33.767648, longitude: -112.528617)),
        .init(name: "Goodyear \u{2014} city-maintained",
              coordinate: .init(latitude: 33.4386, longitude: -112.4118)),
        .init(name: "Sun City \u{2014} subdivision plat",
              coordinate: .init(latitude: 33.5988, longitude: -112.2749)),
        .init(name: "MC 85 \u{2014} numeric road name",
              coordinate: .init(latitude: 33.393854, longitude: -112.444779)),
        .init(name: "McDowell Rd \u{2014} point-located project",
              coordinate: .init(latitude: 33.466228, longitude: -111.667181)),
    ]
}

/// Explains why the locate button did nothing, and offers the one action that fixes it.
private struct LocationNotice: View {
    let text: String
    let showsSettings: Bool
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "location.slash")
            VStack(alignment: .leading, spacing: 6) {
                Text(text).font(.subheadline)
                if showsSettings {
                    Button("Open Settings") { openSettings() }
                        .font(.subheadline.weight(.medium))
                }
            }
            Spacer(minLength: 0)
            Button { dismiss() } label: { Image(systemName: "xmark") }
                .accessibilityLabel("Dismiss")
        }
        .padding(14)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
    }

    private func openSettings() {
        #if os(iOS)
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
        #endif
    }
}

extension LocationProvider.Availability {
    var isDenied: Bool {
        if case .unavailable = self { return true }
        return false
    }
}


/// Wraps an APN so it can drive a `sheet(item:)`.


/// Which sheet the map screen is presenting. One presenter avoids SwiftUI's stacked-`.sheet`
/// ambiguity, and makes adding a fourth safe.
enum MapSheet: Identifiable {
    /// Carries the record rather than reading `model.record` when it presents.
    ///
    /// Drive mode refreshes about every 250 m, so a live read rewrote the screen underneath a
    /// reader who had asked about one specific road. A `RoadRecord` is a value, so this is a
    /// snapshot: the report stays on the road it was opened for, and the card behind it goes on
    /// updating.
    case report(RoadRecord)
    case sources
    case parcel(String)
    /// The roads identified on this drive.
    case driveLog
    /// Shown once, the first time the phone is moving at road speed.
    case driveSafety

    var id: String {
        switch self {
        // Keyed on the pin, so re-opening on a different road presents afresh.
        case .report(let record):
            "report-\(record.query.coordinate.latitude),\(record.query.coordinate.longitude)"
        case .sources: "sources"
        case .parcel(let apn): "parcel-\(apn)"
        case .driveLog: "driveLog"
        case .driveSafety: "driveSafety"
        }
    }
}
