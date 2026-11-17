import Foundation

/// 全局开关
enum AppConfig {
    /// 收费开关。免费公测期间关闭：名场面模式不限次数、不显示付费墙。
    /// 由 project.yml 中的构建设置 `SEICHI_PAYWALL_ENABLED`（写入 Info.plist 的 `SeichiPaywallEnabled`）控制，
    /// 开启收费只需把它改为 YES 并发布新版本。Debug 构建可用环境变量 SEICHI_PAYWALL=1/0 覆盖（UI 测试用）。
    static var paywallEnabled: Bool {
        #if DEBUG
        if let v = ProcessInfo.processInfo.environment["SEICHI_PAYWALL"] { return v == "1" }
        #endif
        let value = Bundle.main.object(forInfoDictionaryKey: "SeichiPaywallEnabled")
        if let b = value as? Bool { return b }
        if let s = value as? String { return ["yes", "true", "1"].contains(s.lowercased()) }
        return false
    }

    /// 联系邮箱（用户反馈、举报处理）。由构建设置 SEICHI_CONTACT_EMAIL 写入 Info.plist；为空时不显示。
    static var contactEmail: String? {
        let v = (Bundle.main.object(forInfoDictionaryKey: "SeichiContactEmail") as? String)?
            .trimmingCharacters(in: .whitespaces)
        guard let v, v.contains("@") else { return nil }
        return v
    }
}
