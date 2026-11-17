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

    public init(latitude: Double, longitude: Double, horizontalAccuracy: Double,
                heading: Double?, headingAccuracy: Double, pitch: Double?) {
        self.latitude = latitude; self.longitude = longitude
        self.horizontalAccuracy = horizontalAccuracy
        self.heading = heading; self.headingAccuracy = headingAccuracy; self.pitch = pitch
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
    /// 离数据中现有机位较远（米）。现有坐标本身可能不准，所以只是提醒，不阻止提交
    case farFromListed(Double)
}

public enum CalibrationQuality {
    public static let maxGPSAccuracy: Double = 15        // 米
    public static let maxHeadingAccuracy: Double = 20    // 度
    public static let farDistance: Double = 300          // 米

    public static func issues(for r: CalibrationReading, listed: GeoPoint) -> [CalibrationIssue] {
        var result: [CalibrationIssue] = []
        if r.horizontalAccuracy < 0 || r.horizontalAccuracy > maxGPSAccuracy {
            result.append(.poorGPS(r.horizontalAccuracy))
        }
        if r.heading == nil {
            result.append(.noHeading)
        } else if r.headingAccuracy < 0 || r.headingAccuracy > maxHeadingAccuracy {
            result.append(.poorCompass(r.headingAccuracy))
        }
        let d = GeoMath.distance(from: r.point, to: listed)
        if d > farDistance { result.append(.farFromListed(d)) }
        return result
    }

    /// 是否满足提交的最低要求：有朝向、GPS 有效
    public static func canSubmit(_ r: CalibrationReading) -> Bool {
        r.heading != nil && r.horizontalAccuracy >= 0
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
