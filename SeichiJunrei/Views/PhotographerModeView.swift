import SwiftUI
import UIKit
import AVFoundation
import PhotosUI
import Photos
import QuartzCore
import Combine
import CoreLocation
import SeichiCore

// MARK: - 主角构图（用户在自己的截图上标记，保存在本机）

enum FramingStore {
    private static let key = "subjectFramings"

    static func framing(for spotID: String) -> SubjectFraming? {
        guard let data = UserDefaults.standard.data(forKey: key),
              let all = try? JSONDecoder().decode([String: SubjectFraming].self, from: data) else { return nil }
        return all[spotID]
    }

    static func set(_ framing: SubjectFraming?, for spotID: String) {
        var all = (UserDefaults.standard.data(forKey: key))
            .flatMap { try? JSONDecoder().decode([String: SubjectFraming].self, from: $0) } ?? [:]
        all[spotID] = framing
        if let data = try? JSONEncoder().encode(all) { UserDefaults.standard.set(data, forKey: key) }
    }
}

/// 照片（竖屏 3:4）坐标 ↔ 屏幕坐标。相机预览是 aspectFill，所以照片的左右两侧会被裁掉一部分。
struct PhotoFrameMapper {
    /// 照片宽高比（宽 / 高），竖屏 3:4
    var photoAspect: Double = 3.0 / 4.0
    var viewSize: CGSize

    /// 照片在屏幕上的显示区域（可能超出屏幕）
    var photoRect: CGRect {
        let vw = viewSize.width, vh = viewSize.height
        guard vw > 0, vh > 0 else { return .zero }
        let scale = max(vw / CGFloat(photoAspect), vh)   // 以“照片高 = 1”为单位
        let w = CGFloat(photoAspect) * scale, h = scale
        return CGRect(x: (vw - w) / 2, y: (vh - h) / 2, width: w, height: h)
    }

    func rect(_ r: UnitRect) -> CGRect {
        let p = photoRect
        return CGRect(x: p.minX + CGFloat(r.x) * p.width, y: p.minY + CGFloat(r.y) * p.height,
                      width: CGFloat(r.width) * p.width, height: CGFloat(r.height) * p.height)
    }
}

// MARK: - 帮拍模式

/// “请人帮我拍”：被拍的人站在主角的位置，App 引导拍照的人把手机放到正确的位置、远近和角度。
///
/// 粗调靠人、精调靠 App：
/// 1. 一次只给一条最重要的指令（大箭头 + 大字 + 震动，可选语音）
/// 2. 人物大小差得不多时自动变焦，不用来回走
/// 3. 对齐并稳定 1 秒后自动倒数 3 秒拍照
/// 4. 拍完按原作构图自动裁切，把被拍的人精确放到主角的位置
struct PhotographerModeView: View {
    let spot: Spot

    @Environment(LocationService.self) private var location
    @Environment(StoreService.self) private var store
    @Environment(PilgrimageStore.self) private var pilgrimage
    @Environment(\.dismiss) private var dismiss

    @State private var shooting = false
    @State private var guideLanguage = AppLanguage.current
    @State private var orientation = OrientationService()
    @State private var camera = CameraController()
    @State private var haptics = Haptics()
    @State private var speech = AVSpeechSynthesizer()
    @State private var target: SubjectFraming = .default
    @State private var showEditor = false
    @State private var showPaywall = false

    @AppStorage("pgAutoShutter") private var autoShutter = true
    @AppStorage("pgVoice") private var voice = false
    @AppStorage("pgGhost") private var showGhost = true

    /// 每秒刷新约 10 次的取景状态。放在单独的对象里，只让需要它的子视图订阅，
    /// 避免整页（包括按钮、菜单）跟着高频重绘导致点击失灵。
    @State private var live = PhotographerLive()
    @State private var toast: String?
    /// nil = 自动变焦；否则固定倍数
    @State private var manualZoom: Double?
    @State private var result: UIImage?
    @State private var closeAfterResult = false

    private let ticker = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()
    /// 开始时的变焦倍数：留出缩小的余地，让自动变焦可以双向微调
    private let baseZoom = 1.25

    private var canUse: Bool { store.allowance.canEnter(spot.id, entitlement: store.entitlement) }
    private var distanceToSpot: Double? {
        location.lastLocation.map { GeoMath.distance(from: $0.geoPoint, to: spot.coordinate) }
    }
    private var farFromSpot: Bool { (distanceToSpot ?? 0) > spot.arrivalRadius + 20 }

    var body: some View {
        Group {
            if shooting {
                shootingView
            } else {
                handoffView
            }
        }
        .onAppear {
            target = FramingStore.framing(for: spot.id) ?? .default
            orientation.declinationProvider = { [location] in location.declination }
            orientation.compassFallback = { [location] in (location.compassHeading, location.headingAccuracy) }
            orientation.start()
            haptics.prepare()
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            live.countdownTask?.cancel()
            orientation.stop()
            camera.stop()
            speech.stopSpeaking(at: .immediate)
        }
        .sheet(isPresented: $showEditor, onDismiss: {
            target = FramingStore.framing(for: spot.id) ?? .default
        }) {
            FramingEditorView(spot: spot)
        }
        .sheet(isPresented: $showPaywall) { PaywallView() }
    }

    // MARK: 交接页（给被拍的人看）

    private var handoffView: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(spot.workBadge).font(.subheadline.bold()).foregroundStyle(spot.tintColor)
                        Text(L("pg.title")).font(.largeTitle.bold())
                        Text(L("pg.subtitle")).font(.callout).foregroundStyle(.secondary)
                    }

                    HStack(alignment: .top, spacing: 16) {
                        FramingPreview(spot: spot, framing: target)
                            .frame(width: 120, height: 160)
                        VStack(alignment: .leading, spacing: 10) {
                            Button { showEditor = true } label: {
                                Label(L("pg.markSubject"), systemImage: "person.crop.rectangle")
                                    .font(.subheadline.weight(.semibold))
                            }
                            .glassButton(tint: spot.tintColor)
                            .accessibilityIdentifier("markSubject")
                            Text(FramingStore.framing(for: spot.id) == nil ? L("pg.defaultFraming") : L("pg.markHint"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        StepRow(number: 1, text: L("pg.step1", subjectDistanceText), tint: spot.tintColor)
                        StepRow(number: 2, text: L("pg.step2"), tint: spot.tintColor)
                        StepRow(number: 3, text: L("pg.step3"), tint: spot.tintColor)
                    }

                    if farFromSpot, let d = distanceToSpot {
                        Label(L("pg.farFromSpot", NearbySearch.formatDistance(d)), systemImage: "figure.walk")
                            .font(.callout)
                            .foregroundStyle(.orange)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text(L("pg.guideLanguage")).font(.subheadline.bold())
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(AppLanguage.supported, id: \.self) { code in
                                    let on = guideLanguage == code
                                    Button { guideLanguage = code } label: {
                                        Text(AppLanguage.nativeName(code))
                                            .font(.subheadline.weight(on ? .bold : .regular))
                                            .padding(.horizontal, 14)
                                            .frame(minHeight: 44)
                                            .foregroundStyle(on ? Color.white : Color.primary)
                                            .glassSurface(Capsule(), tint: on ? spot.tintColor : nil, interactive: true)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityAddTraits(on ? .isSelected : [])
                                }
                            }
                        }
                    }

                    Button {
                        if canUse { startShooting() } else { showPaywall = true }
                    } label: {
                        Label(L("pg.start"), systemImage: "hand.raised.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 34)
                    }
                    .glassButton(prominent: true, tint: spot.tintColor)
                    .controlSize(.large)
                    .accessibilityIdentifier("startPhotographer")
                }
                .padding()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("common.close")) { dismiss() }
                        .accessibilityIdentifier("closePhotographer")
                }
            }
        }
    }

    /// 被拍的人应该站在机位前方多远（按目标构图里的人物大小估算）
    private var subjectDistanceText: String {
        let vfov = fieldOfView(zoom: baseZoom).vertical
        let d = FramingGuidance.distance(to: target.box(aspect: 0.75), verticalFOV: vfov)
        return String(format: "%.0f", max(1, d.rounded()))
    }

    // MARK: 取景页（给拍照的人看）

    private var shootingView: some View {
        GeometryReader { geo in
            let mapper = PhotoFrameMapper(viewSize: geo.size)
            ZStack {
                if camera.isAuthorized {
                    CameraPreview(session: camera.session)
                } else {
                    LinearGradient(colors: [.black, spot.tintColor.opacity(0.6)], startPoint: .top, endPoint: .bottom)
                }

                // 名场面截图半透明叠在画面上（与标记时同样的 3:4 裁切）
                if showGhost, let scene = SceneImageStore.shared.image(for: spot.id) {
                    let r = mapper.photoRect
                    Image(uiImage: scene)
                        .resizable()
                        .scaledToFill()
                        .frame(width: r.width, height: r.height)
                        .clipped()
                        .position(x: r.midX, y: r.midY)
                        .opacity(0.3)
                        .allowsHitTesting(false)
                }

                LiveFramingOverlay(live: live, camera: camera, mapper: mapper, target: target)

                VStack(spacing: 0) {
                    topBar
                    InstructionBanner(live: live, spot: spot, language: guideLanguage)
                        .padding(.horizontal)
                        .padding(.top, 8)
                    if let toast {
                        Text(toast)
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(.black.opacity(0.6), in: Capsule())
                            .padding(.top, 10)
                            .transition(.opacity)
                            .task(id: toast) {
                                try? await Task.sleep(for: .seconds(1.6))
                                withAnimation { self.toast = nil }
                            }
                    }
                    Spacer()
                    bottomBar
                }
                .padding(.top, geo.safeAreaInsets.top + 8)
                .padding(.bottom, geo.safeAreaInsets.bottom + 16)

                CountdownOverlay(live: live)

            }
            .ignoresSafeArea()
        }
        .environment(\.colorScheme, .dark)
        .statusBarHidden()
        .onReceive(ticker) { _ in tick() }
        // 拍好的照片用系统 sheet 展示：可以分享、重拍或完成
        .sheet(isPresented: Binding(get: { result != nil }, set: { if !$0 { result = nil } }),
               onDismiss: { if closeAfterResult { dismiss() } }) {
            if let result {
                ResultSheet(image: result, spot: spot, onDone: {
                    // 先收起结果页，收起后再关闭帮拍模式
                    closeAfterResult = true
                    self.result = nil
                })
                    .presentationDetents([.large])
            }
        }
    }

    private var topBar: some View {
        HStack {
            Button {
                cancelCountdown()
                camera.stop()
                speech.stopSpeaking(at: .immediate)
                shooting = false
            } label: {
                Image(systemName: "chevron.backward").font(.headline)
                    .frame(width: 48, height: 48)
                    // 实底而不是可交互玻璃：真机上可交互玻璃会吃掉按钮的点击
                    .background(Color.black.opacity(0.45), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(LIn(guideLanguage, "common.close"))
            .accessibilityIdentifier("closeShooting")
            Spacer()
            Text(LIn(guideLanguage, "pg.photographerHeader"))
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14).frame(minHeight: 44)
                .background(Color.black.opacity(0.45), in: Capsule())
                .allowsHitTesting(false)
            Spacer()
            Menu {
                Picker(LIn(guideLanguage, "pg.guideLanguage"), selection: $guideLanguage) {
                    ForEach(AppLanguage.supported, id: \.self) { code in
                        Text(AppLanguage.nativeName(code)).tag(code)
                    }
                }
            } label: {
                Image(systemName: "character.bubble").font(.headline)
                    .frame(width: 48, height: 48)
                    .background(Color.black.opacity(0.45), in: Circle())
                    .contentShape(Circle())
            }
            .accessibilityLabel(LIn(guideLanguage, "pg.guideLanguage"))
        }
        .foregroundStyle(.white)
        .padding(.horizontal)
    }

    private var bottomBar: some View {
        Group {
            HStack(spacing: 18) {
                VStack(spacing: 10) {
                    toggle(LIn(guideLanguage, "pg.ghost"), symbol: "square.on.square", on: showGhost && hasScreenshot) {
                        guard hasScreenshot else { show(LIn(guideLanguage, "pg.ghostNeedsImage")); return }
                        showGhost.toggle()
                        show(LIn(guideLanguage, showGhost ? "pg.ghostOn" : "pg.ghostOff"))
                    }
                    toggle(LIn(guideLanguage, "pg.voice"), symbol: voice ? "speaker.wave.2.fill" : "speaker.slash.fill", on: voice) {
                        voice.toggle()
                        show(LIn(guideLanguage, voice ? "pg.voiceOn" : "pg.voiceOff"))
                        if voice { speakNow() } else { speech.stopSpeaking(at: .immediate) }
                    }
                    .accessibilityIdentifier("pgVoice")
                }
                // 快门：外圈显示对齐进度
                Button(action: shutter) {
                    ShutterRing(live: live).frame(width: 84, height: 84)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(LIn(guideLanguage, "celebrate.photo"))
                .accessibilityIdentifier("pgShutter")
                VStack(spacing: 10) {
                    toggle(LIn(guideLanguage, "pg.autoShutter"), symbol: "timer", on: autoShutter) {
                        autoShutter.toggle()
                        if !autoShutter { cancelCountdown() }
                        show(LIn(guideLanguage, autoShutter ? "pg.autoOn" : "pg.autoOff"))
                    }
                    .accessibilityIdentifier("pgAutoShutter")
                    // 变焦：点一下在 自动 → 1× → 2× → 自动 之间切换
                    Button(action: cycleZoom) {
                        ZoomLabel(camera: camera, manual: manualZoom, language: guideLanguage)
                            .frame(width: 64, height: 58)
                            .background(manualZoom == nil ? Color.black.opacity(0.45) : Color.yellow,
                                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .foregroundStyle(manualZoom == nil ? Color.white : Color.black)
                            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("pgZoom")
                }
            }
        }
        .foregroundStyle(.white)
    }

    private var hasScreenshot: Bool { SceneImageStore.shared.hasImage(for: spot.id) }

    /// 开关按钮：打开时用相机 App 惯用的黄色高亮，并在下方写明“开 / 关”
    private func toggle(_ title: String, symbol: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: symbol).font(.body.weight(.semibold))
                Text(title).font(.caption2.weight(.semibold))
                Text(LIn(guideLanguage, on ? "pg.on" : "pg.off")).font(.system(size: 9, weight: .bold))
            }
            .foregroundStyle(on ? Color.black : Color.white)
            .frame(width: 64, height: 58)
            .background(on ? Color.yellow : Color.black.opacity(0.45),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// 变焦：自动（App 根据人物大小微调）→ 固定 1× → 固定 2× → 自动
    private func cycleZoom() {
        switch manualZoom {
        case nil: manualZoom = 1
        case 1?: manualZoom = 2
        default: manualZoom = nil
        }
        if let z = manualZoom {
            camera.setZoom(z, rate: 12)
            show(LIn(guideLanguage, "pg.zoomManual", String(format: "%.0f×", z)))
        } else {
            camera.setZoom(baseZoom, rate: 12)
            show(LIn(guideLanguage, "pg.zoomAutoOn"))
        }
    }

    private func show(_ message: String) {
        withAnimation { toast = message }
    }

    // MARK: 逻辑

    private func startShooting() {
        // 先请求“添加到相册”的权限，免得系统弹窗在按下快门的那一刻打断
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { _ in }
        store.recordSceneEntry(spot.id)
        UIApplication.shared.isIdleTimerDisabled = true
        camera.detectsPeople = true
        camera.savesAutomatically = false
        camera.onPhotoCaptured = { image in handleCaptured(image) }
        camera.start()
        shooting = true
        // 等相机配置好再设置初始变焦
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { camera.setZoom(baseZoom, rate: 20) }
    }

    /// 取景画面的视场角（竖屏：长边是竖直方向）
    private func fieldOfView(zoom: Double) -> (vertical: Double, horizontal: Double) {
        let longSide = camera.sensorFOV > 0 ? camera.sensorFOV : 69
        let aspect = camera.sensorAspect > 0 ? camera.sensorAspect : 4.0 / 3.0
        let t = tan(longSide * .pi / 360) / zoom
        return (atan(t) * 360 / .pi, atan(t / aspect) * 360 / .pi)
    }

    private func tick() {
        guard shooting, result == nil else { return }
        let zoom = max(camera.zoomFactor, 1)
        let fov = fieldOfView(zoom: zoom)
        let headingDelta = orientation.heading.map { GeoMath.signedDelta(from: $0, to: spot.sceneHeading) }
        let pitchDelta = spot.scenePitch.map { $0 - (orientation.pitch ?? 0) }
        let range = camera.zoomRange
        let g = FramingGuidance.compute(
            target: target, subject: camera.subjectBox,
            headingDelta: headingDelta, pitchDelta: pitchDelta,
            verticalFOV: fov.vertical, horizontalFOV: fov.horizontal,
            zoomCorrectable: manualZoom == nil ? (range.lowerBound / zoom)...(range.upperBound / zoom) : 1...1)
        let previous = live.guidance?.step
        if live.guidance != g { live.guidance = g }
        let now = CACurrentMediaTime()

        // 自动变焦：人物大小差一点时由 App 补上（限制频率，等画面稳定后再调）
        if manualZoom == nil, let subject = camera.subjectBox, abs(headingDelta ?? 0) < 20, now - live.lastZoomAdjust > 0.5 {
            let needed = target.height / max(subject.height, 0.02)
            if abs(needed - 1) > 0.06 {
                camera.setZoom(zoom * (1 + (needed - 1) * 0.6))
                live.lastZoomAdjust = now
            }
        }

        // 反馈：越接近越密集的震动；完全对齐时一次成功反馈
        if g.step == .perfect {
            if previous != .perfect { haptics.success() }
            if live.perfectSince == nil { live.perfectSince = now }
            if autoShutter, live.countdown == nil, let since = live.perfectSince, now - since > 1.0 { startCountdown() }
        } else {
            haptics.tick(alignment: g.score)
            live.perfectSince = nil
            if live.countdown != nil, g.score < 0.75 { cancelCountdown() }
        }
        speakIfNeeded(now: now)
    }

    private var currentInstruction: String {
        PhotographerInstruction.make(guidance: live.guidance, spot: spot, location: location.lastLocation,
                                     language: guideLanguage).text
    }

    private func speakIfNeeded(now: CFTimeInterval) {
        guard voice, live.countdown == nil else { return }
        let text = currentInstruction
        guard text != live.lastSpoken, now - live.lastSpokenAt > 1.8 else { return }
        speak(text, now: now)
    }

    /// 打开语音时立即读出当前指令，让用户马上知道开关生效了
    private func speakNow() { speak(currentInstruction, now: CACurrentMediaTime()) }

    private func speak(_ text: String, now: CFTimeInterval) {
        live.lastSpoken = text
        live.lastSpokenAt = now
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: Self.speechLocale(guideLanguage))
        speech.stopSpeaking(at: .immediate)
        speech.speak(utterance)
    }

    static func speechLocale(_ code: String) -> String {
        switch code {
        case "zh-Hans": return "zh-CN"
        case "zh-Hant": return "zh-TW"
        case "ja": return "ja-JP"
        case "ko": return "ko-KR"
        default: return "en-US"
        }
    }

    private func startCountdown() {
        live.countdownTask?.cancel()
        live.countdownTask = Task { @MainActor in
            for n in stride(from: 3, through: 1, by: -1) {
                withAnimation(.spring(response: 0.3)) { live.countdown = n }
                haptics.tick(alignment: 1)
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
            }
            live.countdown = nil
            shutter()
        }
    }

    private func cancelCountdown() {
        live.countdownTask?.cancel()
        live.countdownTask = nil
        if live.countdown != nil { withAnimation { live.countdown = nil } }
    }

    private func shutter() {
        cancelCountdown()
        live.subjectAtShutter = camera.subjectBox
        camera.capturePhoto()
    }

    /// 拍完：按原作构图自动裁切 → 存相册 → 记录巡礼
    private func handleCaptured(_ image: UIImage) {
        var final = image
        if let subject = live.subjectAtShutter,
           let crop = AutoReframe.cropRect(subject: subject, target: target) {
            final = image.cropped(to: crop) ?? image
        }
        camera.save(final)
        pilgrimage.markCompleted(spotID: spot.id, heading: orientation.heading,
                                 latitude: location.lastLocation?.coordinate.latitude,
                                 longitude: location.lastLocation?.coordinate.longitude)
        pilgrimage.attachPhoto(final, spotID: spot.id)
        haptics.success()
        result = final
    }
}

/// 帮拍取景的高频状态
@Observable
final class PhotographerLive {
    var guidance: FramingGuidance?
    var countdown: Int?
    @ObservationIgnored var perfectSince: CFTimeInterval?
    @ObservationIgnored var countdownTask: Task<Void, Never>?
    @ObservationIgnored var lastZoomAdjust: CFTimeInterval = 0
    @ObservationIgnored var lastSpoken = ""
    @ObservationIgnored var lastSpokenAt: CFTimeInterval = 0
    @ObservationIgnored var subjectAtShutter: UnitRect?
}

/// 给拍照的人的一条指令（图标 + 文字），可以用拍照人选的语言
enum PhotographerInstruction {
    static func make(guidance: FramingGuidance?, spot: Spot, location: CLLocation?,
                     language lang: String) -> (symbol: String, text: String) {
        if let loc = location {
            let d = GeoMath.distance(from: loc.geoPoint, to: spot.coordinate)
            if d > spot.arrivalRadius + 20 {
                let bearing = GeoMath.bearing(from: loc.geoPoint, to: spot.coordinate)
                return ("figure.walk", LIn(lang, "pg.goto", NearbySearch.formatDistance(d),
                                           LIn(lang, "compass.\(GeoMath.compassIndex(bearing))")))
            }
        }
        guard let g = guidance else { return ("location.north.line", LIn(lang, "pg.find")) }
        func m(_ v: Double) -> String { String(format: abs(v) < 1 ? "%.1f" : "%.0f", abs(v)) }
        switch g.step {
        case .findSubject: return ("person.fill.viewfinder", LIn(lang, "pg.find"))
        case .turn(let d): return d > 0 ? ("arrow.turn.up.right", LIn(lang, "pg.turnRight", abs(d)))
                                        : ("arrow.turn.up.left", LIn(lang, "pg.turnLeft", abs(d)))
        case .tilt(let d): return d > 0 ? ("arrow.up.to.line", LIn(lang, "pg.tiltUp", abs(d)))
                                        : ("arrow.down.to.line", LIn(lang, "pg.tiltDown", abs(d)))
        case .moveCloser(let v): return ("figure.walk.arrival", LIn(lang, "pg.closer", m(v)))
        case .moveBack(let v): return ("figure.walk.departure", LIn(lang, "pg.back", m(v)))
        case .sidestep(let v): return v > 0 ? ("arrow.right", LIn(lang, "pg.stepRight", m(v)))
                                            : ("arrow.left", LIn(lang, "pg.stepLeft", m(v)))
        case .raise: return ("arrow.up", LIn(lang, "pg.raise"))
        case .lower: return ("arrow.down", LIn(lang, "pg.lower"))
        case .perfect: return ("checkmark.circle.fill", LIn(lang, "pg.perfect"))
        }
    }
}

/// 当前最重要的一条指令：大图标 + 大字
private struct InstructionBanner: View {
    let live: PhotographerLive
    let spot: Spot
    let language: String
    @Environment(LocationService.self) private var location

    var body: some View {
        let instruction = PhotographerInstruction.make(guidance: live.guidance, spot: spot,
                                                       location: location.lastLocation, language: language)
        let perfect = live.guidance?.step == .perfect
        HStack(spacing: 14) {
            Image(systemName: instruction.symbol)
                .font(.system(size: 40, weight: .bold))
                .frame(width: 56)
                .contentTransition(.symbolEffect(.replace))
            Text(instruction.text)
                .font(.title2.bold())
                .minimumScaleFactor(0.6)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("pgInstruction")
        }
        .foregroundStyle(.white)
        .padding(16)
        .background(perfect ? Color.green.opacity(0.85) : Color.black.opacity(0.55),
                    in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .animation(.snappy, value: instruction.text)
        .allowsHitTesting(false)
    }
}

private struct LiveFramingOverlay: View {
    let live: PhotographerLive
    let camera: CameraController
    let mapper: PhotoFrameMapper
    let target: SubjectFraming

    var body: some View {
        FramingOverlay(target: mapper.rect(target.box(aspect: 0.75)),
                       subject: camera.subjectBox.map { mapper.rect($0) },
                       score: live.guidance?.score ?? 0,
                       perfect: live.guidance?.step == .perfect)
    }
}

private struct CountdownOverlay: View {
    let live: PhotographerLive
    var body: some View {
        if let n = live.countdown {
            Text("\(n)")
                .font(.system(size: 140, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .shadow(radius: 12)
                .transition(.scale.combined(with: .opacity))
                .id(n)
                .allowsHitTesting(false)
                .accessibilityIdentifier("pgCountdown")
        }
    }
}

/// 快门：外圈显示对齐进度
private struct ShutterRing: View {
    let live: PhotographerLive
    var body: some View {
        let score = live.guidance?.score ?? 0
        ZStack {
            Circle().stroke(.white.opacity(0.25), lineWidth: 5)
            Circle()
                .trim(from: 0, to: score)
                .stroke(live.guidance?.step == .perfect ? Color.green : Color.white,
                        style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.2), value: score)
            Circle().fill(.white).padding(9)
        }
    }
}

/// 变焦按钮的内容：当前倍数 + 自动 / 手动
private struct ZoomLabel: View {
    let camera: CameraController
    let manual: Double?
    let language: String
    var body: some View {
        VStack(spacing: 1) {
            Image(systemName: "plus.magnifyingglass").font(.caption.weight(.semibold))
            Text(String(format: "%.1f×", camera.zoomFactor))
                .font(.subheadline.bold().monospacedDigit())
            Text(LIn(language, manual == nil ? "pg.zoomAuto" : "pg.zoomFixed"))
                .font(.system(size: 9, weight: .bold))
        }
    }
}

extension UIImage {
    /// 按归一化区域裁切（考虑图片方向）
    func cropped(to r: UnitRect) -> UIImage? {
        let rect = CGRect(x: CGFloat(r.x) * size.width, y: CGFloat(r.y) * size.height,
                          width: CGFloat(r.width) * size.width, height: CGFloat(r.height) * size.height)
        guard rect.width >= 1, rect.height >= 1 else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        return UIGraphicsImageRenderer(size: rect.size, format: format).image { _ in
            draw(at: CGPoint(x: -rect.minX, y: -rect.minY))
        }
    }
}

// MARK: - 子视图

private struct StepRow: View {
    let number: Int
    let text: String
    let tint: Color
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("\(number)")
                .font(.headline.monospacedDigit())
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(tint, in: Circle())
            Text(text).font(.body).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// 取景框上的目标人形 + 检测到的人 + 连接线
private struct FramingOverlay: View {
    let target: CGRect
    let subject: CGRect?
    let score: Double
    let perfect: Bool

    private var color: Color { perfect ? .green : (score > 0.7 ? .yellow : .white) }

    var body: some View {
        ZStack {
            // 目标：主角的位置（人形轮廓）
            Image(systemName: "figure.stand")
                .resizable()
                .scaledToFit()
                .foregroundStyle(color.opacity(0.35))
                .frame(width: target.width * 1.4, height: target.height)
                .position(x: target.midX, y: target.midY)
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(color, style: StrokeStyle(lineWidth: 3, dash: perfect ? [] : [10, 7]))
                .frame(width: target.width * 1.4, height: target.height)
                .position(x: target.midX, y: target.midY)

            if let subject {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(color, lineWidth: 2)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(color.opacity(0.08)))
                    .frame(width: subject.width, height: subject.height)
                    .position(x: subject.midX, y: subject.midY)
                if !perfect {
                    // 被拍的人 → 目标位置的连线，直观看出还差多少
                    Path { p in
                        p.move(to: CGPoint(x: subject.midX, y: subject.maxY))
                        p.addLine(to: CGPoint(x: target.midX, y: target.maxY))
                    }
                    .stroke(color.opacity(0.8), style: StrokeStyle(lineWidth: 2, dash: [4, 6]))
                }
            }
        }
        .animation(.interactiveSpring(response: 0.25), value: subject)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// 3:4 的构图预览：截图（如果有）+ 主角位置
struct FramingPreview: View {
    let spot: Spot
    let framing: SubjectFraming

    var body: some View {
        GeometryReader { geo in
            let box = framing.box(aspect: 0.75)
            ZStack(alignment: .topLeading) {
                if let scene = SceneImageStore.shared.image(for: spot.id) {
                    Image(uiImage: scene).resizable().scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height).clipped()
                } else {
                    LinearGradient(colors: [spot.tintColor.opacity(0.7), .black.opacity(0.8)],
                                   startPoint: .top, endPoint: .bottom)
                }
                Image(systemName: "figure.stand")
                    .resizable().scaledToFit()
                    .foregroundStyle(.white)
                    .shadow(radius: 2)
                    .frame(width: CGFloat(box.width) * geo.size.width * 1.4,
                           height: CGFloat(box.height) * geo.size.height)
                    .position(x: CGFloat(box.midX) * geo.size.width,
                              y: CGFloat(box.y + box.height / 2) * geo.size.height)
            }
        }
        .aspectRatio(3.0 / 4.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityHidden(true)
    }
}

/// 拍好的照片：已按原作构图裁切并存入相册
private struct ResultSheet: View {
    let image: UIImage
    let spot: Spot
    let onDone: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var showShare = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityHidden(true)
                Label(L("pg.saved"), systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(spot.tintColor)
                    .accessibilityIdentifier("pgSaved")
                HStack(spacing: 12) {
                    Button { dismiss() } label: {
                        Label(L("pg.retake"), systemImage: "arrow.counterclockwise")
                            .frame(maxWidth: .infinity, minHeight: 30)
                    }
                    .glassButton()
                    Button { showShare = true } label: {
                        Label(L("share.share"), systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity, minHeight: 30)
                    }
                    .glassButton(prominent: true, tint: spot.tintColor)
                }
                .controlSize(.large)
            }
            .padding()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(L("common.done"), action: onDone) }
            }
        }
        .sheet(isPresented: $showShare) { ShareComposerView(spot: spot) }
    }
}

// MARK: - 标记主角位置

/// 在用户自己的名场面截图上，用人形框标出主角站的位置和大小。
struct FramingEditorView: View {
    let spot: Spot
    @Environment(\.dismiss) private var dismiss
    @State private var framing: SubjectFraming = .default
    @State private var dragStart: SubjectFraming?
    @State private var picked: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text(L("pg.editorHint"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                GeometryReader { geo in
                    let size = geo.size
                    let box = framing.box(aspect: 0.75)
                    let rect = CGRect(x: CGFloat(box.x) * size.width, y: CGFloat(box.y) * size.height,
                                      width: CGFloat(box.width) * size.width, height: CGFloat(box.height) * size.height)
                    ZStack(alignment: .topLeading) {
                        if let scene = SceneImageStore.shared.image(for: spot.id) {
                            Image(uiImage: scene).resizable().scaledToFill()
                                .frame(width: size.width, height: size.height).clipped()
                        } else {
                            LinearGradient(colors: [spot.tintColor.opacity(0.7), .black.opacity(0.8)],
                                           startPoint: .top, endPoint: .bottom)
                        }
                        // 人形框：拖动移动
                        ZStack {
                            RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.15))
                            RoundedRectangle(cornerRadius: 10).stroke(.white, lineWidth: 2)
                            Image(systemName: "figure.stand").resizable().scaledToFit()
                                .foregroundStyle(.white).padding(4)
                        }
                        .frame(width: rect.width * 1.4, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                        .gesture(DragGesture()
                            .onChanged { v in
                                let start = dragStart ?? framing
                                dragStart = start
                                framing = SubjectFraming(centerX: start.centerX + Double(v.translation.width / size.width),
                                                         footY: start.footY + Double(v.translation.height / size.height),
                                                         height: start.height)
                            }
                            .onEnded { _ in dragStart = nil })
                        .accessibilityIdentifier("framingBox")
                        // 上方圆点：拖动调整大小（脚底位置不变）
                        Circle().fill(.white).frame(width: 26, height: 26)
                            .shadow(radius: 2)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                            .position(x: rect.midX, y: rect.minY)
                            .gesture(DragGesture()
                                .onChanged { v in
                                    let start = dragStart ?? framing
                                    dragStart = start
                                    framing = SubjectFraming(centerX: start.centerX, footY: start.footY,
                                                             height: start.height - Double(v.translation.height / size.height))
                                }
                                .onEnded { _ in dragStart = nil })
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .aspectRatio(3.0 / 4.0, contentMode: .fit)

                HStack {
                    PhotosPicker(selection: $picked, matching: .images) {
                        Label(SceneImageStore.shared.hasImage(for: spot.id) ? L("detail.changeImage") : L("pg.addScreenshot"),
                              systemImage: "photo.badge.plus")
                    }
                    Spacer()
                    Button(L("pg.reset")) { framing = .default }
                }
                .font(.subheadline.weight(.semibold))
            }
            .padding()
            .navigationTitle(L("pg.editorTitle"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("common.cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("common.done")) {
                        FramingStore.set(framing, for: spot.id)
                        dismiss()
                    }
                    .accessibilityIdentifier("saveFraming")
                }
            }
            .onAppear { framing = FramingStore.framing(for: spot.id) ?? .default }
            .onChange(of: picked) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        await MainActor.run { _ = SceneImageStore.shared.save(data, for: spot.id) }
                    }
                    await MainActor.run { picked = nil }
                }
            }
        }
    }
}
