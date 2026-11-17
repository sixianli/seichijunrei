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

    /// “附近”的范围（米）
    var searchRadius: Double = 30_000

    func load(bundle: Bundle = .main) {
        guard spots.isEmpty else { return }
        do {
            guard let url = bundle.url(forResource: "spots", withExtension: "json") else {
                loadError = "找不到 spots.json"; return
            }
            spots = try SpotCatalog.decode(Data(contentsOf: url))
            if let p = userPoint { recompute(from: p) }
        } catch {
            loadError = "圣地数据解析失败：\(error.localizedDescription)"
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

    func nearbyInfo(for spot: Spot) -> NearbySpot? {
        nearby.first { $0.id == spot.id }
    }
}
