import Foundation

/// 一次“巡礼达成”：用户在机位上对准了名场面。
public struct PilgrimageRecord: Codable, Equatable, Identifiable, Sendable {
    public var spotID: String
    /// 达成时间
    public var date: Date
    /// 达成时摄像头朝向（真北，度）
    public var heading: Double?
    /// 达成时的位置
    public var latitude: Double?
    public var longitude: Double?
    /// 现场照片（App 本地文件名）
    public var photoFileName: String?

    public var id: String { spotID }

    public init(spotID: String, date: Date, heading: Double? = nil, latitude: Double? = nil,
                longitude: Double? = nil, photoFileName: String? = nil) {
        self.spotID = spotID; self.date = date; self.heading = heading
        self.latitude = latitude; self.longitude = longitude; self.photoFileName = photoFileName
    }
}

/// 巡礼足迹：每个圣地保留第一次达成的时间，照片取最近拍的一张。
public struct PilgrimageLog: Codable, Equatable, Sendable {
    public private(set) var records: [PilgrimageRecord] = []

    public init(records: [PilgrimageRecord] = []) { self.records = records }

    public func record(for spotID: String) -> PilgrimageRecord? { records.first { $0.spotID == spotID } }

    /// 记录一次达成。已达成过的圣地保留最初的日期（“第一次来到这里”的那天），但补充缺失的信息。
    public mutating func markCompleted(_ new: PilgrimageRecord) {
        if let i = records.firstIndex(where: { $0.spotID == new.spotID }) {
            var r = records[i]
            r.heading = r.heading ?? new.heading
            r.latitude = r.latitude ?? new.latitude
            r.longitude = r.longitude ?? new.longitude
            if let p = new.photoFileName { r.photoFileName = p }
            records[i] = r
        } else {
            records.append(new)
        }
    }

    /// 给已达成的圣地设置/更换现场照片。返回被替换掉的旧文件名（便于删除）。
    @discardableResult
    public mutating func setPhoto(_ fileName: String, for spotID: String) -> String? {
        guard let i = records.firstIndex(where: { $0.spotID == spotID }) else { return nil }
        let old = records[i].photoFileName
        records[i].photoFileName = fileName
        return old == fileName ? nil : old
    }

    public var completedCount: Int { records.count }
}

public enum ShareFormatting {
    /// 把作品名变成可用的话题标签：去掉空格和符号（# 后只保留字母、数字、假名、汉字）。
    public static func hashtag(_ text: String) -> String? {
        let kept = text.unicodeScalars.filter { $0.properties.isAlphabetic || $0.properties.numericType != nil || $0 == "_" }
        let tag = String(String.UnicodeScalarView(kept))
        return tag.isEmpty ? nil : "#" + tag
    }

    /// 生成去重后的话题标签列表
    public static func hashtags(_ texts: [String?]) -> [String] {
        var seen = Set<String>()
        return texts.compactMap { $0.flatMap(hashtag) }.filter { seen.insert($0.lowercased()).inserted }
    }

    /// 坐标显示：35.6854°N 139.7227°E
    public static func coordinate(latitude: Double, longitude: Double) -> String {
        String(format: "%.4f°%@ %.4f°%@", abs(latitude), latitude >= 0 ? "N" : "S",
               abs(longitude), longitude >= 0 ? "E" : "W")
    }
}
