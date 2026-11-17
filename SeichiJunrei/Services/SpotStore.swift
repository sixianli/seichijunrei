import Foundation
import CoreLocation
import Observation
import SeichiCore

/// 圣地数据源。读取 App 内置的 catalog.json（由 tools/catalog.py 从 data/ 生成），以后可以替换为远程 API。
@Observable
final class SpotStore {
    /// 当前界面语言下的名场面
    private(set) var spots: [Spot] = []
    /// 未本地化的原始数据（切换语言时重新本地化）
    @ObservationIgnored private var rawSpots: [Spot] = []
    @ObservationIgnored private var language: String?
    /// 按距离排序的附近圣地（全部，已排序）
    private(set) var nearby: [NearbySpot] = []
    private(set) var loadError: String?
    private(set) var userPoint: GeoPoint?
    /// 外部（如点击通知）请求打开的圣地 ID，由地图页消费
    var requestedSpotID: String?

    /// “附近”的范围（米）
    var searchRadius: Double = 30_000

    func load(bundle: Bundle = .main) {
        guard rawSpots.isEmpty else { return }
        do {
            guard let url = bundle.url(forResource: "catalog", withExtension: "json") else {
                loadError = L("data.missing"); return
            }
            rawSpots = try SpotCatalog.decode(Data(contentsOf: url))
            applyLanguage(AppLanguage.current)
        } catch {
            loadError = L("data.parseFailed", error.localizedDescription)
        }
    }

    /// 按界面语言替换文案（翻译保留，搜索时可匹配所有语言）
    func applyLanguage(_ code: String) {
        guard code != language || spots.isEmpty else { return }
        language = code
        spots = rawSpots.map { $0.localized(to: code) }
        if let p = userPoint { recompute(from: p) }
    }

    func update(userLocation: CLLocation) {
        let p = GeoPoint(latitude: userLocation.coordinate.latitude,
                         longitude: userLocation.coordinate.longitude)
        userPoint = p
        recompute(from: p)
    }

    private func recompute(from p: GeoPoint) {
        nearby = NearbySearch.nearby(spots, from: p)
    }

    /// 半径内的圣地
    var nearbyWithinRadius: [NearbySpot] { nearby.filter { $0.distance <= searchRadius } }

    /// 把任意一组圣地转成带距离的列表：有定位时按距离排序，否则保持原顺序（距离为 ∞）。
    func items(for spots: [Spot]) -> [NearbySpot] {
        if let p = userPoint { return NearbySearch.nearby(spots, from: p) }
        return spots.map { NearbySpot(spot: $0, distance: .infinity, bearing: 0) }
    }

    func nearbyInfo(for spot: Spot) -> NearbySpot? {
        nearby.first { $0.id == spot.id }
    }
}
