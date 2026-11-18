import XCTest

/// 端到端冒烟测试：在模拟器里走一遍主要流程，并在每一步截图。
/// CI 会先把模拟器定位设到「須賀神社」的机位附近，所以启动后应该出现“到达横幅”。
final class SmokeUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        // 系统权限弹窗可能在任意时刻出现（比如定位弹窗晚于通知弹窗），挡住点击时自动允许
        addUIInterruptionMonitor(withDescription: "System alerts") { alert in
            for label in ["Allow While Using App", "Allow", "OK", "使用App时允许", "允许", "好"] {
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
                entitlement: String = "lifetime", freeUsed: Int? = nil, extraEnv: [String: String] = [:]) {
        app = XCUIApplication()
        let locale = ["zh-Hans": "zh_CN", "zh-Hant": "zh_TW", "ja": "ja_JP", "en": "en_US", "ko": "ko_KR"][language] ?? "en_US"
        app.launchArguments += ["-AppleLanguages", "(\(language))", "-AppleLocale", locale,
                                // 清掉 App 内的语言设置 / 默认地图，避免测试之间互相影响
                                "-appLanguageOverride", "", "-preferredMapApp", ""]
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

    /// 免费额度用完：到达机位后显示锁定层，点按钮弹出付费墙（含恢复购买）
    func testFreeLimitShowsPaywall() throws {
        launch(heading: 216, pitch: 12, entitlement: "free", freeUsed: 3)
        enterSceneFromBanner()
        if !app.buttons["showPaywall"].waitForExistence(timeout: 8) {
            snapshot("13-scene-locked-missing")
            print(app.debugDescription)
            XCTFail("额度用完应显示锁定层")
        }
        XCTAssertFalse(app.staticTexts["celebrationTitle"].exists, "锁定时不应进入取景")
        snapshot("13-scene-locked")
        app.buttons["showPaywall"].tap()
        XCTAssertTrue(app.staticTexts["解锁全部名场面"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["restorePurchases"].exists, "付费墙必须提供恢复购买")
        snapshot("14-paywall")
    }

    /// 免费用户还有额度：可以正常进入取景并对准
    func testFreeUserWithAllowanceCanEnter() throws {
        launch(heading: 218, pitch: 10, entitlement: "free", freeUsed: 2)
        enterSceneFromBanner()
        if !app.staticTexts["celebrationTitle"].waitForExistence(timeout: 10) {
            snapshot("free-allowance-no-celebration")
            print(app.debugDescription)
            XCTFail("还有免费额度时应能体验")
        }
        XCTAssertFalse(app.buttons["showPaywall"].exists)
    }

    /// 处理定位、通知等系统权限弹窗（模拟器为英文环境，也兼容中文）。
    func dismissSystemAlerts(timeout: TimeInterval = 8) {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let labels = ["Allow While Using App", "Allow", "Allow Once", "OK",
                      "使用App时允许", "允许", "好"]
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

    func snapshot(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testMainFlow() throws {
        launch()
        // 1. 地图首页 + 到达横幅（模拟器定位在須賀神社）
        let banner = app.buttons["arrivalBanner"]
        if !banner.waitForExistence(timeout: 20) {
            snapshot("01-map-no-banner")
            print(app.debugDescription)
            XCTFail("站在机位附近时应显示到达横幅")
        }
        snapshot("01-map-arrived")

        // 2. 按作品名搜索
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("your name")
        let workRow = app.buttons["work-君の名は。"]
        XCTAssertTrue(workRow.waitForExistence(timeout: 5), "搜索 your name 应找到《君の名は。》")
        snapshot("02-search-suggestions")
        workRow.tap()
        XCTAssertTrue(app.staticTexts["日漫《你的名字。》"].waitForExistence(timeout: 5),
                      "选择作品后应聚焦到《君の名は。》，而不是被“搜索全部结果”覆盖")
        snapshot("03-work-focused")

        // 3. 打开名场面详情
        let card = app.buttons["card-kiminonawa-suga-shrine"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        card.tap()
        let enter = app.buttons["enterScene"]
        XCTAssertTrue(enter.waitForExistence(timeout: 5), "详情页应有进入名场面的按钮")
        snapshot("04-detail")

        // 4. 进入名场面模式（模拟器没有相机/罗盘，应优雅降级而不是崩溃）
        // 详情页顶部是大图，按钮可能在半屏 sheet 之外：先上滑展开
        var tries = 0
        while !enter.isHittable && tries < 4 { app.swipeUp(); tries += 1 }
        enter.tap()
        dismissSystemAlerts(timeout: 4)   // 相机权限弹窗
        let close = app.buttons["closeScene"]
        XCTAssertTrue(close.waitForExistence(timeout: 8), "应进入全屏名场面模式")
        sleep(2)
        snapshot("05-scene-mode")
        close.tap()
        XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 5), "关闭后应回到地图")
    }

    func testListBrowseAndFilter() throws {
        launch()
        let open = app.buttons["openList"]
        XCTAssertTrue(open.waitForExistence(timeout: 10))
        open.tap()
        XCTAssertTrue(app.staticTexts["全部名场面"].waitForExistence(timeout: 5))
        let picker = app.segmentedControls.firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        picker.buttons["日剧"].tap()
        // 日剧很多，用搜索框定位到《东京爱情故事》
        // 列表页自己的搜索框（地图页的搜索框也在视图层级里，不能用 firstMatch）
        let search = app.searchFields["日漫 / 日剧 / 日影名称"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("东京爱情")
        XCTAssertTrue(app.staticTexts["月台栏杆上的白手帕"].waitForExistence(timeout: 5),
                      "电视剧筛选应显示《东京爱情故事》的名场面")
        snapshot("06-list-drama")
    }

    /// 朝向偏离名场面 70° 时，应提示“向右转 70°”
    func testSceneTurnGuidance() throws {
        launch(heading: 146, pitch: 12)
        enterSceneFromBanner()
        XCTAssertTrue(app.staticTexts["向右转 70°"].waitForExistence(timeout: 5), "应提示向右转 70°")
        snapshot("07-scene-turn-right")
        XCTAssertFalse(app.staticTexts["celebrationTitle"].exists, "未对准时不应触发庆祝")
    }

    /// 朝向与名场面一致并保持一会儿，应触发“就是这个画面！”庆祝
    func testSceneAlignedCelebration() throws {
        launch(heading: 218, pitch: 10)
        enterSceneFromBanner()
        let title = app.staticTexts["celebrationTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 6), "对准并保持后应出现庆祝画面")
        sleep(1)
        snapshot("08-scene-celebration")
    }

    /// 英语界面：标题、搜索提示、转身指引、名场面内容都应切换为英语
    func testEnglishLocalization() throws {
        launch(heading: 146, pitch: 12, language: "en")
        XCTAssertTrue(app.navigationBars["Seichi Junrei"].waitForExistence(timeout: 10), "导航标题应为英语")
        XCTAssertEqual(app.searchFields.firstMatch.placeholderValue, "Search anime, J-dramas, movies")
        snapshot("09-en-map")
        enterSceneFromBanner()
        XCTAssertTrue(app.staticTexts["Turn right 70°"].waitForExistence(timeout: 5))
        snapshot("10-en-scene")
    }

    /// 日语界面：转身指引与列表
    func testJapaneseLocalization() throws {
        launch(heading: 146, pitch: 12, language: "ja")
        XCTAssertTrue(app.navigationBars["聖地巡礼"].waitForExistence(timeout: 10), "导航标题应为日语")
        let open = app.buttons["openList"]
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        open.tap()
        XCTAssertTrue(app.staticTexts["すべての名シーン"].waitForExistence(timeout: 5))
        snapshot("11-ja-list")
        app.buttons["完了"].tap()
        enterSceneFromBanner()
        XCTAssertTrue(app.staticTexts["右に70°回って"].waitForExistence(timeout: 5))
        snapshot("12-ja-scene")
    }

    /// 巡礼达成 → 拍照留念 → 自动打开分享卡（作中 vs 现实）→ 切换版式 → 打开系统分享面板
    func testShareCardAfterPilgrimage() throws {
        launch(heading: 218, pitch: 10, extraEnv: ["SEICHI_SIM_SCENE_IMAGE": "1"])
        enterSceneFromBanner()
        XCTAssertTrue(app.staticTexts["celebrationTitle"].waitForExistence(timeout: 8))
        app.buttons["celebratePhoto"].tap()   // 模拟器生成示意照片
        let card = app.otherElements["shareCard"]
        if !card.waitForExistence(timeout: 8) {
            snapshot("share-missing")
            print(app.debugDescription)
            XCTFail("拍照后应打开分享卡")
        }
        sleep(1)
        snapshot("15-share-compare")
        app.segmentedControls.buttons["现场照片"].tap()
        sleep(1)
        snapshot("16-share-single")
        app.buttons["shareButton"].tap()
        sleep(2)
        snapshot("17-share-sheet")
    }

    /// 用户在现场校准机位：名场面模式 → 校准 → 读数质量良好 → 填备注 → 提交成功
    func testCalibrationSubmission() throws {
        launch(heading: 216, pitch: 12, extraEnv: ["SEICHI_FAKE_SUBMIT": "1"])
        enterSceneFromBanner()
        // 朝向与名场面完全一致，所以一定会先出现庆祝画面（出现时间取决于相机启动等）。
        // 等庆祝画面出现后点“继续欣赏”，回到取景界面再找校准按钮。
        XCTAssertTrue(app.staticTexts["celebrationTitle"].waitForExistence(timeout: 15), "对准后应出现庆祝画面")
        let keepLooking = app.buttons["继续欣赏"]
        XCTAssertTrue(keepLooking.waitForExistence(timeout: 5))
        // 相机权限弹窗可能还挡在上面
        var tries = 0
        while keepLooking.exists && tries < 4 {
            dismissSystemAlerts(timeout: 2)
            keepLooking.tap()
            tries += 1
            sleep(1)
        }
        let calibrate = app.buttons["sceneCalibrate"]
        XCTAssertTrue(calibrate.waitForExistence(timeout: 8), "名场面模式应有校准入口")
        calibrate.tap()
        XCTAssertTrue(app.staticTexts["数据质量良好，可以提交"].waitForExistence(timeout: 8), "模拟器注入的读数应判定为质量良好")
        let note = app.textFields["calibrationNote"].exists ? app.textFields["calibrationNote"] : app.textViews["calibrationNote"]
        if note.exists {
            note.tap()
            note.typeText("top step")
        }
        snapshot("18-calibration")
        app.buttons["submitCalibration"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "感谢")).firstMatch.waitForExistence(timeout: 8),
                      "提交后应显示感谢")
        snapshot("19-calibration-thanks")
    }

    /// 设置页切换语言：不用去系统设置，切换后界面立即变成对应语言
    func testSwitchLanguageInSettings() throws {
        launch()
        let settings = app.buttons["openSettings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.tap()
        let language = app.buttons["settingsLanguage"]
        XCTAssertTrue(language.waitForExistence(timeout: 5))
        snapshot("20-settings")
        language.tap()
        app.buttons["日本語"].tap()
        // 返回设置页，标题已经是日语
        XCTAssertTrue(app.navigationBars["設定"].waitForExistence(timeout: 5), "切换后设置页应立即变成日语")
        app.buttons["完了"].tap()
        XCTAssertTrue(app.navigationBars["聖地巡礼"].waitForExistence(timeout: 5), "地图页也应变成日语")
        snapshot("21-switched-to-ja")
    }

    /// 帮拍模式：被拍的人已经站在主角的位置，方向也对 → 提示“完美” → 自动倒数拍照 → 按原作构图保存
    func testPhotographerModeAutoShutter() throws {
        launch(heading: 216, pitch: 12, extraEnv: ["SEICHI_SIM_SUBJECT": "0.5,0.85,0.45"])
        let card = app.buttons["card-kiminonawa-suga-shrine"]
        XCTAssertTrue(card.waitForExistence(timeout: 20))
        card.tap()
        let open = app.buttons["openPhotographer"]
        XCTAssertTrue(open.waitForExistence(timeout: 5), "详情页应有“请人帮我拍”")
        if !open.isHittable { app.swipeUp() }
        open.tap()
        let start = app.buttons["startPhotographer"]
        XCTAssertTrue(start.waitForExistence(timeout: 8), "应先显示交接页")
        snapshot("22-photographer-handoff")
        start.tap()
        dismissSystemAlerts(timeout: 4)   // 相机权限
        XCTAssertTrue(app.staticTexts["pgInstruction"].waitForExistence(timeout: 8))
        snapshot("23-photographer-shooting")
        let saved = app.descendants(matching: .any)["pgSaved"]
        if !saved.waitForExistence(timeout: 15) {
            dismissSystemAlerts(timeout: 3)   // 相册权限
        }
        XCTAssertTrue(saved.waitForExistence(timeout: 10), "对齐后应自动倒数拍照并保存")
        snapshot("24-photographer-saved")
    }

    /// 帮拍模式：人物太大（离得太近）时，提示往后退
    func testPhotographerModeStepBackHint() throws {
        launch(heading: 216, pitch: 12, extraEnv: ["SEICHI_SIM_SUBJECT": "0.5,0.98,0.95"])
        let card = app.buttons["card-kiminonawa-suga-shrine"]
        XCTAssertTrue(card.waitForExistence(timeout: 20))
        card.tap()
        let open = app.buttons["openPhotographer"]
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        if !open.isHittable { app.swipeUp() }
        open.tap()
        app.buttons["startPhotographer"].tap()
        dismissSystemAlerts(timeout: 4)
        let hint = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "往后退")).firstMatch
        XCTAssertTrue(hint.waitForExistence(timeout: 8), "人物太大时应提示往后退")
        snapshot("25-photographer-step-back")
    }

    /// 巡礼者的照片：详情页能看到别人上传的照片，可以举报
    func testCommunityPhotoReport() throws {
        launch(extraEnv: ["SEICHI_FAKE_COMMUNITY": "1"])
        let card = app.buttons["card-kiminonawa-suga-shrine"]
        XCTAssertTrue(card.waitForExistence(timeout: 20))
        card.tap()
        let photo = app.buttons["communityPhoto"].firstMatch
        XCTAssertTrue(photo.waitForExistence(timeout: 8), "详情页应显示巡礼者的照片")
        var tries = 0
        while !photo.isHittable && tries < 8 { app.swipeUp(); tries += 1 }
        snapshot("26-community-photos")
        photo.tap()
        let more = app.buttons["communityMore"]
        XCTAssertTrue(more.waitForExistence(timeout: 5))
        more.tap()
        app.buttons["举报"].tap()
        let reason = app.buttons["与这个地点无关"]
        XCTAssertTrue(reason.waitForExistence(timeout: 5))
        reason.tap()
        XCTAssertTrue(app.staticTexts["communityNotice"].waitForExistence(timeout: 5)
                      || app.descendants(matching: .any)["communityNotice"].waitForExistence(timeout: 3),
                      "举报后应提示已收到")
        snapshot("27-community-reported")
    }

    /// 投稿新名场面：表单可以打开，必填项没填时不能提交
    func testSubmitSceneFormRequiresFields() throws {
        launch(extraEnv: ["SEICHI_FAKE_COMMUNITY": "1"])
        let open = app.buttons["openSubmit"]
        XCTAssertTrue(open.waitForExistence(timeout: 10))
        open.tap()
        let send = app.buttons["submitSend"]
        let title = app.textFields["submitWorkTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        title.typeText("测试作品")
        snapshot("28-submit-form")
        var tries = 0
        while !send.exists && tries < 6 { app.swipeUp(); tries += 1 }
        XCTAssertTrue(send.exists)
        XCTAssertFalse(send.isEnabled, "没填完必填项、没有照片时不能提交")
    }

    /// 帮拍取景页：返回按钮能回到交接页；变焦按钮能在 自动 / 1× / 2× 之间切换；
    /// 指引语言切成日语后，按钮文字也跟着变
    func testPhotographerBackZoomAndLanguage() throws {
        launch(heading: 216, pitch: 12, extraEnv: ["SEICHI_SIM_SUBJECT": "0.5,0.98,0.95"])
        let card = app.buttons["card-kiminonawa-suga-shrine"]
        XCTAssertTrue(card.waitForExistence(timeout: 20))
        card.tap()
        let open = app.buttons["openPhotographer"]
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        var tries = 0
        while !open.isHittable && tries < 4 { app.swipeUp(); tries += 1 }
        open.tap()
        app.buttons["日本語"].tap()       // 拍照的人的语言
        app.buttons["startPhotographer"].tap()
        dismissSystemAlerts(timeout: 4)
        XCTAssertTrue(app.staticTexts["pgInstruction"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["pgAutoShutter"].label.contains("自動撮影"), "按钮文字应跟随拍照人的语言（日语）")
        let zoom = app.buttons["pgZoom"]
        XCTAssertTrue(zoom.exists)
        zoom.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "固定")).firstMatch
                        .waitForExistence(timeout: 3), "点变焦后应切换到固定倍数")
        snapshot("29-photographer-ja-zoom")
        app.buttons["closeShooting"].tap()
        XCTAssertTrue(app.buttons["startPhotographer"].waitForExistence(timeout: 5), "返回按钮应回到交接页")
    }
}
