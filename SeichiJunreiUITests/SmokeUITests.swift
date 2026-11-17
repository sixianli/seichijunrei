import XCTest

/// 端到端冒烟测试：在模拟器里走一遍主要流程，并在每一步截图。
/// CI 会先把模拟器定位设到「須賀神社」的机位附近，所以启动后应该出现“到达横幅”。
final class SmokeUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// 启动 App：位置固定在「須賀神社」（《君の名は。》，名场面朝向 270°、仰角 10°）的机位，
    /// 可选地注入摄像头朝向（模拟器没有罗盘）。
    func launch(heading: Double? = nil, pitch: Double? = nil) {
        app = XCUIApplication()
        app.launchEnvironment["SEICHI_SIM_LAT"] = "35.68540"
        app.launchEnvironment["SEICHI_SIM_LON"] = "139.72265"
        if let heading { app.launchEnvironment["SEICHI_SIM_HEADING"] = String(heading) }
        if let pitch { app.launchEnvironment["SEICHI_SIM_PITCH"] = String(pitch) }
        app.launch()
        dismissSystemAlerts()
    }

    /// 从到达横幅进入名场面模式
    func enterSceneFromBanner() {
        let banner = app.buttons["arrivalBanner"]
        XCTAssertTrue(banner.waitForExistence(timeout: 20), "站在机位附近时应显示到达横幅")
        banner.tap()
        dismissSystemAlerts(timeout: 4)   // 相机权限弹窗
        XCTAssertTrue(app.buttons["closeScene"].waitForExistence(timeout: 8))
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
        XCTAssertTrue(app.staticTexts["《君の名は。（你的名字。）》"].waitForExistence(timeout: 5),
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
        picker.buttons["电视剧"].tap()
        XCTAssertTrue(app.staticTexts["月台栏杆上的白手帕"].waitForExistence(timeout: 5),
                      "电视剧筛选应显示《东京爱情故事》的名场面")
        snapshot("06-list-drama")
    }

    /// 朝向偏离名场面 70° 时，应提示“向右转 70°”
    func testSceneTurnGuidance() throws {
        launch(heading: 200, pitch: 10)
        enterSceneFromBanner()
        XCTAssertTrue(app.staticTexts["向右转 70°"].waitForExistence(timeout: 5), "应提示向右转 70°")
        snapshot("07-scene-turn-right")
        XCTAssertFalse(app.staticTexts["celebrationTitle"].exists, "未对准时不应触发庆祝")
    }

    /// 朝向与名场面一致并保持一会儿，应触发“就是这个画面！”庆祝
    func testSceneAlignedCelebration() throws {
        launch(heading: 272, pitch: 8)
        enterSceneFromBanner()
        let title = app.staticTexts["celebrationTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 6), "对准并保持后应出现庆祝画面")
        sleep(1)
        snapshot("08-scene-celebration")
    }
}
