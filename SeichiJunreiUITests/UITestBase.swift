import XCTest

/// 所有 UI 测试共用：启动参数、权限弹窗、输入、截图
class UITestBase: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        // 系统权限弹窗可能在任意时刻出现（比如定位弹窗晚于通知弹窗），挡住点击时自动允许
        addUIInterruptionMonitor(withDescription: "System alerts") { alert in
            for label in ["Allow While Using App", "Change to Always Allow", "Allow", "OK",
                          "使用App时允许", "更改为始终允许", "允许", "好"] {
                let button = alert.buttons[label]
                if button.exists { button.tap(); return true }
            }
            return false
        }
    }
    /// 启动 App：位置固定在「須賀神社」（《君の名は。》，名场面朝向 216°、仰角 12°）的机位，
    /// 可选地注入摄像头朝向（模拟器没有罗盘）。
    /// - entitlement: "lifetime"（默认，避免测试之间共享免费额度状态）/ "free"
    func launch(heading: Double? = nil, pitch: Double? = nil, language: String = "zh-Hans",
                entitlement: String = "lifetime", freeUsed: Int? = nil, extraEnv: [String: String] = [:],
                resetMapApp: Bool = true) {
        app = XCUIApplication()
        let locale = ["zh-Hans": "zh_CN", "zh-Hant": "zh_TW", "ja": "ja_JP", "en": "en_US", "ko": "ko_KR"][language] ?? "en_US"
        app.launchArguments += ["-AppleLanguages", "(\(language))", "-AppleLocale", locale,
                                // 清掉 App 内的语言设置 / 默认地图，避免测试之间互相影响
                                "-appLanguageOverride", ""]
        // 默认地图也清掉（测“设置默认地图”时保留，才能看到设置生效）
        if resetMapApp { app.launchArguments += ["-preferredMapApp", ""] }
        // 端到端测试开关：选图给模拟照片、外部链接只记录不跳出（只在 Debug 构建里生效）
        app.launchEnvironment["SEICHI_UITEST"] = "1"
        // 清掉上一个测试改过的偏好（帮拍的自动拍 / 语音等）
        app.launchEnvironment["SEICHI_RESET_PREFS"] = "1"
        app.launchEnvironment["SEICHI_SIM_LAT"] = "35.68518"
        app.launchEnvironment["SEICHI_SIM_LON"] = "139.72345"
        app.launchEnvironment["SEICHI_ENTITLEMENT"] = entitlement
        // 免费用户相关的测试需要打开收费开关，其余测试按默认（免费公测期）运行
        app.launchEnvironment["SEICHI_PAYWALL"] = entitlement == "free" ? "1" : "0"
        app.launchEnvironment.merge(extraEnv) { _, new in new }
        if let freeUsed { app.launchEnvironment["SEICHI_FREE_USED"] = String(freeUsed) }
        if let heading { app.launchEnvironment["SEICHI_SIM_HEADING"] = String(heading) }
        if let pitch { app.launchEnvironment["SEICHI_SIM_PITCH"] = String(pitch) }
        app.launch()
        dismissSystemAlerts()
    }
    /// 从到达横幅进入名场面模式
    func enterSceneFromBanner() {
        let banner = app.buttons["arrivalBanner"]
        XCTAssertTrue(banner.waitForExistence(timeout: 20), "站在机位附近时应显示到达横幅")
        dismissSystemAlerts(timeout: 3)   // 晚出现的权限弹窗（定位等）会挡住横幅
        banner.tap()
        dismissSystemAlerts(timeout: 4)   // 相机权限弹窗
        if banner.exists && banner.isHittable { banner.tap(); dismissSystemAlerts(timeout: 4) }
        // 已对准时庆祝画面会很快出现，并暂时隐藏顶部的关闭按钮，所以两者出现其一即表示已进入名场面模式
        let entered = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier IN %@", ["closeScene", "celebrationTitle"]))
            .firstMatch
        XCTAssertTrue(entered.waitForExistence(timeout: 15), "应进入名场面模式")
    }
    /// 处理定位、通知等系统权限弹窗（模拟器为英文环境，也兼容中文）。
    func dismissSystemAlerts(timeout: TimeInterval = 8) {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let labels = ["Allow While Using App", "Change to Always Allow", "Allow", "Allow Once", "OK",
                      "使用App时允许", "更改为始终允许", "允许", "好"]
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            var tapped = false
            for label in labels {
                let button = springboard.alerts.buttons[label]
                if button.exists { button.tap(); tapped = true; break }
            }
            if !tapped {
                if !springboard.alerts.firstMatch.waitForExistence(timeout: 1.5) { return }
            }
        }
    }
    /// 模拟器偶尔会丢键（例如把 “your name” 打成 “yur name”）：输入后核对内容，不对就清空重打
    func typeReliably(_ text: String, into field: XCUIElement, attempts: Int = 3) {
        for _ in 0..<attempts {
            field.typeText(text)
            if (field.value as? String) == text { return }
            let current = (field.value as? String) ?? ""
            if !current.isEmpty, current != field.placeholderValue {
                field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
            }
        }
        XCTAssertEqual(field.value as? String, text, "搜索框内容应为 \(text)")
    }
    func snapshot(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
    func dismissPopover() {
        let region = app.otherElements["PopoverDismissRegion"]
        if region.exists { region.tap() } else { app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05)).tap() }
        sleep(1)
    }

    /// 端到端测试打开外部链接 / 地图 App 时不会真的跳出 App，而是把地址写在 debugLastURL 里
    func lastOpenedURL(timeout: TimeInterval = 5) -> String? {
        let probe = app.staticTexts["debugLastURL"]
        guard probe.waitForExistence(timeout: timeout) else { return nil }
        return probe.label
    }

    /// 打开某个名场面的详情页（不经过地图点选）
    func launchAtDetail(_ spotID: String, heading: Double? = 30, language: String = "zh-Hans",
                        extraEnv: [String: String] = [:]) {
        launch(heading: heading, language: language, extraEnv: extraEnv.merging(["SEICHI_OPEN_SPOT": spotID]) { _, n in n })
        XCTAssertTrue(app.buttons["enterScene"].waitForExistence(timeout: 20), "应打开 \(spotID) 的详情页")
    }

    /// 往上滑直到元素可以点
    @discardableResult
    /// 滚到元素可点：先往下翻，找不到再往回翻（元素可能在当前位置的上方）
    @discardableResult
    func scrollTo(_ element: XCUIElement, maxSwipes: Int = 8) -> Bool {
        var tries = 0
        while !(element.exists && element.isHittable) && tries < maxSwipes { app.swipeUp(); tries += 1 }
        tries = 0
        while !(element.exists && element.isHittable) && tries < maxSwipes { app.swipeDown(); tries += 1 }
        return element.exists && element.isHittable
    }
}
