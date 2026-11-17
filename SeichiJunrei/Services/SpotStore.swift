import Foundation
import CoreLocation
import Observation
import SeichiCore

/// 圣地数据源。目前读取 App 内置的 spots.json，以后可以替换为远程 API。
@Observable
final class SpotStore {
    private(set) var spots: [Spot] = []
    /// 按距离排序的附近圣地（全部，已排序）
    private(set) var nearby: [NearbySpot] = []
    private(set) var loadError: String?
    private(set) var userPoint: GeoPoint?
    /// 外部（如点击通知）请求打开的圣地 ID，由地图页消费
    var requestedSpotID: String?

    /// “附近”的范围（米）
    var searchRadius: Double = 30_000

    func load(bundle: Bundle = .main) {
        guard spots.isEmpty else { return }
        do {
            guard let url = bundle.url(forResource: "spots", withExtension: "json") else {
                loadError = L("data.missing"); return
            }
            // 按当前界面语言替换文案（翻译保留，搜索时可匹配所有语言）
            let language = AppLanguage.current
            spots = try SpotCatalog.decode(Data(contentsOf: url)).map { $0.localized(to: language) }
            if let p = userPoint { recompute(from: p) }
        } catch {
            loadError = L("data.parseFailed", error.localizedDescription)
        }
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
