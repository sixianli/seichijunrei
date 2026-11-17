import Foundation

/// 一个与平台无关的经纬度坐标（不依赖 CoreLocation，便于在任何平台上测试）。
public struct GeoPoint: Codable, Hashable, Sendable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

public enum GeoMath {
    /// WGS84 平均地球半径（米）
    public static let earthRadius: Double = 6_371_008.8

    @inlinable public static func radians(_ degrees: Double) -> Double { degrees * .pi / 180 }
    @inlinable public static func degrees(_ radians: Double) -> Double { radians * 180 / .pi }

    /// 半正矢（haversine）公式计算两点之间的大圆距离（米）。
    public static func distance(from a: GeoPoint, to b: GeoPoint) -> Double {
        let φ1 = radians(a.latitude), φ2 = radians(b.latitude)
        let Δφ = φ2 - φ1
        let Δλ = radians(b.longitude - a.longitude)
        let h = sin(Δφ / 2) * sin(Δφ / 2) + cos(φ1) * cos(φ2) * sin(Δλ / 2) * sin(Δλ / 2)
        return 2 * earthRadius * asin(min(1, sqrt(h)))
    }

    /// 从 a 指向 b 的初始方位角（相对正北，顺时针，0..<360°）。
    public static func bearing(from a: GeoPoint, to b: GeoPoint) -> Double {
        let φ1 = radians(a.latitude), φ2 = radians(b.latitude)
        let Δλ = radians(b.longitude - a.longitude)
        let y = sin(Δλ) * cos(φ2)
        let x = cos(φ1) * sin(φ2) - sin(φ1) * cos(φ2) * cos(Δλ)
        return normalize(degrees(atan2(y, x)))
    }

    /// 把任意角度归一化到 0..<360。
    public static func normalize(_ angle: Double) -> Double {
        let r = angle.truncatingRemainder(dividingBy: 360)
        let n = r < 0 ? r + 360 : r
        // 极小的负数加 360 后会被舍入成 360，保证结果严格落在 0..<360
        return n >= 360 ? 0 : n
    }

    /// 从 `current` 转到 `target` 所需的最小有符号角度，范围 (-180, 180]。
    /// 正数 = 向右（顺时针）转，负数 = 向左（逆时针）转。
    public static func signedDelta(from current: Double, to target: Double) -> Double {
        let d = normalize(target - current)
        return d > 180 ? d - 360 : d
    }

    /// 角度的圆周平均（用于平滑罗盘读数，避免 359°/1° 之间跳变）。
    public static func circularMean(_ angles: [Double]) -> Double? {
        guard !angles.isEmpty else { return nil }
        let s = angles.reduce(0) { $0 + sin(radians($1)) }
        let c = angles.reduce(0) { $0 + cos(radians($1)) }
        if abs(s) < 1e-12 && abs(c) < 1e-12 { return nil }
        return normalize(degrees(atan2(s, c)))
    }

    /// 八方位：0 北、1 东北、2 东、3 东南、4 南、5 西南、6 西、7 西北。
    /// 只返回序号，具体文字由 App 层按界面语言本地化。
    public static func compassIndex(_ bearing: Double) -> Int {
        Int((normalize(bearing) + 22.5) / 45) % 8
    }
}
