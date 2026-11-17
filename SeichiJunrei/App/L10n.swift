import Foundation
import SeichiCore

/// 取本地化文案。key 定义在 tools/l10n.py，生成到 Resources/<语言>.lproj/Localizable.strings。
/// 支持 printf 风格参数：L("guide.right", 70) → "向右转 70°" / "Turn right 70°"
func L(_ key: String, _ args: CVarArg...) -> String {
    let format = Bundle.main.localizedString(forKey: key, value: nil, table: nil)
    return args.isEmpty ? format : String(format: format, locale: Locale.current, arguments: args)
}

enum AppLanguage {
    /// 当前界面实际使用的语言（App 支持的语言之一；不支持的系统语言会回退到英语）
    static var current: String { Bundle.main.preferredLocalizations.first ?? "en" }
}

extension MediaType {
    var label: String {
        switch self {
        case .anime: return L("media.anime")
        case .animeFilm: return L("media.animeFilm")
        case .film: return L("media.film")
        case .drama: return L("media.drama")
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
    /// 「场景名」/“Scene title”
    var quotedSceneTitle: String { L("format.sceneTitle", sceneTitle) }
    /// 作品原名 +（本地化译名）
    var displayWorkLocalized: String {
        workLocalized.map { L("format.workWithLocalized", work, $0) } ?? work
    }
}
