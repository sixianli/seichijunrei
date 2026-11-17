import Foundation

/// 按作品名（动画 / 电影 / 电视剧）搜索名场面。
///
/// 支持：中文 / 日文 / 英文 / 罗马字别名，大小写、全角半角、平假名与片假名互通，
/// 忽略空格和「。☆！△」之类的装饰符号（例如输入「君の名は」也能搜到「君の名は。」）。
public enum SpotSearch {
    /// 一部作品及其匹配到的名场面
    public struct WorkMatch: Identifiable, Hashable, Sendable {
        public var work: String
        public var workLocalized: String?
        public var mediaType: MediaType
        public var spots: [Spot]
        /// 相关度，越大越靠前
        public var score: Int
        public var id: String { work }
    }

    /// 把文本归一化，便于宽松匹配。
    public static func normalize(_ text: String) -> String {
        let folded = text.folding(options: [.caseInsensitive, .widthInsensitive], locale: nil)
        var out = String.UnicodeScalarView()
        for scalar in folded.unicodeScalars {
            var v = scalar.value
            // 片假名 → 平假名（ァ..ヶ）
            if (0x30A1...0x30F6).contains(v) { v -= 0x60 }
            guard let u = Unicode.Scalar(v) else { continue }
            let p = u.properties
            if p.isAlphabetic || p.numericType != nil || u == "ー" {
                out.append(u)
            }
        }
        return String(out)
    }

    /// 单个字段与关键词的匹配分。
    static func fieldScore(_ field: String, query q: String, exact: Int, prefix: Int, contains: Int) -> Int {
        let f = normalize(field)
        guard !f.isEmpty, !q.isEmpty else { return 0 }
        if f == q { return exact }
        if f.hasPrefix(q) { return prefix }
        if f.contains(q) { return contains }
        return 0
    }

    /// 作品名层面的匹配分（作品名、中文名、别名）。
    static func workScore(_ spot: Spot, query q: String) -> Int {
        ([spot.work] + [spot.workLocalized].compactMap { $0 } + spot.aliases)
            .map { fieldScore($0, query: q, exact: 100, prefix: 80, contains: 60) }
            .max() ?? 0
    }

    /// 名场面层面的匹配分（场景标题、地点名）。
    static func sceneScore(_ spot: Spot, query q: String) -> Int {
        [spot.sceneTitle, spot.placeName]
            .map { fieldScore($0, query: q, exact: 50, prefix: 40, contains: 30) }
            .max() ?? 0
    }

    /// - Parameters:
    ///   - query: 关键词；为空时返回全部作品（按数据顺序）
    ///   - mediaType: 只搜索某种类型，nil 表示全部
    public static func search(_ query: String, in spots: [Spot],
                              mediaType: MediaType? = nil) -> [WorkMatch] {
        let candidates = spots.filter { mediaType == nil || $0.mediaType == mediaType }
        let q = normalize(query)

        // 按作品分组，保持数据中的出现顺序
        var order: [String] = []
        var groups: [String: [Spot]] = [:]
        for s in candidates {
            if groups[s.work] == nil { order.append(s.work) }
            groups[s.work, default: []].append(s)
        }

        var results: [WorkMatch] = []
        for (index, work) in order.enumerated() {
            let workSpots = groups[work]!
            let first = workSpots[0]
            if q.isEmpty {
                results.append(WorkMatch(work: work, workLocalized: first.workLocalized,
                                         mediaType: first.mediaType, spots: workSpots,
                                         score: -index))
                continue
            }
            let ws = workSpots.map { workScore($0, query: q) }.max() ?? 0
            if ws > 0 {
                // 作品名匹配：返回这部作品的全部名场面
                results.append(WorkMatch(work: work, workLocalized: first.workLocalized,
                                         mediaType: first.mediaType, spots: workSpots, score: ws))
            } else {
                // 只匹配到具体场景/地点：只返回匹配到的那几个
                let scored = workSpots.map { ($0, sceneScore($0, query: q)) }.filter { $0.1 > 0 }
                if let best = scored.map(\.1).max() {
                    results.append(WorkMatch(work: work, workLocalized: first.workLocalized,
                                             mediaType: first.mediaType, spots: scored.map(\.0), score: best))
                }
            }
        }
        return results.sorted { $0.score != $1.score ? $0.score > $1.score : $0.work < $1.work }
    }

    /// 计算一组坐标的外接范围（用于地图缩放到搜索结果）。
    public static func boundingBox(of spots: [Spot]) -> (minLat: Double, minLon: Double,
                                                         maxLat: Double, maxLon: Double)? {
        guard let f = spots.first else { return nil }
        var box = (minLat: f.coordinate.latitude, minLon: f.coordinate.longitude,
                   maxLat: f.coordinate.latitude, maxLon: f.coordinate.longitude)
        for s in spots.dropFirst() {
            box.minLat = min(box.minLat, s.coordinate.latitude)
            box.maxLat = max(box.maxLat, s.coordinate.latitude)
            box.minLon = min(box.minLon, s.coordinate.longitude)
            box.maxLon = max(box.maxLon, s.coordinate.longitude)
        }
        return box
    }
}
