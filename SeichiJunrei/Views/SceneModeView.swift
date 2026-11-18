import SwiftUI
import Combine
import UIKit
import QuartzCore
import SeichiCore

/// 全屏的“名场面模式”：
/// - 还没到达机位时：箭头指向圣地方向 + 距离
/// - 到达机位后：相机取景 + 名场面画框悬浮在真实方向上，引导用户转身/抬头，
///   对准后触发“你就是主角！”的庆祝效果。
struct SceneModeView: View {
    let spot: Spot

    @Environment(LocationService.self) private var location
    @Environment(StoreService.self) private var store
    @Environment(PilgrimageStore.self) private var pilgrimage
    @State private var showShare = false
    @State private var showCalibration = false
    @State private var showPaywall = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var systemColorScheme

    @State private var orientation = OrientationService()
    @State private var camera = CameraController()
    @State private var haptics = Haptics()
    @State private var latch = AlignmentLatch()
    @State private var celebrating = false
    @State private var showStory = false
    /// 定时评估对准状态：用户保持不动时朝向值不再变化，不能只依赖 onChange
    private let ticker = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    private var userPoint: GeoPoint? { location.lastLocation?.geoPoint }
    private var distance: Double? { userPoint.map { GeoMath.distance(from: $0, to: spot.coordinate) } }
    private var bearingToSpot: Double? { userPoint.map { GeoMath.bearing(from: $0, to: spot.coordinate) } }
    private var arrived: Bool {
        guard let d = distance else { return false }
        return d <= spot.arrivalRadius + min(max(location.lastLocation?.horizontalAccuracy ?? 0, 0), 20)
    }

    /// 是否可以使用取景模式（已购买，或仍有免费额度 / 已体验过这一处）
    private var canUseScene: Bool {
        store.allowance.canEnter(spot.id, entitlement: store.entitlement)
    }

    private var guidance: SceneGuidance? {
        guard let h = orientation.heading else { return nil }
        return SceneGuidance.compute(deviceHeading: h, devicePitch: orientation.pitch,
                                     sceneHeading: spot.sceneHeading, scenePitch: spot.scenePitch,
                                     headingAccuracy: orientation.accuracy)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                background
                if arrived && !canUseScene {
                    SceneLockedOverlay(tint: spot.tintColor) { showPaywall = true }
                } else if arrived {
                    alignmentLayer(size: geo.size)
                } else {
                    ApproachLayer(spot: spot, distance: distance, bearing: bearingToSpot,
                                  heading: orientation.heading)
                }
                if !celebrating { chrome }
                if celebrating {
                    CelebrationView(spot: spot, onCapture: { camera.capturePhoto() },
                                    onShare: { showShare = true },
                                    onClose: { withAnimation { celebrating = false } })
                        .transition(.opacity.combined(with: .scale(scale: 1.1)))
                }
            }
        }
        .ignoresSafeArea()
        .environment(\.colorScheme, .dark)   // 相机取景界面统一使用深色外观
        .statusBarHidden()
        .onAppear(perform: start)
        .onDisappear(perform: stop)
        .onReceive(ticker) { _ in tick() }
        .onChange(of: arrived) { _, isArrived in
            if isArrived { beginSceneIfAllowed(); haptics.success() }
        }
        .onChange(of: store.entitlement) { _, _ in
            // 在锁定页完成购买后，直接开始取景
            if arrived { beginSceneIfAllowed() }
        }
        .sheet(isPresented: $showPaywall) { PaywallView() }
        .sheet(isPresented: $showShare) { ShareComposerView(spot: spot) }
        .sheet(isPresented: $showCalibration) {
            // 校准页使用浅色/系统外观，而不是相机界面的深色
            CalibrationView(spot: spot).environment(\.colorScheme, systemColorScheme)
        }
        .sheet(isPresented: $showStory) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(spot.sceneTitle).font(.title2.bold())
                    Text(spot.story).lineSpacing(5)
                }.padding()
            }
            .presentationDetents([.medium])
        }
    }

    // MARK: - Layers

    @ViewBuilder private var background: some View {
        if arrived && canUseScene && camera.isAuthorized {
            CameraPreview(session: camera.session)
        } else {
            LinearGradient(colors: [.black, spot.tintColor.opacity(0.6)], startPoint: .top, endPoint: .bottom)
        }
    }

    @ViewBuilder
    private func alignmentLayer(size: CGSize) -> some View {
        if let g = guidance {
            let fov = camera.sensorFOV > 0
                ? ViewfinderProjection.visibleFieldOfView(sensorFOV: camera.sensorFOV, sensorAspect: camera.sensorAspect,
                                                          viewWidth: size.width, viewHeight: size.height)
                : .typicalPortrait
            let projected = ViewfinderProjection.project(yawDelta: g.yawDelta, pitchDelta: g.pitchDelta ?? 0, fov: fov)
            ZStack {
                // 名场面画框：悬浮在真实世界中的方向上
                if let p = projected, abs(p.x) < 2.5 {
                    SceneFrame(spot: spot, alignment: g.alignment, locked: latch.isLocked)
                        .frame(width: size.width * 0.78, height: size.width * 0.78 * 9 / 16)
                        .position(x: size.width / 2 + CGFloat(p.x) * size.width / 2,
                                  y: size.height / 2 - CGFloat(p.y) * size.height / 2)
                        .animation(.interactiveSpring(response: 0.25), value: p.x)
                }
                // 画面中央的取景框
                ViewfinderReticle(alignment: g.alignment, tint: spot.tintColor)
                    .frame(width: size.width * 0.82, height: size.width * 0.82 * 9 / 16)
                    .position(x: size.width / 2, y: size.height / 2)

                // 画框在视野外时，屏幕边缘的大箭头
                if projected == nil || abs(projected!.x) >= 1 {
                    EdgeTurnArrow(turnRight: g.yawDelta > 0, tint: spot.tintColor)
                        .position(x: g.yawDelta > 0 ? size.width - 46 : 46, y: size.height / 2)
                }

                VStack {
                    Spacer()
                    GuidanceHUD(guidance: g, tint: spot.tintColor, accuracy: orientation.accuracy)
                        .padding(.bottom, 110)
                }
            }
        } else {
            VStack(spacing: 12) {
                ProgressView().tint(.white)
                Text(L("scene.calibrating")).multilineTextAlignment(.center)
            }
            .foregroundStyle(.white)
        }
    }

    private var chrome: some View {
        VStack {
            HStack(alignment: .top) {
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.headline)
                        .frame(width: 44, height: 44)        // HIG：触控区域 ≥ 44pt
                        .glassSurface(Circle(), interactive: true)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L("common.close"))
                .accessibilityIdentifier("closeScene")
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(spot.work).font(.caption).opacity(0.8)
                    Text(spot.sceneTitle).font(.headline)
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .glassSurface(RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
            .padding(.top, 56)
            .padding(.horizontal)

            Spacer()

            // 相机类界面：底部控件浮在取景画面上，用同一个玻璃容器分组
            GlassGroup(spacing: 16) {
                HStack(spacing: 16) {
                    Button { showStory = true } label: {
                        Label(L("scene.story"), systemImage: "book")
                            .padding(.horizontal, 16).frame(minHeight: 44)
                            .glassSurface(Capsule(), interactive: true)
                    }
                    .buttonStyle(.plain)
                    if arrived {
                        // 快门沿用相机 App 的白色圆形，保持用户熟悉的心智模型
                        Button { camera.capturePhoto() } label: {
                            Image(systemName: "camera.fill").font(.title2)
                                .frame(width: 68, height: 68)
                                .background(.white, in: Circle())
                                .foregroundStyle(.black)
                                .padding(4)
                                .overlay(Circle().stroke(.white.opacity(0.8), lineWidth: 2))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L("celebrate.photo"))
                    }
                    // 用户在现场校准机位（数据提交到 CloudKit）
                    Button {
                        showCalibration = true
                    } label: {
                        Label(L("calib.sceneButton"), systemImage: "scope")
                            .padding(.horizontal, 16).frame(minHeight: 44)
                            .glassSurface(Capsule(), interactive: true)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("sceneCalibrate")
                }
            }
            .padding(.bottom, 36)
        }
        .foregroundStyle(.white)
        .overlay(alignment: .top) {
            if let msg = camera.statusMessage {
                Text(msg).font(.callout.bold())
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .glassSurface(Capsule())
                    .padding(.top, 110)
                    .task(id: msg) {
                        try? await Task.sleep(for: .seconds(2))
                        camera.clearStatus()
                    }
            }
        }
    }

    // MARK: - Lifecycle

    private func start() {
        UIApplication.shared.isIdleTimerDisabled = true
        orientation.declinationProvider = { [location] in location.declination }
        orientation.compassFallback = { [location] in (location.compassHeading, location.headingAccuracy) }
        orientation.start()
        haptics.prepare()
        // 拍下的现场照片存入巡礼足迹，并直接打开分享卡
        camera.onPhotoCaptured = { [pilgrimage, spot, location] image in
            pilgrimage.attachPhoto(image, spotID: spot.id)
            pilgrimage.addToAlbum(image, spotID: spot.id, kind: .scene, location: location.lastLocation?.geoPoint)
            showShare = true
        }
        if arrived { beginSceneIfAllowed() }
    }

    /// 到达机位后：有权限则记录一次体验（免费用户扣额度）并打开相机
    private func beginSceneIfAllowed() {
        guard canUseScene else { return }
        store.recordSceneEntry(spot.id)
        camera.start()
    }

    private func stop() {
        UIApplication.shared.isIdleTimerDisabled = false
        orientation.stop()
        camera.stop()
    }

    private func tick() {
        guard arrived, canUseScene, let g = guidance else { return }
        if !latch.isLocked { haptics.tick(alignment: g.alignment) }
        if latch.update(guidance: g, at: CACurrentMediaTime()) {
            haptics.success()
            pilgrimage.markCompleted(spotID: spot.id, heading: orientation.heading,
                                     latitude: location.lastLocation?.coordinate.latitude,
                                     longitude: location.lastLocation?.coordinate.longitude)
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) { celebrating = true }
        }
    }

}

// MARK: - Subviews

/// 未到达机位时的“寻路”界面。
private struct ApproachLayer: View {
    let spot: Spot
    let distance: Double?
    let bearing: Double?
    let heading: Double?

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            if let d = distance, let b = bearing {
                let relative = heading.map { GeoMath.signedDelta(from: $0, to: b) }
                ZStack {
                    Circle().stroke(.white.opacity(0.2), lineWidth: 2).frame(width: 240, height: 240)
                    Circle().fill(spot.tintColor.opacity(0.18)).frame(width: 240, height: 240)
                    Image(systemName: "location.north.fill")
                        .font(.system(size: 110))
                        .foregroundStyle(.white)
                        .rotationEffect(.degrees(relative ?? b))
                        .animation(.interactiveSpring(response: 0.3), value: relative ?? b)
                        .shadow(color: spot.tintColor, radius: 16)
                }
                VStack(spacing: 6) {
                    Text(NearbySearch.formatDistance(d))
                        .font(.system(size: 48, weight: .bold, design: .rounded).monospacedDigit())
                    Text(heading == nil ? L("scene.spotDirection", Compass.name(b))
                                        : hint(relative: relative ?? 0))
                        .font(.title3)
                    Text(L("scene.walkCloser", Int(spot.arrivalRadius)))
                        .font(.footnote).opacity(0.7)
                }
                .multilineTextAlignment(.center)
            } else {
                ProgressView().tint(.white)
                Text(L("scene.locating"))
            }
            Spacer()
            Spacer()
        }
        .foregroundStyle(.white)
        .padding()
    }

    private func hint(relative: Double) -> String {
        let a = abs(relative)
        if a < 20 { return L("scene.straightAhead") }
        if a > 150 { return L("scene.behind") }
        return relative > 0 ? L("scene.aheadRight") : L("scene.aheadLeft")
    }
}

/// 悬浮在真实方向上的名场面画框。
private struct SceneFrame: View {
    let spot: Spot
    let alignment: Double
    let locked: Bool

    var body: some View {
        SceneArtwork(spot: spot)
            .opacity(locked ? 0.55 : 0.25 + 0.5 * pow(alignment, 3))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(spot.tintColor, lineWidth: locked ? 4 : 2)
                    .shadow(color: spot.tintColor, radius: locked ? 14 : 4)
            )
            .scaleEffect(locked ? 1.05 : 1)
            .animation(.spring, value: locked)
    }
}

/// 画面中央的取景框，四角会随对准程度点亮。
private struct ViewfinderReticle: View {
    let alignment: Double
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            let w: CGFloat = geo.size.width
            let h: CGFloat = geo.size.height
            let l: CGFloat = 26
            Path { p in
                let corners: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [(0, 0, 1, 1), (w, 0, -1, 1), (0, h, 1, -1), (w, h, -1, -1)]
                for (x, y, dx, dy) in corners {
                    p.move(to: CGPoint(x: x, y: y + dy * l))
                    p.addLine(to: CGPoint(x: x, y: y))
                    p.addLine(to: CGPoint(x: x + dx * l, y: y))
                }
            }
            .stroke(alignment > 0.97 ? tint : .white.opacity(0.4 + 0.6 * alignment),
                    style: StrokeStyle(lineWidth: 4, lineCap: .round))
        }
    }
}

private struct EdgeTurnArrow: View {
    let turnRight: Bool
    let tint: Color
    @State private var nudge = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Image(systemName: turnRight ? "chevron.right.2" : "chevron.left.2")
            .font(.system(size: 44, weight: .heavy))
            .foregroundStyle(.white)
            .shadow(color: tint, radius: 10)
            .offset(x: nudge ? (turnRight ? 10 : -10) : 0)
            .animation(.easeInOut(duration: 0.6).repeatForever(), value: nudge)
            .onAppear { nudge = !reduceMotion }
    }
}

/// 底部的文字 + 刻度提示。
private struct GuidanceHUD: View {
    let guidance: SceneGuidance
    let tint: Color
    let accuracy: Double

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                switch guidance.turn {
                case .left: Image(systemName: "arrow.turn.up.left")
                case .right: Image(systemName: "arrow.turn.up.right")
                case .aligned:
                    switch guidance.tilt {
                    case .up: Image(systemName: "arrow.up")
                    case .down: Image(systemName: "arrow.down")
                    case .level: Image(systemName: "checkmark.seal.fill")
                    }
                }
                Text(guidance.instruction)
            }
            .font(.title3.bold())

            // 对准进度条
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.2))
                    Capsule().fill(tint.gradient)
                        .frame(width: geo.size.width * guidance.alignment)
                }
            }
            .frame(width: 220, height: 6)

            if accuracy < 0 || accuracy > 20 {
                Text(L("scene.weakCompass")).font(.caption2).opacity(0.8)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 22).padding(.vertical, 16)
        .glassSurface(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .animation(.default, value: guidance.turn)
    }
}
