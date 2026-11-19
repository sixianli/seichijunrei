import SwiftUI
import SeichiCore

@main
struct SeichiJunreiApp: App {
    @State private var store = SpotStore()
    @State private var location = LocationService()
    @State private var storeKit = StoreService.shared
    @State private var pilgrimage = PilgrimageStore.shared
    @State private var language = AppLanguage.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(location)
                .environment(storeKit)
                .environment(pilgrimage)
                .environment(language)
                // 日期、数字格式跟随 App 内选择的语言
                .environment(\.locale, language.locale)
                .onChange(of: language.code) { _, code in store.applyLanguage(code) }
                .task {
                    storeKit.start()
                    // 之前因断网 / 未登录 iCloud 没能提交的校准数据，自动补传
                    Task { await CalibrationService.shared.retryPending() }
                    store.load()
                    // 审核通过的用户投稿，合并进地图
                    Task {
                        await CommunityService.shared.loadApprovedScenes()
                        store.setCommunity(CommunityService.shared.approvedScenes)
                    }
                    location.start()
                    #if DEBUG
                    // UI 测试 / 演示：通过环境变量把位置固定在某个坐标
                    let env = ProcessInfo.processInfo.environment
                    if let lat = env["SEICHI_SIM_LAT"].flatMap(Double.init),
                       let lon = env["SEICHI_SIM_LON"].flatMap(Double.init) {
                        location.simulate(at: GeoPoint(latitude: lat, longitude: lon))
                    }
                    location.simulatedHeading = env["SEICHI_SIM_HEADING"].flatMap(Double.init)
                    // 多语言截图巡检：启动后直接打开某个名场面的详情页
                    if let id = env["SEICHI_OPEN_SPOT"] {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { store.requestedSpotID = id }
                    }
                    #endif
                    NotificationService.shared.requestAuthorization()
                    NotificationService.shared.onOpenSpot = { id in store.requestedSpotID = id }
                    NotificationService.shared.onResumeJourney = { id, purpose in
                        store.requestedJourneyPurpose = purpose
                        store.requestedSpotID = id
                    }
                }
                // 每次回到前台都重新启动定位：App 可能曾被地理围栏在后台唤醒，那时的定位不会自动恢复
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { location.start() }
                }
                .onChange(of: location.lastLocation, initial: true) { _, newValue in
                    guard let loc = newValue else { return }
                    store.update(userLocation: loc)
                    location.monitorNearestRegions(store.nearby.map(\.spot))
                }
        }
    }
}
