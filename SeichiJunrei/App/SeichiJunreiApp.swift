import SwiftUI
import SeichiCore

@main
struct SeichiJunreiApp: App {
    @State private var store = SpotStore()
    @State private var location = LocationService()
    @State private var storeKit = StoreService.shared
    @State private var pilgrimage = PilgrimageStore.shared
    @State private var language = AppLanguage.shared

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
                    #endif
                    NotificationService.shared.requestAuthorization()
                    NotificationService.shared.onOpenSpot = { id in store.requestedSpotID = id }
                }
                .onChange(of: location.lastLocation) { _, newValue in
                    guard let loc = newValue else { return }
                    store.update(userLocation: loc)
                    location.monitorNearestRegions(store.nearby.map(\.spot))
                }
        }
    }
}
