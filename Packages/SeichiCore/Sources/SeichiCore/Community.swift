import Foundation

// MARK: - 用户投稿的内容规则（与平台无关，方便测试）

/// 投稿文字的基础过滤：拦截脏话、广告链接、联系方式。
/// App Store 审核规范 1.2 要求有“过滤不良内容”的机制；图片靠举报 + 人工复核。
public enum ContentFilter {
    public enum Problem: Equatable, Sendable {
        case empty
        case tooLong(max: Int)
        case link          // 网址 / 广告
        case contact       // 电话、微信、LINE 等联系方式
        case offensive     // 脏话、辱骂
    }

    /// 常见脏话 / 辱骂词（中日英韩），都是小写；匹配时忽略大小写与空格
    static let blocked: [String] = [
        // 中文
        "傻逼", "傻b", "煞笔", "沙比", "操你", "草你妈", "你妈的", "尼玛", "妈逼", "贱人", "婊子", "去死", "强奸", "约炮", "裸聊",
        // 日本語
        "死ね", "殺す", "ころす", "きもい", "ちんこ", "まんこ", "セックス", "援交",
        // English
        "fuck", "shit", "bitch", "cunt", "nigger", "faggot", "porn", "rape",
        // 한국어
        "씨발", "시발", "병신", "개새끼", "좆",
    ]

    public static func problems(in text: String, required: Bool = true, maxLength: Int = 500) -> [Problem] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var out: [Problem] = []
        if trimmed.isEmpty {
            if required { out.append(.empty) }
            return out
        }
        if trimmed.count > maxLength { out.append(.tooLong(max: maxLength)) }
        let lower = trimmed.lowercased()
        let compact = lower.filter { !$0.isWhitespace }
        if lower.range(of: #"(https?://|www\.|\.com\b|\.cn\b|\.jp\b|t\.me/)"#, options: .regularExpression) != nil {
            out.append(.link)
        }
        if compact.range(of: #"(\d[\d\-]{8,}\d|微信|vx[:：]|wechat|line[:：]?id|qq[:：]?\d)"#, options: .regularExpression) != nil {
            out.append(.contact)
        }
        if blocked.contains(where: { compact.contains($0) }) { out.append(.offensive) }
        return out
    }

    public static func isClean(_ text: String, required: Bool = true, maxLength: Int = 500) -> Bool {
        problems(in: text, required: required, maxLength: maxLength).isEmpty
    }
}

/// 用户投稿的新名场面（草稿）
public struct SceneDraft: Equatable, Sendable {
    public var workTitle: String
    public var mediaType: MediaType
    public var sceneTitle: String
    public var episode: String
    public var placeName: String
    public var story: String
    public var latitude: Double?
    public var longitude: Double?
    public var heading: Double?
    public var pitch: Double?
    public var hasPhoto: Bool

    public init(workTitle: String = "", mediaType: MediaType = .anime, sceneTitle: String = "", episode: String = "",
                placeName: String = "", story: String = "", latitude: Double? = nil, longitude: Double? = nil,
                heading: Double? = nil, pitch: Double? = nil, hasPhoto: Bool = false) {
        self.workTitle = workTitle; self.mediaType = mediaType; self.sceneTitle = sceneTitle
        self.episode = episode; self.placeName = placeName; self.story = story
        self.latitude = latitude; self.longitude = longitude; self.heading = heading; self.pitch = pitch
        self.hasPhoto = hasPhoto
    }

    public enum Field: String, CaseIterable, Sendable {
        case workTitle, sceneTitle, episode, placeName, story, location, heading, photo
    }

    /// 每个字段的问题；全部为空才能提交
    public func problems() -> [Field: [ContentFilter.Problem]] {
        var out: [Field: [ContentFilter.Problem]] = [:]
        func check(_ f: Field, _ text: String, required: Bool, max: Int) {
            let p = ContentFilter.problems(in: text, required: required, maxLength: max)
            if !p.isEmpty { out[f] = p }
        }
        check(.workTitle, workTitle, required: true, max: 80)
        check(.sceneTitle, sceneTitle, required: true, max: 40)
        check(.episode, episode, required: false, max: 40)
        check(.placeName, placeName, required: true, max: 80)
        check(.story, story, required: true, max: 800)
        if let lat = latitude, let lon = longitude {
            // 目前只收录日本境内的名场面
            if !(24...46).contains(lat) || !(122...154).contains(lon) { out[.location] = [.empty] }
        } else {
            out[.location] = [.empty]
        }
        if heading == nil { out[.heading] = [.empty] }
        if !hasPhoto { out[.photo] = [.empty] }
        return out
    }

    public var canSubmit: Bool { problems().isEmpty }
}

/// 举报自动隐藏：同一内容被不同用户举报达到阈值就先隐藏，等人工复核
public enum ReportPolicy {
    public static let hideThreshold = 3

    /// - Parameter reports: (被举报内容 ID, 举报人 ID)
    /// - Returns: 应该隐藏的内容 ID
    public static func hiddenTargets(_ reports: [(target: String, reporter: String)],
                                     threshold: Int = hideThreshold) -> Set<String> {
        var reporters: [String: Set<String>] = [:]
        for r in reports { reporters[r.target, default: []].insert(r.reporter) }
        return Set(reporters.filter { $0.value.count >= threshold }.keys)
    }

    /// 带举报原因的版本：以“侵犯版权”举报 1 次就先隐藏（版权风险最高，等人工复核），其他原因仍要 3 人
    public static func hiddenTargets(_ reports: [(target: String, reporter: String, reason: String)],
                                     threshold: Int = hideThreshold) -> Set<String> {
        let copyright = Set(reports.filter { $0.reason == copyrightReason }.map(\.target))
        return copyright.union(hiddenTargets(reports.map { (target: $0.target, reporter: $0.reporter) }, threshold: threshold))
    }

    public static let copyrightReason = "copyright"
}

/// 上传照片的来源检查：只收“在现场用相机拍的原图”
public enum PhotoProvenance: Equatable, Sendable {
    case ok
    /// 系统截图
    case screenshot
    /// 没有相机信息：网上下载、微信保存、编辑导出的图
    case noCamera
    /// 没有拍摄位置
    case noLocation
    /// 不是在名场面附近拍的（例如在家翻拍屏幕）
    case tooFar(meters: Double)

    /// App 里自己的相机拍的：拍摄时就在现场，直接通过
    public static func check(isInAppCapture: Bool, isScreenshot: Bool, cameraMake: String?, cameraModel: String?,
                             photoLocation: GeoPoint?, spot: GeoPoint, maxDistance: Double = 1000) -> PhotoProvenance {
        if isInAppCapture { return .ok }
        if isScreenshot { return .screenshot }
        let make = (cameraMake ?? "").trimmingCharacters(in: .whitespaces)
        let model = (cameraModel ?? "").trimmingCharacters(in: .whitespaces)
        if make.isEmpty && model.isEmpty { return .noCamera }
        guard let loc = photoLocation else { return .noLocation }
        let d = GeoMath.distance(from: loc, to: spot)
        return d <= maxDistance ? .ok : .tooFar(meters: d)
    }
}
