import Foundation
import Observation
import SwiftUI
import SeichiCore

/// 取本地化文案。key 定义在 tools/l10n.py，生成到 Resources/<语言>.lproj/Localizable.strings。
/// 支持 printf 风格参数：L("guide.right", 70) → "向右转 70°" / "Turn right 70°"
func L(_ key: String, _ args: CVarArg...) -> String {
    let lang = AppLanguage.shared
    let format = lang.bundle.localizedString(forKey: key, value: nil, table: nil)
    return args.isEmpty ? format : String(format: format, locale: lang.locale, arguments: args)
}

/// App 内的界面语言。默认跟随系统；用户可以在 App 的设置页里单独切换，不用跑去系统设置。
///
/// 这是一个 @Observable 对象：`L()` 每次都会读取 `code`，所以 SwiftUI 视图在 body 里调用 `L()`
/// 就会自动订阅语言变化，切换后界面立刻刷新，不需要重启 App。
@Observable
final class AppLanguage {
    static let shared = AppLanguage()
    /// App 支持的语言，按设置页显示顺序
    static let supported = ["zh-Hans", "zh-Hant", "ja", "en", "ko"]
    private static let storageKey = "appLanguageOverride"

    /// 用户选择的语言；nil 表示跟随系统
    var override: String? {
        didSet {
            UserDefaults.standard.set(override, forKey: Self.storageKey)
            refresh()
        }
    }
    /// 当前界面实际使用的语言
    private(set) var code: String = "en"
    private(set) var bundle: Bundle = .main
    private(set) var locale: Locale = .current

    private init() {
        let saved = UserDefaults.standard.string(forKey: Self.storageKey)
        override = saved.flatMap { Self.supported.contains($0) ? $0 : nil }
        refresh()
    }

    /// 兼容旧调用：当前语言代码
    static var current: String { shared.code }

    /// 系统语言里第一个 App 支持的语言（不支持时回退到英语）
    static var systemLanguage: String { Bundle.main.preferredLocalizations.first ?? "en" }

    private func refresh() {
        let lang = override ?? Self.systemLanguage
        if let path = Bundle.main.path(forResource: lang, ofType: "lproj"), let b = Bundle(path: path) {
            bundle = b
        } else {
            bundle = .main
        }
        locale = override.map { Locale(identifier: $0) } ?? .current
        code = lang
    }

    /// 语言自己的名字（设置页用，不随界面语言变化）
    static func nativeName(_ code: String) -> String {
        switch code {
        case "zh-Hans": return "简体中文"
        case "zh-Hant": return "繁體中文"
        case "ja": return "日本語"
        case "en": return "English"
        case "ko": return "한국어"
        default: return code
        }
    }
}

extension MediaType {
    /// 作品类型的口语化称呼（日漫 / 日剧 / 日影、アニメ / ドラマ / 映画 …），用在作品名前面
    var label: String {
        switch self {
        case .anime: return L("media.anime")
        case .animeFilm: return L("media.animeFilm")
        case .film: return L("media.film")
        case .drama: return L("media.drama")
        }
    }
}

extension MediaCategory {
    /// 筛选标签
    var label: String { L("category.\(rawValue)") }
    /// 类型代表色：日漫 / 日剧 / 日影各一种，一眼区分
    var color: Color {
        switch self {
        case .anime: return Color(red: 0.93, green: 0.36, blue: 0.55)
        case .drama: return Color(red: 0.25, green: 0.52, blue: 0.96)
        case .film: return Color(red: 0.96, green: 0.62, blue: 0.20)
        }
    }
    var symbolName: String {
        switch self {
        case .anime: return "sparkles.tv.fill"
        case .drama: return "tv.fill"
        case .film: return "movieclapper.fill"
        }
    }
}

enum Compass {
    /// 八方位名称（本地化）
    static func name(_ bearing: Double) -> String { L("compass.\(GeoMath.compassIndex(bearing))") }
}

extension SceneGuidance {
    /// 给用户看的一句话提示
    var instruction: String {
        switch (turn, tilt) {
        case (.aligned, .level): return L("guide.aligned")
        case (.aligned, .up): return L("guide.tiltUp", pitchDegrees)
        case (.aligned, .down): return L("guide.tiltDown", pitchDegrees)
        case (.left, _): return L("guide.left", yawDegrees)
        case (.right, _): return L("guide.right", yawDegrees)
        }
    }
}

extension Spot {
    /// 《作品名》/『作品名』等，按语言习惯加书名号；有本地化译名时用译名（日语环境下就是原名）
    var workTitle: String { L("format.workTitle", workLocalized ?? work) }
    /// 当前语言下的作品名（无书名号）
    var workName: String { workLocalized ?? work }
    /// 作品原名；与当前语言的名称相同时为 nil（例如日语环境）
    var originalWorkName: String? { workLocalized == nil || workLocalized == work ? nil : work }
    /// 作品类型的叫法：在日本取景的外国电影（如《非诚勿扰》）不能叫“日影”
    var mediaLabel: String {
        if mediaType == .film, let country, country != "JP" { return L("media.filmForeign") }
        return mediaType.label
    }
    /// “日漫《龙猫》” / “アニメ『となりのトトロ』” / “Anime · My Neighbor Totoro”
    var workBadge: String { L("format.workBadge", mediaLabel, workName) }
    /// “名场面一” / “名シーン1” / “Scene 1”；作品只有一个名场面时为 nil
    var sceneNumberLabel: String? {
        guard let n = sceneNumber else { return nil }
        let lang = AppLanguage.current
        let numeral: String
        if lang.hasPrefix("zh") {
            // 中文用汉字数字：一、二、三……
            let f = NumberFormatter()
            f.numberStyle = .spellOut
            f.locale = Locale(identifier: lang == "zh-Hant" ? "zh-Hant" : "zh-Hans")
            numeral = f.string(from: NSNumber(value: n)) ?? "\(n)"
        } else {
            numeral = "\(n)"
        }
        return L("format.sceneNumber", numeral)
    }
    /// 地图标记 / 卡片上的标题：同一作品有多个名场面时加上序号，例如“日影《情书》名场面一”
    var badgeWithNumber: String {
        sceneNumberLabel.map { L("format.badgeWithNumber", workBadge, $0) } ?? workBadge
    }
    /// 关于作品里的作品名：带书名号
    var quotedWorkName: String { L("format.workTitle", workName) }
    /// 「场景名」/“Scene title”
    var quotedSceneTitle: String { L("format.sceneTitle", sceneTitle) }
    /// 作品原名 +（本地化译名）
    var displayWorkLocalized: String {
        workLocalized.map { L("format.workWithLocalized", work, $0) } ?? work
    }
}

/// 用指定语言取文案（帮拍模式：拍照的人可能说另一种语言，比如请日本路人帮忙）
func LIn(_ code: String, _ key: String, _ args: CVarArg...) -> String {
    let bundle = Bundle.main.path(forResource: code, ofType: "lproj").flatMap(Bundle.init(path:)) ?? .main
    let format = bundle.localizedString(forKey: key, value: nil, table: nil)
    return args.isEmpty ? format : String(format: format, locale: Locale(identifier: code), arguments: args)
}
