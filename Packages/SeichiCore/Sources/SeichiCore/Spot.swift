import Foundation

/// 作品类型
public enum MediaType: String, Codable, CaseIterable, Sendable {
    case anime        // TV 动画
    case animeFilm    // 动画电影
    case film         // 真人电影
    case drama        // 电视剧
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

    public init(workLocalized: String? = nil, placeName: String? = nil, sceneTitle: String? = nil,
                episode: String? = nil, story: String? = nil, trivia: String? = nil) {
        self.workLocalized = workLocalized; self.placeName = placeName; self.sceneTitle = sceneTitle
        self.episode = episode; self.story = story; self.trivia = trivia
    }
}

/// 一个圣地（动画/电影/电视剧名场面在现实中的取景地）。
public struct Spot: Codable, Identifiable, Hashable, Sendable {
    public var id: String
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

    public init(id: String, work: String, workLocalized: String? = nil,
                mediaType: MediaType = .anime, aliases: [String] = [], placeName: String,
                sceneTitle: String, episode: String? = nil, story: String, trivia: String? = nil,
                coordinate: GeoPoint, sceneHeading: Double, scenePitch: Double? = nil,
                arrivalRadius: Double = 25, sceneImage: String? = nil, sourceURL: String? = nil,
                verified: Bool = false, tint: String? = nil,
                translations: [String: SpotTranslation] = [:]) {
        self.id = id; self.work = work; self.workLocalized = workLocalized
        self.mediaType = mediaType; self.aliases = aliases
        self.placeName = placeName; self.sceneTitle = sceneTitle; self.episode = episode
        self.story = story; self.trivia = trivia; self.coordinate = coordinate
        self.sceneHeading = sceneHeading; self.scenePitch = scenePitch
        self.arrivalRadius = arrivalRadius; self.sceneImage = sceneImage
        self.sourceURL = sourceURL; self.verified = verified; self.tint = tint
        self.translations = translations
    }

    enum CodingKeys: String, CodingKey {
        case id, work, workLocalized, mediaType, aliases, placeName, sceneTitle, episode, story, trivia
        case latitude, longitude, sceneHeading, scenePitch, arrivalRadius
        case sceneImage, sourceURL, verified, tint, translations
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        work = try c.decode(String.self, forKey: .work)
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
    /// 从 JSON 数据解码圣地列表，并校验 id 唯一。
    public static func decode(_ data: Data) throws -> [Spot] {
        let spots = try JSONDecoder().decode([Spot].self, from: data)
        var seen = Set<String>()
        for s in spots where !seen.insert(s.id).inserted {
            throw CatalogError.duplicateID(s.id)
        }
        return spots
    }

    public enum CatalogError: Error, Equatable {
        case duplicateID(String)
    }
}
