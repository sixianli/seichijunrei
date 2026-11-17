import Foundation

/// 作品类型
public enum MediaType: String, Codable, CaseIterable, Sendable {
    case anime        // TV 动画
    case animeFilm    // 动画电影
    case film         // 真人电影
    case drama        // 电视剧

    /// 给用户看的大类：动画电影也归入“日漫”
    public var category: MediaCategory {
        switch self {
        case .anime, .animeFilm: return .anime
        case .drama: return .drama
        case .film: return .film
        }
    }
}

/// 筛选用的大类（日漫 / 日剧 / 日影）
public enum MediaCategory: String, CaseIterable, Sendable {
    case anime, drama, film
}

/// 真实地点的照片（Wikimedia Commons 等自由许可图片），展示时必须带署名。
public struct SpotPhoto: Codable, Hashable, Sendable {
    public var url: String
    public var pageURL: String?
    public var author: String
    public var license: String
    public var licenseURL: String?

    public init(url: String, pageURL: String? = nil, author: String, license: String, licenseURL: String? = nil) {
        self.url = url; self.pageURL = pageURL; self.author = author; self.license = license; self.licenseURL = licenseURL
    }
}

/// 某种语言下的圣地文案。字段为空表示沿用基础（简体中文）内容。
public struct SpotTranslation: Codable, Hashable, Sendable {
    /// 作品在该语言中的通用译名；空字符串表示不显示译名（如日语环境下原名即可）
    public var workLocalized: String?
    public var placeName: String?
    public var sceneTitle: String?
    public var episode: String?
    public var story: String?
    public var trivia: String?
    public var highlight: String?
    public var access: String?
    public var bestTime: String?
    public var creator: String?
    public var synopsis: String?

    public init(workLocalized: String? = nil, placeName: String? = nil, sceneTitle: String? = nil,
                episode: String? = nil, story: String? = nil, trivia: String? = nil,
                highlight: String? = nil, access: String? = nil, bestTime: String? = nil,
                creator: String? = nil, synopsis: String? = nil) {
        self.workLocalized = workLocalized; self.placeName = placeName; self.sceneTitle = sceneTitle
        self.episode = episode; self.story = story; self.trivia = trivia
        self.highlight = highlight; self.access = access; self.bestTime = bestTime
        self.creator = creator; self.synopsis = synopsis
    }
}

/// 一个圣地（动画/电影/电视剧名场面在现实中的取景地）。
public struct Spot: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    /// 作品 ID（同一作品的名场面共享）；旧数据没有时用作品原名
    public var workID: String
    /// 作品名（原文）
    public var work: String
    /// 作品名（中文，可选）
    public var workLocalized: String?
    /// 作品类型
    public var mediaType: MediaType
    /// 作品别名（英文名、罗马字、简称等），用于搜索
    public var aliases: [String]
    /// 地点名称
    public var placeName: String
    /// 名场面标题
    public var sceneTitle: String
    /// 出现集数 / 时间点，例如 "第1話 12:34"
    public var episode: String?
    /// 名场面在故事中的位置、剧情背景
    public var story: String
    /// 小知识 / 巡礼提示
    public var trivia: String?
    /// 用户应该站立的位置（名场面“镜头”所在的位置）
    public var coordinate: GeoPoint
    /// 名场面镜头朝向：相对正北顺时针的角度（0..<360）
    public var sceneHeading: Double
    /// 镜头俯仰角：正数为仰视，负数为俯视（度）。可选。
    public var scenePitch: Double?
    /// 判定“已进入场景”的半径（米）
    public var arrivalRadius: Double
    /// 场景截图（需要有授权的图片，本地资源名或远程 URL）
    public var sceneImage: String?
    /// 参考资料 / 出处链接
    public var sourceURL: String?
    /// 坐标与朝向是否经过实地校验
    public var verified: Bool
    /// 主题色（十六进制），用于卡片和地图标记
    public var tint: String?
    /// 其他语言的文案，键为语言代码（zh-Hant / ja / en / ko …）。基础字段为简体中文。
    public var translations: [String: SpotTranslation]

    // —— 详情页信息（新版数据才有） ——
    /// 为什么这一幕是名场面
    public var highlight: String?
    /// 交通方式
    public var access: String?
    /// 最佳到访时间
    public var bestTime: String?
    /// story 是否含剧透
    public var spoiler: Bool
    /// 真实地点照片
    public var photo: SpotPhoto?
    /// 作品首播 / 上映年份
    public var year: Int?
    /// 导演 / 制作公司 / 电视台
    public var creator: String?
    /// 作品简介（不剧透）
    public var synopsis: String?
    /// 作品官网
    public var officialURL: String?
    /// 作品出品国家（ISO 代码），nil 表示日本
    public var country: String?
    /// 同一作品里的第几个名场面（从 1 开始）；作品只有一个名场面时为 nil。由 SpotCatalog 计算，不参与编码
    public var sceneNumber: Int?
    /// 用户投稿（审核通过）的名场面：投稿人的匿名 ID；内置数据为 nil。不参与编码
    public var communityAuthorID: String?
    public var isCommunity: Bool { communityAuthorID != nil }

    public init(id: String, work: String, workLocalized: String? = nil,
                mediaType: MediaType = .anime, aliases: [String] = [], placeName: String,
                sceneTitle: String, episode: String? = nil, story: String, trivia: String? = nil,
                coordinate: GeoPoint, sceneHeading: Double, scenePitch: Double? = nil,
                arrivalRadius: Double = 25, sceneImage: String? = nil, sourceURL: String? = nil,
                verified: Bool = false, tint: String? = nil,
                translations: [String: SpotTranslation] = [:], workID: String? = nil,
                highlight: String? = nil, access: String? = nil, bestTime: String? = nil,
                spoiler: Bool = false, photo: SpotPhoto? = nil, year: Int? = nil,
                creator: String? = nil, synopsis: String? = nil, officialURL: String? = nil,
                country: String? = nil) {
        self.id = id; self.workID = workID ?? work; self.work = work; self.workLocalized = workLocalized
        self.mediaType = mediaType; self.aliases = aliases
        self.placeName = placeName; self.sceneTitle = sceneTitle; self.episode = episode
        self.story = story; self.trivia = trivia; self.coordinate = coordinate
        self.sceneHeading = sceneHeading; self.scenePitch = scenePitch
        self.arrivalRadius = arrivalRadius; self.sceneImage = sceneImage
        self.sourceURL = sourceURL; self.verified = verified; self.tint = tint
        self.translations = translations
        self.highlight = highlight; self.access = access; self.bestTime = bestTime
        self.spoiler = spoiler; self.photo = photo; self.year = year
        self.creator = creator; self.synopsis = synopsis; self.officialURL = officialURL
        self.country = country
    }

    enum CodingKeys: String, CodingKey {
        case id, work, workLocalized, mediaType, aliases, placeName, sceneTitle, episode, story, trivia
        case latitude, longitude, sceneHeading, scenePitch, arrivalRadius
        case sceneImage, sourceURL, verified, tint, translations
        case workID, highlight, access, bestTime, spoiler, photo, year, creator, synopsis, officialURL, country
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        work = try c.decode(String.self, forKey: .work)
        workID = try c.decodeIfPresent(String.self, forKey: .workID) ?? work
        workLocalized = try c.decodeIfPresent(String.self, forKey: .workLocalized)
        mediaType = try c.decodeIfPresent(MediaType.self, forKey: .mediaType) ?? .anime
        aliases = try c.decodeIfPresent([String].self, forKey: .aliases) ?? []
        placeName = try c.decode(String.self, forKey: .placeName)
        sceneTitle = try c.decode(String.self, forKey: .sceneTitle)
        episode = try c.decodeIfPresent(String.self, forKey: .episode)
        story = try c.decode(String.self, forKey: .story)
        trivia = try c.decodeIfPresent(String.self, forKey: .trivia)
        let lat = try c.decode(Double.self, forKey: .latitude)
        let lon = try c.decode(Double.self, forKey: .longitude)
        guard (-90...90).contains(lat), (-180...180).contains(lon) else {
            throw DecodingError.dataCorruptedError(forKey: .latitude, in: c,
                debugDescription: "Invalid coordinate \(lat),\(lon) for spot \(id)")
        }
        coordinate = GeoPoint(latitude: lat, longitude: lon)
        sceneHeading = GeoMath.normalize(try c.decode(Double.self, forKey: .sceneHeading))
        scenePitch = try c.decodeIfPresent(Double.self, forKey: .scenePitch)
        arrivalRadius = try c.decodeIfPresent(Double.self, forKey: .arrivalRadius) ?? 25
        sceneImage = try c.decodeIfPresent(String.self, forKey: .sceneImage)
        sourceURL = try c.decodeIfPresent(String.self, forKey: .sourceURL)
        verified = try c.decodeIfPresent(Bool.self, forKey: .verified) ?? false
        tint = try c.decodeIfPresent(String.self, forKey: .tint)
        translations = try c.decodeIfPresent([String: SpotTranslation].self, forKey: .translations) ?? [:]
        highlight = try c.decodeIfPresent(String.self, forKey: .highlight)
        access = try c.decodeIfPresent(String.self, forKey: .access)
        bestTime = try c.decodeIfPresent(String.self, forKey: .bestTime)
        spoiler = try c.decodeIfPresent(Bool.self, forKey: .spoiler) ?? false
        photo = try c.decodeIfPresent(SpotPhoto.self, forKey: .photo)
        year = try c.decodeIfPresent(Int.self, forKey: .year)
        creator = try c.decodeIfPresent(String.self, forKey: .creator)
        synopsis = try c.decodeIfPresent(String.self, forKey: .synopsis)
        officialURL = try c.decodeIfPresent(String.self, forKey: .officialURL)
        country = try c.decodeIfPresent(String.self, forKey: .country)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(work, forKey: .work)
        try c.encodeIfPresent(workLocalized, forKey: .workLocalized)
        try c.encode(mediaType, forKey: .mediaType)
        if !aliases.isEmpty { try c.encode(aliases, forKey: .aliases) }
        try c.encode(placeName, forKey: .placeName)
        try c.encode(sceneTitle, forKey: .sceneTitle)
        try c.encodeIfPresent(episode, forKey: .episode)
        try c.encode(story, forKey: .story)
        try c.encodeIfPresent(trivia, forKey: .trivia)
        try c.encode(coordinate.latitude, forKey: .latitude)
        try c.encode(coordinate.longitude, forKey: .longitude)
        try c.encode(sceneHeading, forKey: .sceneHeading)
        try c.encodeIfPresent(scenePitch, forKey: .scenePitch)
        try c.encode(arrivalRadius, forKey: .arrivalRadius)
        try c.encodeIfPresent(sceneImage, forKey: .sceneImage)
        try c.encodeIfPresent(sourceURL, forKey: .sourceURL)
        try c.encode(verified, forKey: .verified)
        try c.encodeIfPresent(tint, forKey: .tint)
        if !translations.isEmpty { try c.encode(translations, forKey: .translations) }
        try c.encode(workID, forKey: .workID)
        try c.encodeIfPresent(highlight, forKey: .highlight)
        try c.encodeIfPresent(access, forKey: .access)
        try c.encodeIfPresent(bestTime, forKey: .bestTime)
        if spoiler { try c.encode(spoiler, forKey: .spoiler) }
        try c.encodeIfPresent(photo, forKey: .photo)
        try c.encodeIfPresent(year, forKey: .year)
        try c.encodeIfPresent(creator, forKey: .creator)
        try c.encodeIfPresent(synopsis, forKey: .synopsis)
        try c.encodeIfPresent(officialURL, forKey: .officialURL)
        try c.encodeIfPresent(country, forKey: .country)
    }
}

public extension Spot {
    var displayWork: String { workLocalized.map { "\(work)（\($0)）" } ?? work }

    /// 基础内容所用的语言
    static let baseLanguage = "zh-Hans"

    /// 返回把文案替换为指定语言后的圣地（没有对应翻译的字段保留基础内容）。
    /// `translations` 会原样保留，以便搜索仍能匹配所有语言。
    func localized(to language: String?) -> Spot {
        guard let language, language != Self.baseLanguage,
              let t = translations[language] ?? translations[Self.languageFamily(language)] else { return self }
        var s = self
        if let w = t.workLocalized { s.workLocalized = w.isEmpty ? nil : w }
        if let v = t.placeName, !v.isEmpty { s.placeName = v }
        if let v = t.sceneTitle, !v.isEmpty { s.sceneTitle = v }
        if let v = t.episode, !v.isEmpty { s.episode = v }
        if let v = t.story, !v.isEmpty { s.story = v }
        if let v = t.trivia, !v.isEmpty { s.trivia = v }
        if let v = t.highlight, !v.isEmpty { s.highlight = v }
        if let v = t.access, !v.isEmpty { s.access = v }
        if let v = t.bestTime, !v.isEmpty { s.bestTime = v }
        if let v = t.creator, !v.isEmpty { s.creator = v }
        if let v = t.synopsis, !v.isEmpty { s.synopsis = v }
        return s
    }

    /// "en-US" → "en"，"zh-Hant-TW" → "zh-Hant"，"ja_JP" → "ja"
    static func languageFamily(_ code: String) -> String {
        let parts = code.replacingOccurrences(of: "_", with: "-").split(separator: "-").map(String.init)
        guard let first = parts.first else { return code }
        if first == "zh", parts.count > 1, ["Hans", "Hant"].contains(parts[1]) { return "zh-\(parts[1])" }
        if first == "zh" { return parts.contains(where: { ["TW", "HK", "MO"].contains($0) }) ? "zh-Hant" : "zh-Hans" }
        return first
    }
}

public enum SpotCatalog {
    /// 解码圣地数据。支持两种格式：
    /// - 新版 catalog.json：`{"works": [...], "spots": [...]}`（由 tools/catalog.py 生成）
    /// - 旧版：`[Spot]` 数组
    /// 两种都会校验 id 唯一。
    public static func decode(_ data: Data) throws -> [Spot] {
        var spots: [Spot]
        if let file = try? JSONDecoder().decode(CatalogFile.self, from: data) {
            spots = try file.resolve()
        } else {
            spots = try JSONDecoder().decode([Spot].self, from: data)
        }
        numberScenes(&spots)
        var seen = Set<String>()
        for s in spots where !seen.insert(s.id).inserted {
            throw CatalogError.duplicateID(s.id)
        }
        return spots
    }

    /// 给同一作品的多个名场面编号（按数据顺序）：地图上同一作品出现多次时，用“名场面一 / 二”区分
    public static func numberScenes(_ spots: inout [Spot]) {
        var counts: [String: Int] = [:]
        for s in spots { counts[s.workID, default: 0] += 1 }
        var seen: [String: Int] = [:]
        for i in spots.indices {
            let w = spots[i].workID
            seen[w, default: 0] += 1
            spots[i].sceneNumber = (counts[w] ?? 0) > 1 ? seen[w] : nil
        }
    }

    public enum CatalogError: Error, Equatable {
        case duplicateID(String)
        case unknownWork(spot: String, work: String)
        case missingBaseText(String)
    }
}

// MARK: - catalog.json 的原始结构

struct CatalogFile: Decodable {
    struct WorkText: Decodable {
        var title: String?
        var creator: String?
        var synopsis: String?
    }
    struct Work: Decodable {
        var id: String
        var title: String
        var mediaType: MediaType
        var year: Int?
        var creator: String?
        var tint: String?
        var aliases: [String]?
        var officialURL: String?
        var country: String?
        var text: [String: WorkText]
    }
    struct SpotText: Decodable {
        var placeName: String?
        var sceneTitle: String?
        var episode: String?
        var highlight: String?
        var story: String?
        var access: String?
        var bestTime: String?
        var tips: String?
    }
    struct SpotRecord: Decodable {
        var id: String
        var workID: String
        var latitude: Double
        var longitude: Double
        var sceneHeading: Double
        var scenePitch: Double?
        var arrivalRadius: Double?
        var spoiler: Bool?
        var sourceURL: String?
        var photo: SpotPhoto?
        var verified: Bool?
        var text: [String: SpotText]
    }

    var works: [Work]
    var spots: [SpotRecord]

    func resolve() throws -> [Spot] {
        let byID = Dictionary(works.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let base = Spot.baseLanguage
        return try spots.map { r in
            guard let w = byID[r.workID] else { throw SpotCatalog.CatalogError.unknownWork(spot: r.id, work: r.workID) }
            guard let t = r.text[base], let place = t.placeName, let title = t.sceneTitle, let story = t.story else {
                throw SpotCatalog.CatalogError.missingBaseText(r.id)
            }
            guard (-90...90).contains(r.latitude), (-180...180).contains(r.longitude) else {
                throw SpotCatalog.CatalogError.missingBaseText(r.id)
            }
            let wt = w.text[base]
            var translations: [String: SpotTranslation] = [:]
            for lang in Set(r.text.keys).union(w.text.keys) where lang != base {
                let st = r.text[lang], wl = w.text[lang]
                translations[lang] = SpotTranslation(
                    workLocalized: wl?.title, placeName: st?.placeName, sceneTitle: st?.sceneTitle,
                    episode: st?.episode, story: st?.story, trivia: st?.tips,
                    highlight: st?.highlight, access: st?.access, bestTime: st?.bestTime,
                    creator: wl?.creator, synopsis: wl?.synopsis)
            }
            return Spot(id: r.id, work: w.title,
                        workLocalized: wt?.title.flatMap { $0.isEmpty ? nil : $0 },
                        mediaType: w.mediaType, aliases: w.aliases ?? [],
                        placeName: place, sceneTitle: title, episode: t.episode, story: story, trivia: t.tips,
                        coordinate: GeoPoint(latitude: r.latitude, longitude: r.longitude),
                        sceneHeading: GeoMath.normalize(r.sceneHeading), scenePitch: r.scenePitch,
                        arrivalRadius: r.arrivalRadius ?? 40, sourceURL: r.sourceURL,
                        verified: r.verified ?? false, tint: w.tint, translations: translations,
                        workID: w.id, highlight: t.highlight, access: t.access, bestTime: t.bestTime,
                        spoiler: r.spoiler ?? false, photo: r.photo, year: w.year,
                        creator: wt?.creator ?? w.creator, synopsis: wt?.synopsis, officialURL: w.officialURL,
                        country: w.country == "JP" ? nil : w.country)
        }
    }
}
