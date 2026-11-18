import SwiftUI
import MapKit
import CoreLocation
import SeichiCore

/// 用户想做的事：拍下同一幕，或者请人帮自己拍
enum JourneyPurpose: String, Codable {
    case scene, photographer
}

struct Journey: Identifiable, Equatable {
    let spot: Spot
    let purpose: JourneyPurpose
    var id: String { spot.id + "|" + purpose.rawValue }
}

/// “带我去复现 / 请人帮我拍”的全程：
/// 1. 远（> 400 m）：出发页，一键用常用的地图 App 导航过去，快到了发通知叫你回来；
/// 2. 近（40–400 m）：实时指南针 + 步行小地图；
/// 3. 到了（机位半径内）：相机取景（复现）或交给拍照的人（帮拍）。
struct JourneyView: View {
    let journey: Journey
    @Environment(LocationService.self) private var location
    @Environment(\.dismiss) private var dismiss
    @State private var stage: JourneyStage?
    @State private var haptics = Haptics()

    private var spot: Spot { journey.spot }
    private var distance: Double? {
        location.lastLocation.map { GeoMath.distance(from: $0.geoPoint, to: spot.coordinate) }
    }

    /// 第一次渲染时就按当前距离选好页面，避免先闪一下出发页
    private var initialStage: JourneyStage {
        distance.map { JourneyStage.next(from: nil, distance: $0, arrivalRadius: spot.arrivalRadius) } ?? .far
    }

    var body: some View {
        Group {
            switch stage ?? initialStage {
            case .far:
                DepartureView(journey: journey, distance: distance)
            case .near:
                NearApproachView(spot: spot, distance: distance)
            case .arrived:
                switch journey.purpose {
                case .scene: SceneModeView(spot: spot)
                case .photographer: PhotographerModeView(spot: spot)
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: stage)
        .onAppear { updateStage() }
        .onChange(of: location.lastLocation) { _, _ in updateStage() }
        .onChange(of: stage) { old, new in
            if new == .arrived, old != nil { haptics.success() }
            if new != .far { location.disarmJourney() }
        }
    }

    private func updateStage() {
        guard let d = distance else { return }
        let next = JourneyStage.next(from: stage, distance: d, arrivalRadius: spot.arrivalRadius)
        if next != stage { stage = next }
    }
}

// MARK: - 远：出发页

private struct DepartureView: View {
    let journey: Journey
    let distance: Double?
    @Environment(LocationService.self) private var location
    @Environment(\.dismiss) private var dismiss
    @State private var choosing = false
    @State private var armed = false
    @State private var preferred: MapApp? = MapApp.preferred

    private var spot: Spot { journey.spot }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Map(initialPosition: .automatic, interactionModes: [.pan, .zoom]) {
                        UserAnnotation()
                        Marker(spot.sceneTitle, systemImage: "camera.fill", coordinate: spot.clCoordinate)
                            .tint(spot.tintColor)
                    }
                    .mapStyle(.standard(pointsOfInterest: .excludingAll))
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(spot.badgeWithNumber).font(.subheadline.bold()).foregroundStyle(spot.tintColor)
                        Text(spot.sceneTitle).font(.title2.bold())
                        if let d = distance {
                            Text(L("journey.farDistance", NearbySearch.formatDistance(d)))
                                .font(.callout).foregroundStyle(.secondary)
                        }
                        if let access = spot.access {
                            Label(access, systemImage: "tram.fill")
                                .font(.callout)
                                .padding(.top, 6)
                        }
                    }

                    Button(action: navigate) {
                        Label(preferred.map { L("journey.navigateWith", $0.name) } ?? L("journey.navigate"),
                              systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 36)
                    }
                    .glassButton(prominent: true, tint: spot.tintColor)
                    .controlSize(.large)
                    .accessibilityIdentifier("journeyNavigate")

                    if preferred != nil {
                        Button(L("journey.changeMapApp")) { choosing = true }
                            .font(.footnote.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }

                    reminderCard

                    Text(L(journey.purpose == .scene ? "journey.howItWorksScene" : "journey.howItWorksPhotographer"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
            .navigationTitle(L(journey.purpose == .scene ? "detail.startGuide" : "detail.photographer"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("common.close")) { dismiss() }.accessibilityIdentifier("closeJourney")
                }
            }
            .confirmationDialog(L("detail.chooseMapApp"), isPresented: $choosing, titleVisibility: .visible) {
                ForEach(MapApp.ordered) { app in
                    Button(app.isInstalled ? app.name : L("mapApp.web", app.name)) {
                        MapApp.preferred = app
                        preferred = app
                        open(app)
                    }
                }
                Button(L("common.cancel"), role: .cancel) {}
            } message: {
                Text(L("journey.chooseHint"))
            }
        }
    }

    /// 快到了提醒：需要“始终允许”定位才能在用户切到地图 App 时收到
    @ViewBuilder private var reminderCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: armed ? "bell.badge.fill" : "bell")
                .font(.title3)
                .foregroundStyle(spot.tintColor)
            VStack(alignment: .leading, spacing: 6) {
                Text(armed ? L("journey.reminderOn") : L("journey.reminderTitle")).font(.subheadline.bold())
                Text(L("journey.reminderBody", Int(JourneyStage.nearEnter))).font(.caption).foregroundStyle(.secondary)
                if !armed {
                    Button(L("journey.reminderEnable")) { enableReminder() }
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(spot.tintColor)
                        .accessibilityIdentifier("journeyReminder")
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onAppear { armed = location.armJourney(spot: spot, purpose: journey.purpose) }
        .onChange(of: location.authorization) { _, _ in
            armed = location.armJourney(spot: spot, purpose: journey.purpose)
        }
    }

    private func enableReminder() {
        if location.authorization == .authorizedAlways {
            armed = location.armJourney(spot: spot, purpose: journey.purpose)
        } else if location.authorization == .authorizedWhenInUse {
            location.requestAlwaysAuthorization()
        } else if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    private func navigate() {
        if let app = preferred { open(app) } else { choosing = true }
    }

    private func open(_ app: MapApp) {
        let walking = distance.map(JourneyStage.prefersWalking) ?? false
        app.openDirections(to: spot, walking: walking)
    }
}

// MARK: - 近：指南针 + 步行小地图

private struct NearApproachView: View {
    let spot: Spot
    let distance: Double?
    @Environment(LocationService.self) private var location
    @Environment(\.dismiss) private var dismiss
    @State private var route: MKRoute?
    @State private var routeOrigin: GeoPoint?

    private var bearing: Double? {
        location.lastLocation.map { GeoMath.bearing(from: $0.geoPoint, to: spot.coordinate) }
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.headline)
                        .frame(width: 44, height: 44)
                        .background(.black.opacity(0.45), in: Circle())
                }
                .accessibilityIdentifier("closeJourney")
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text(spot.badgeWithNumber).font(.caption.bold())
                    Text(spot.sceneTitle).font(.subheadline.bold())
                }
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(.black.opacity(0.45), in: Capsule())
            }
            .padding(.horizontal)

            compass

            if let d = distance {
                VStack(spacing: 4) {
                    Text(NearbySearch.formatDistance(d))
                        .font(.system(size: 44, weight: .bold, design: .rounded).monospacedDigit())
                        .contentTransition(.numericText())
                    Text(directionText).font(.title3.weight(.semibold))
                    Text(L("scene.walkCloser", Int(spot.arrivalRadius))).font(.footnote).opacity(0.75)
                }
                .multilineTextAlignment(.center)
            }

            Map(initialPosition: .userLocation(fallback: .automatic), interactionModes: [.pan, .zoom]) {
                UserAnnotation()
                if let route {
                    MapPolyline(route.polyline).stroke(spot.tintColor, lineWidth: 5)
                }
                Marker(spot.sceneTitle, systemImage: "camera.fill", coordinate: spot.clCoordinate)
                    .tint(spot.tintColor)
            }
            .mapStyle(.standard(pointsOfInterest: .excludingAll))
            .frame(maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .padding(.horizontal)
            .accessibilityIdentifier("nearMap")

            Button {
                (MapApp.preferred ?? .apple).openDirections(to: spot, walking: true)
            } label: {
                Label(L("journey.openInMaps"), systemImage: "map").font(.footnote.weight(.semibold))
            }
            .padding(.bottom, 8)
        }
        .padding(.top, 8)
        .foregroundStyle(.white)
        .background(LinearGradient(colors: [.black, spot.tintColor.opacity(0.7)], startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea())
        .environment(\.colorScheme, .dark)
        .task(id: routeKey) { await updateRoute() }
        .accessibilityIdentifier("nearApproach")
    }

    @ViewBuilder private var compass: some View {
        let heading = location.reliableHeading
        ZStack {
            Circle().fill(spot.tintColor.opacity(0.2)).frame(width: 150, height: 150)
            Circle().stroke(.white.opacity(0.25), lineWidth: 2).frame(width: 150, height: 150)
            if let b = bearing, let heading {
                Image(systemName: "location.north.fill")
                    .font(.system(size: 70))
                    .rotationEffect(.degrees(GeoMath.signedDelta(from: heading, to: b)))
                    .animation(.interactiveSpring(response: 0.3), value: heading)
                    .shadow(color: spot.tintColor, radius: 14)
            } else {
                Image(systemName: "location.north.circle").font(.system(size: 60)).opacity(0.6)
            }
        }
    }

    private var directionText: String {
        guard let b = bearing else { return L("scene.locating") }
        guard let h = location.reliableHeading else { return L("scene.spotDirection", Compass.name(b)) }
        return L("relative.go.\(RelativeDirection.of(bearing: b, heading: h).rawValue)")
    }

    /// 走动超过 40 m 才重新算路线
    private var routeKey: String {
        guard let p = location.lastLocation?.geoPoint else { return "" }
        if let o = routeOrigin, GeoMath.distance(from: o, to: p) < 40 { return "\(o.latitude),\(o.longitude)" }
        return "\(p.latitude),\(p.longitude)"
    }

    private func updateRoute() async {
        guard let p = location.lastLocation?.geoPoint else { return }
        if let o = routeOrigin, GeoMath.distance(from: o, to: p) < 40, route != nil { return }
        routeOrigin = p
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: p.latitude, longitude: p.longitude)))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: spot.clCoordinate))
        request.transportType = .walking
        route = try? await MKDirections(request: request).calculate().routes.first
    }
}
