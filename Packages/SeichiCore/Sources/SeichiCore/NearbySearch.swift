import Foundation

/// 带距离/方位信息的附近圣地。
public struct NearbySpot: Identifiable, Hashable, Sendable {
    public var spot: Spot
    /// 用户到圣地的距离（米）
    public var distance: Double
    /// 从用户指向圣地的方位角（度）
    public var bearing: Double
    public var id: String { spot.id }

    public init(spot: Spot, distance: Double, bearing: Double) {
        self.spot = spot; self.distance = distance; self.bearing = bearing
    }

    /// 用户是否已站在名场面镜头位置附近。`accuracy` 为 GPS 水平精度，用于适度放宽判定。
    public func hasArrived(accuracy: Double = 0) -> Bool {
        distance <= spot.arrivalRadius + min(max(accuracy, 0), 20)
    }
}

public enum NearbySearch {
    /// 按距离排序返回 `radius` 米以内的圣地（最多 `limit` 个）。
    public static func nearby(_ spots: [Spot], from user: GeoPoint,
                              within radius: Double = .infinity, limit: Int = .max) -> [NearbySpot] {
        spots
            .map { NearbySpot(spot: $0,
                              distance: GeoMath.distance(from: user, to: $0.coordinate),
                              bearing: GeoMath.bearing(from: user, to: $0.coordinate)) }
            .filter { $0.distance <= radius }
            .sorted { $0.distance < $1.distance }
            .prefix(limit)
            .map { $0 }
    }

    /// 人性化的距离文本。
    public static func formatDistance(_ meters: Double) -> String {
        if meters < 1000 { return "\(Int(meters.rounded())) m" }
        if meters < 10_000 { return String(format: "%.1f km", meters / 1000) }
        return "\(Int((meters / 1000).rounded())) km"
    }
}
