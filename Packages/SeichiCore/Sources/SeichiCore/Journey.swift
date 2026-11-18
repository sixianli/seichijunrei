import Foundation

/// “带我去复现”的三段：远处交给导航 App，近处 App 自己带路，到了开相机。
public enum JourneyStage: String, Sendable, Equatable {
    /// 超过 nearEnter：用导航 App（Google / Apple / 高德 / 百度）过去
    case far
    /// nearEnter 以内：实时指南针 + 步行小地图
    case near
    /// 到达机位半径以内：相机取景、指引转身对准
    case arrived

    /// 走近到这个距离切到“近”
    public static let nearEnter: Double = 400
    /// 走远超过这个距离才切回“远”（缓冲，避免定位抖动来回切换）
    public static let nearExit: Double = 500
    /// 离开机位半径的这个倍数才退出“到了”
    public static let arrivedExitFactor: Double = 1.6

    /// 根据当前阶段和最新距离算下一阶段（带缓冲）
    public static func next(from current: JourneyStage?, distance: Double, arrivalRadius: Double) -> JourneyStage {
        guard distance.isFinite else { return current ?? .far }
        switch current {
        case .arrived?:
            if distance <= arrivalRadius * arrivedExitFactor { return .arrived }
            return distance <= nearExit ? .near : .far
        case .near?:
            if distance <= arrivalRadius { return .arrived }
            return distance <= nearExit ? .near : .far
        case .far?, nil:
            if distance <= arrivalRadius { return .arrived }
            return distance <= nearEnter ? .near : .far
        }
    }

    /// 远处导航默认的出行方式：2 km 以内步行，再远用公共交通
    public static func prefersWalking(distance: Double) -> Bool { distance <= 2000 }
}

/// 以用户为参照的方向：正前方 / 右前方 / 右边 / 右后方 / 正后方 / 左后方 / 左边 / 左前方
public enum RelativeDirection: Int, CaseIterable, Sendable {
    case ahead, aheadRight, right, behindRight, behind, behindLeft, left, aheadLeft

    /// bearing：目标方位角；heading：手机朝向（都是正北顺时针的度数）
    public static func of(bearing: Double, heading: Double) -> RelativeDirection {
        let delta = GeoMath.normalize(bearing - heading)
        return RelativeDirection(rawValue: Int(((delta + 22.5) / 45).rounded(.down)) % 8) ?? .ahead
    }
}

/// 最佳月份分段：[11, 12, 1, 2] → [11…2]，[3, 4, 10, 11] → [3…4, 10…11]
public enum MonthRanges {
    public struct Range: Equatable, Sendable {
        public var start: Int
        public var end: Int
        public init(_ start: Int, _ end: Int) { self.start = start; self.end = end }
    }

    public static func ranges(_ months: [Int]) -> [Range] {
        let set = Set(months.filter { (1...12).contains($0) })
        guard !set.isEmpty else { return [] }
        if set.count == 12 { return [Range(1, 12)] }
        // 从一个“前一个月不在集合里”的月份开始，顺着往后连，处理跨年
        var out: [Range] = []
        let starts = (1...12).filter { set.contains($0) && !set.contains($0 == 1 ? 12 : $0 - 1) }
        for s in starts {
            var e = s
            while set.contains(e == 12 ? 1 : e + 1) { e = e == 12 ? 1 : e + 1 }
            out.append(Range(s, e))
        }
        return out.sorted { $0.start < $1.start }
    }
}

/// “网上搜这一幕”：按用户语言选搜索引擎，搜索词同时带日语原名和当前语言的名字
public enum SceneImageSearch {
    public enum Engine: String, Sendable { case google, baidu, naver }

    public static func engine(for language: String) -> Engine {
        switch language {
        case "zh-Hans": return .baidu
        case "ko": return .naver
        default: return .google
        }
    }

    /// 地点名去掉括号里的城市说明：“須賀神社 男坂（東京・四谷）” → “須賀神社 男坂”
    public static func trimmedPlace(_ place: String) -> String {
        place.components(separatedBy: CharacterSet(charactersIn: "（(")).first?
            .trimmingCharacters(in: .whitespaces) ?? place
    }

    /// 日语关键词在前（原作资料最多），后面接当前语言的作品名和地点名；重复的词去掉
    public static func query(originalWork: String, japanesePlace: String?, localizedWork: String?,
                             localizedPlace: String?, language: String) -> String {
        var parts = [originalWork]
        if let p = japanesePlace { parts.append(trimmedPlace(p)) }
        parts.append(language == "ja" ? "シーン" : "アニメ シーン")
        if language != "ja" {
            if let w = localizedWork, !w.isEmpty { parts.append(w) }
            if let p = localizedPlace { parts.append(trimmedPlace(p)) }
            parts.append(sceneWord(language))
        }
        var seen = Set<String>()
        return parts.filter { !$0.isEmpty && seen.insert($0).inserted }.joined(separator: " ")
    }

    static func sceneWord(_ language: String) -> String {
        switch language {
        case "zh-Hans": return "名场面"
        case "zh-Hant": return "名場面"
        case "ko": return "명장면"
        default: return "scene"
        }
    }

    public static func url(query: String, language: String) -> URL? {
        var c: URLComponents?
        switch engine(for: language) {
        case .baidu:
            c = URLComponents(string: "https://image.baidu.com/search/index")
            c?.queryItems = [URLQueryItem(name: "tn", value: "baiduimage"), URLQueryItem(name: "word", value: query)]
        case .naver:
            c = URLComponents(string: "https://search.naver.com/search.naver")
            c?.queryItems = [URLQueryItem(name: "where", value: "image"), URLQueryItem(name: "query", value: query)]
        case .google:
            c = URLComponents(string: "https://www.google.com/search")
            c?.queryItems = [URLQueryItem(name: "tbm", value: "isch"), URLQueryItem(name: "q", value: query)]
        }
        return c?.url
    }
}

/// 上传照片的第一道关：照片必须带拍摄位置，并且在名场面附近拍的
public enum PhotoLocationCheck: Equatable, Sendable {
    case ok
    case missingLocation
    case tooFar(meters: Double)

    public static let maxDistance: Double = 1000

    public static func check(photoLocation: GeoPoint?, spot: GeoPoint) -> PhotoLocationCheck {
        guard let loc = photoLocation else { return .missingLocation }
        let d = GeoMath.distance(from: loc, to: spot)
        return d <= maxDistance ? .ok : .tooFar(meters: d)
    }
}
