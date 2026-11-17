import Foundation

/// 用户在现场校准机位时采集的一次读数。
public struct CalibrationReading: Codable, Equatable, Sendable {
    public var latitude: Double
    public var longitude: Double
    /// GPS 水平精度（米），负数表示无效
    public var horizontalAccuracy: Double
    /// 摄像头朝向（真北，度），nil 表示指南针不可用
    public var heading: Double?
    /// 朝向误差（度），负数表示未知
    public var headingAccuracy: Double
    /// 摄像头俯仰角（度）
    public var pitch: Double?
    /// 定位是否来自模拟（Xcode 模拟位置、虚拟定位工具等，`CLLocationSourceInformation`）
    public var isSimulated: Bool?

    public init(latitude: Double, longitude: Double, horizontalAccuracy: Double,
                heading: Double?, headingAccuracy: Double, pitch: Double?, isSimulated: Bool = false) {
        self.latitude = latitude; self.longitude = longitude
        self.horizontalAccuracy = horizontalAccuracy
        self.heading = heading; self.headingAccuracy = headingAccuracy; self.pitch = pitch
        self.isSimulated = isSimulated
    }

    public var point: GeoPoint { GeoPoint(latitude: latitude, longitude: longitude) }
}

/// 读数质量问题
public enum CalibrationIssue: Equatable, Sendable {
    /// GPS 精度不足（米）
    case poorGPS(Double)
    /// 指南针精度不足（度）
    case poorCompass(Double)
    /// 指南针不可用
    case noHeading
    /// 离数据中现有机位较远（米）。现有坐标本身可能不准，所以只要求写备注说明，不直接阻止
    case farFromListed(Double)
    /// 离现有机位太远（米）：不在现场，不能提交（防止在家里随手提交）
    case tooFar(Double)
    /// 定位是模拟出来的，不能提交
    case simulatedLocation
}

public enum CalibrationQuality {
    public static let maxGPSAccuracy: Double = 15        // 米
    public static let maxHeadingAccuracy: Double = 20    // 度
    public static let farDistance: Double = 300          // 米：超过需要写备注
    public static let maxSubmitDistance: Double = 2_000  // 米：超过直接不能提交
    public static let maxSubmitGPSAccuracy: Double = 50  // 米：GPS 太差不能提交

    public static func issues(for r: CalibrationReading, listed: GeoPoint) -> [CalibrationIssue] {
        var result: [CalibrationIssue] = []
        if r.isSimulated == true { result.append(.simulatedLocation) }
        if r.horizontalAccuracy < 0 || r.horizontalAccuracy > maxGPSAccuracy {
            result.append(.poorGPS(r.horizontalAccuracy))
        }
        if r.heading == nil {
            result.append(.noHeading)
        } else if r.headingAccuracy < 0 || r.headingAccuracy > maxHeadingAccuracy {
            result.append(.poorCompass(r.headingAccuracy))
        }
        let d = GeoMath.distance(from: r.point, to: listed)
        if d > maxSubmitDistance { result.append(.tooFar(d)) }
        else if d > farDistance { result.append(.farFromListed(d)) }
        return result
    }

    /// 是否允许提交。规则：
    /// - 必须有朝向、GPS 有效且精度在 50 米以内，不能是模拟定位；
    /// - 离现有机位 2 km 以上：说明人不在现场，不能提交；
    /// - 300 m～2 km：现有坐标可能本身不准，允许提交，但必须写备注说明。
    /// 提交上来的数据也不会直接生效，见 `CalibrationConsensus`。
    public static func canSubmit(_ r: CalibrationReading, listed: GeoPoint, note: String = "") -> Bool {
        guard r.heading != nil, r.horizontalAccuracy >= 0, r.horizontalAccuracy <= maxSubmitGPSAccuracy,
              r.isSimulated != true else { return false }
        let d = GeoMath.distance(from: r.point, to: listed)
        if d > maxSubmitDistance { return false }
        if d > farDistance { return !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return true
    }

    /// 是否属于高质量读数（GPS 与指南针都在阈值内）——用于界面上的“质量良好”提示
    public static func isGood(_ r: CalibrationReading, listed: GeoPoint) -> Bool {
        issues(for: r, listed: listed).allSatisfy { if case .farFromListed = $0 { return true } else { return false } }
    }
}

/// 一次提交（App 发送到 CloudKit 的内容）
public struct CalibrationSubmission: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var spotID: String
    public var reading: CalibrationReading
    public var note: String
    public var appVersion: String
    public var locale: String
    public var createdAt: Date

    public init(id: String = UUID().uuidString, spotID: String, reading: CalibrationReading, note: String,
                appVersion: String, locale: String, createdAt: Date = Date()) {
        self.id = id; self.spotID = spotID; self.reading = reading
        self.note = String(note.prefix(500)); self.appVersion = appVersion
        self.locale = locale; self.createdAt = createdAt
    }
}

/// 把多位用户的校准合并成新机位：单个人的提交不会直接生效。
///
/// 规则：只采用高质量读数；按位置聚类（半径 `radius`），同一个 iCloud 用户在一个机位只算一票；
/// 最大的一簇至少有 `minUsers` 个不同用户、且朝向大致一致时，取中位数作为新机位。
public enum CalibrationConsensus {
    public struct Vote: Sendable {
        public var userID: String
        public var reading: CalibrationReading
        public init(userID: String, reading: CalibrationReading) { self.userID = userID; self.reading = reading }
    }

    public struct Result: Equatable, Sendable {
        public var point: GeoPoint
        public var heading: Double
        public var pitch: Double?
        public var users: Int
    }

    public static func merge(_ votes: [Vote], listed: GeoPoint, minUsers: Int = 3, radius: Double = 25,
                             maxHeadingSpread: Double = 25) -> Result? {
        // 1. 只要高质量读数，每个用户只取最后一次
        var latest: [String: CalibrationReading] = [:]
        for v in votes where CalibrationQuality.isGood(v.reading, listed: listed) && v.reading.isSimulated != true {
            latest[v.userID] = v.reading
        }
        let readings = Array(latest.values)
        guard readings.count >= minUsers else { return nil }
        // 2. 找邻居最多的读数作为中心，取半径内的一簇
        var best: [CalibrationReading] = []
        for c in readings {
            let cluster = readings.filter { GeoMath.distance(from: $0.point, to: c.point) <= radius }
            if cluster.count > best.count { best = cluster }
        }
        guard best.count >= minUsers else { return nil }
        // 3. 朝向要一致
        let headings = best.compactMap(\.heading)
        let mean = GeoMath.circularMean(headings) ?? 0
        let agreeing = best.filter { r in r.heading.map { abs(GeoMath.signedDelta(from: mean, to: $0)) <= maxHeadingSpread } ?? false }
        guard agreeing.count >= minUsers else { return nil }
        func median(_ xs: [Double]) -> Double {
            let s = xs.sorted(); return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
        }
        let pitches = agreeing.compactMap(\.pitch)
        return Result(point: GeoPoint(latitude: median(agreeing.map(\.latitude)), longitude: median(agreeing.map(\.longitude))),
                      heading: GeoMath.normalize(GeoMath.circularMean(agreeing.compactMap(\.heading)) ?? mean),
                      pitch: pitches.isEmpty ? nil : median(pitches), users: agreeing.count)
    }
}
