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

/// “网上搜这一幕”：按用户所在国家选搜索引擎（中国大陆用不了 Google），
/// 搜索词用和搜索引擎匹配的一种语言：作品名 + 粉丝常用的地点 / 场景关键词 + 巡礼词
public enum SceneImageSearch {
    public enum Engine: String, Sendable { case google, baidu, naver, yandex }

    /// country：ISO 国家代码（定位所在国家，没有定位时用手机的地区设置）
    public static func engine(country: String?) -> Engine {
        switch country?.uppercased() {
        case "CN": return .baidu
        case "KR": return .naver
        case "RU", "BY", "KZ": return .yandex
        default: return .google
        }
    }

    /// 地点名去掉括号里的城市说明：“須賀神社 男坂（東京・四谷）” → “須賀神社 男坂”
    public static func trimmedPlace(_ place: String) -> String {
        place.components(separatedBy: CharacterSet(charactersIn: "（(")).first?
            .trimmingCharacters(in: .whitespaces) ?? place
    }

    /// 一条现成的搜索：实际去搜的词 + 给用户看的说明（用户自己的语言）+ 用哪个搜索引擎
    public struct Option: Equatable, Sendable {
        /// 实际去搜的词（搜索引擎的语言，比如 Google 用日文）
        public var query: String
        public var engine: Engine
        /// 用户界面语言的版本，让看不懂日文的人也知道这条搜的是什么；和 query 同语言时为 nil
        public var label: String?
        public init(query: String, engine: Engine, label: String? = nil) {
            self.query = query; self.engine = engine; self.label = label
        }
    }

    /// 某一种语言的搜索素材：作品名 + 粉丝常用的地点 / 场景关键词（各语言按下标一一对应）+ 地名（关键词缺失时兜底）
    public struct Words: Equatable, Sendable {
        public var language: String
        public var work: String
        public var terms: [String]
        public var place: String?
        public init(language: String, work: String, terms: [String], place: String?) {
            self.language = language; self.work = work; self.terms = terms; self.place = place
        }

        var keywords: [String] {
            let k = terms.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            if k.isEmpty, let p = place { return [SceneImageSearch.trimmedPlace(p)] }
            return k
        }
    }

    /// 和搜索引擎最搭的语言：百度用简体中文，Naver 用韩语，Google 用日语（原作和巡礼对比图日文最多）
    public static func language(for engine: Engine, userLanguage: String) -> String {
        switch engine {
        case .baidu: return "zh-Hans"
        case .naver: return "ko"
        case .google, .yandex: return "ja"
        }
    }

    static func pilgrimageWord(_ language: String) -> String {
        switch language {
        case "ja": return "聖地巡礼 比較"
        case "zh-Hans": return "圣地巡礼 对比"
        case "zh-Hant": return "聖地巡禮 對比"
        case "ko": return "성지순례 비교"
        default: return "anime pilgrimage comparison"
        }
    }

    static func pilgrimageLabel(_ language: String) -> String {
        switch language {
        case "ja": return "聖地巡礼の比較"
        case "zh-Hans": return "圣地巡礼对比"
        case "zh-Hant": return "聖地巡禮對比"
        case "ko": return "성지순례 비교"
        default: return "pilgrimage comparison"
        }
    }

    /// 几条现成的搜索：用 search 的语言去搜；display（用户界面语言）不同时，每条都配上用户看得懂的说明。
    /// 关键词组合：[第 1 个 + 巡礼词]、[第 2 个]、[第 3 个]…、[第 1 + 第 2 个]，去重，最多 4 条
    public static func options(search: Words, display: Words?, engine: Engine) -> [Option] {
        let keys = search.keywords
        var combos: [(indices: [Int], pilgrimage: Bool)] = []
        if !keys.isEmpty { combos.append(([0], true)) }
        for i in keys.indices.dropFirst() { combos.append(([i], false)) }
        if keys.count >= 2 { combos.append(([0, 1], false)) }

        // 用户语言的关键词要和搜索语言一一对应，才能逐条翻译；对不上就不显示说明，免得说错
        let showLabel = display.map { $0.language != search.language } ?? false
        let shown = display?.keywords ?? []
        let canTranslate = showLabel && shown.count == keys.count

        var seen = Set<String>()
        var out: [Option] = []
        for c in combos {
            var q = ([search.work] + c.indices.map { keys[$0] }).joined(separator: " ")
            if c.pilgrimage { q += " " + pilgrimageWord(search.language) }
            guard seen.insert(q).inserted else { continue }
            var label: String?
            if let d = display, showLabel {
                var parts = [d.work]
                if canTranslate { parts += c.indices.map { shown[$0] } }
                if c.pilgrimage { parts.append(pilgrimageLabel(d.language)) }
                label = canTranslate ? parts.joined(separator: " · ") : nil
            }
            out.append(Option(query: q, engine: engine, label: label))
            if out.count == 4 { break }
        }
        return out
    }

    /// 只用一种语言（不配说明）
    public static func options(work: String, terms: [String], place: String?, language: String,
                               engine: Engine) -> [Option] {
        options(search: Words(language: language, work: work, terms: terms, place: place), display: nil, engine: engine)
    }

    public static func url(query: String, engine: Engine) -> URL? {
        var c: URLComponents?
        switch engine {
        case .baidu:
            c = URLComponents(string: "https://image.baidu.com/search/index")
            c?.queryItems = [URLQueryItem(name: "tn", value: "baiduimage"), URLQueryItem(name: "word", value: query)]
        case .naver:
            c = URLComponents(string: "https://search.naver.com/search.naver")
            c?.queryItems = [URLQueryItem(name: "where", value: "image"), URLQueryItem(name: "query", value: query)]
        case .yandex:
            c = URLComponents(string: "https://yandex.com/images/search")
            c?.queryItems = [URLQueryItem(name: "text", value: query)]
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
