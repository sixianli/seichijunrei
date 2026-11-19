import XCTest

/// 端到端测试：每条功能路径从点按钮开始，走到用户能看到的结果为止。
/// 位置固定在「須賀神社」机位（《君の名は。》名场面三）。离它约 700 m 的「信濃町天桥」用来测“远处出发”。
/// 外部链接 / 地图 App 不会真的跳出，地址记在 debugLastURL 里；系统相册选图换成模拟照片。
final class FeatureE2ETests: UITestBase {
    private let suga = "kiminonawa-suga-shrine"
    private let bridge = "kiminonawa-shinanomachi-footbridge"

    private func waitGone(_ element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
        let gone = NSPredicate(format: "exists == false")
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: gone, object: element)], timeout: timeout) == .completed
    }

    private func turnOn(_ toggle: XCUIElement) {
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        scrollTo(toggle)
        if (toggle.value as? String) != "1" { toggle.tap() }
        if (toggle.value as? String) != "1" {
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        }
        XCTAssertEqual(toggle.value as? String, "1", "开关应已打开")
    }

    private func element(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    // MARK: - 首页地图

    /// 类型筛选：选“日剧”后附近卡片里没有动画的名场面；选回“全部”又出现
    func testMapCategoryFilter() throws {
        launch()
        let card = app.buttons["card-\(suga)"]
        XCTAssertTrue(card.waitForExistence(timeout: 20))
        app.buttons["日剧"].firstMatch.tap()
        XCTAssertTrue(waitGone(card), "筛选日剧后不应再显示动画的名场面")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'card-'")).firstMatch
                        .waitForExistence(timeout: 8), "筛选日剧后附近应有日剧的名场面")
        app.buttons["全部"].firstMatch.tap()
        XCTAssertTrue(card.waitForExistence(timeout: 8), "选回全部后应重新出现")
    }

    /// 搜索作品 → 地图聚焦 → 点叉号取消聚焦
    func testSearchFocusAndClear() throws {
        launch()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap()
        typeReliably("your name", into: search)
        let row = app.buttons["work-君の名は。"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        let chip = element("focusChip")
        XCTAssertTrue(chip.waitForExistence(timeout: 5), "选择作品后应显示聚焦提示条")
        // 提示条是滑入的，等它停稳再点叉号
        let clear = app.buttons["clearFocus"]
        XCTAssertTrue(clear.waitForExistence(timeout: 5))
        let settled = NSPredicate(format: "hittable == true")
        _ = XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: settled, object: clear)], timeout: 5)
        sleep(1)
        clear.tap()
        XCTAssertTrue(waitGone(chip, timeout: 10), "点叉号后应取消聚焦")
        let text = (search.value as? String) ?? ""
        XCTAssertTrue(text.isEmpty || text == search.placeholderValue, "取消聚焦后搜索框应清空：\(text)")
    }

    /// “附近的名场面”标题回到我的位置；“开启始终允许”提示可以关掉
    func testCarouselTitleAndAlwaysHint() throws {
        launch()
        let title = app.buttons["carouselTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 20))
        title.tap()
        XCTAssertTrue(app.buttons["card-\(suga)"].waitForExistence(timeout: 5), "回到我的位置后附近卡片仍在")
        let hint = app.buttons["dismissAlwaysHint"]
        if hint.exists {
            hint.tap()
            XCTAssertTrue(waitGone(hint), "点叉号后提示应消失")
        }
    }

    /// 全部名场面列表：筛选后点一行能打开详情页
    func testListOpensDetail() throws {
        launch()
        app.buttons["openList"].tap()
        let search = app.searchFields["日漫 / 日剧 / 日影名称"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        typeReliably("东京爱情", into: search)
        let row = app.staticTexts["月台栏杆上的白手帕"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertTrue(app.buttons["enterScene"].waitForExistence(timeout: 8), "点列表里的名场面应打开详情页")
    }

    // MARK: - 详情页

    /// 展开全文、步行地图放大、校准入口、官网链接
    func testDetailSections() throws {
        launchAtDetail(bridge)
        let toggle = app.buttons["highlightTextToggle"]
        XCTAssertTrue(scrollTo(toggle), "“为什么是名场面”应有展开全文")
        toggle.tap()
        XCTAssertTrue(toggle.label.contains("收起"), "展开后按钮应变成“收起”")

        let route = app.buttons["accessRouteMap"]
        XCTAssertTrue(scrollTo(route), "应有步行小地图")
        route.tap()
        let close = app.buttons["closeRouteMap"]
        XCTAssertTrue(close.waitForExistence(timeout: 5), "点小地图应放大")
        close.tap()

        let calibrate = app.buttons["detailCalibrate"]
        XCTAssertTrue(scrollTo(calibrate))
        calibrate.tap()
        let closeCal = app.buttons["closeCalibration"]
        XCTAssertTrue(closeCal.waitForExistence(timeout: 5), "应打开校准页")
        closeCal.tap()

        let site = app.buttons["officialSite"].exists ? app.buttons["officialSite"] : app.links["officialSite"]
        XCTAssertTrue(scrollTo(site), "关于作品里应有官网链接")
        site.tap()
        let url = lastOpenedURL() ?? ""
        XCTAssertTrue(url.hasPrefix("http"), "应打开作品官网，实际：\(url)")
    }

    /// 看原作画面：列出几条搜索，点一条去图片搜索（英文界面：大字英文、小字日文，按日文搜）
    func testSearchOriginalScene() throws {
        launchAtDetail(bridge, language: "en")
        let button = app.buttons["searchScene"]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        button.tap()
        let option = app.buttons["searchOption"].firstMatch
        XCTAssertTrue(option.waitForExistence(timeout: 5), "应列出搜索词")
        XCTAssertTrue(option.label.contains("Your Name."), "英文界面的说明应是英文：\(option.label)")
        XCTAssertTrue(option.label.contains("君の名は。"), "下面应附上实际搜索的日文：\(option.label)")
        option.tap()
        let url = lastOpenedURL() ?? ""
        XCTAssertTrue(url.contains("google.com/search") && url.contains("tbm=isch"), "应打开 Google 图片搜索：\(url)")
    }

    /// 名场面截图：添加（相册选图）→ 显示 → 删除
    func testSceneScreenshotAddAndDelete() throws {
        launchAtDetail(suga)
        let add = app.buttons["addSceneImage"]
        XCTAssertTrue(scrollTo(add))
        add.tap()
        let delete = app.buttons["deleteSceneImage"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5), "添加后应能删除")
        delete.tap()
        XCTAssertTrue(waitGone(delete), "删除后删除按钮应消失")
    }

    // MARK: - 带我去复现 / 请人帮我拍：远处出发

    /// 远处：选地图 App 导航（步行），换一个地图，开启“快到了提醒我”
    func testJourneyMapAppsAndReminder() throws {
        launchAtDetail(bridge)
        app.buttons["enterScene"].tap()
        let navigate = app.buttons["journeyNavigate"]
        XCTAssertTrue(navigate.waitForExistence(timeout: 8), "离机位 700 m 应显示出发页")
        navigate.tap()
        let google = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Google'")).firstMatch
        XCTAssertTrue(google.waitForExistence(timeout: 5), "应让用户选地图 App")
        google.tap()
        let url = lastOpenedURL() ?? ""
        XCTAssertTrue(url.contains("google.com/maps") && url.contains("walking"), "700 m 应用 Google 地图步行导航：\(url)")

        app.buttons["换一个地图"].tap()
        let apple = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Apple'")).firstMatch
        XCTAssertTrue(apple.waitForExistence(timeout: 5))
        apple.tap()
        let appleURL = lastOpenedURL() ?? ""
        XCTAssertTrue(appleURL.contains("maps.apple.com") && appleURL.contains("dirflg=w"), "换成 Apple 地图后应用 Apple 地图步行导航：\(appleURL)")

        let reminder = app.buttons["journeyReminder"]
        if reminder.exists {
            reminder.tap()
            dismissSystemAlerts(timeout: 5)   // “改为始终允许”
        }
        XCTAssertTrue(app.staticTexts["快到了会提醒你"].waitForExistence(timeout: 8), "开启后应显示已开启提醒")
        app.buttons["closeJourney"].firstMatch.tap()
        // 出发页是从地图上打开的全屏页，关闭后回到地图（和名场面模式一样）
        XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 5), "关闭后回到地图")
        XCTAssertFalse(app.buttons["journeyNavigate"].exists, "出发页应已关闭")
    }

    /// 远处点“请人帮我拍”：同样先出发，标题是“请人帮我拍”
    func testPhotographerFromFarStartsJourney() throws {
        launchAtDetail(bridge)
        let open = app.buttons["openPhotographer"]
        XCTAssertTrue(scrollTo(open))
        open.tap()
        XCTAssertTrue(app.buttons["journeyNavigate"].waitForExistence(timeout: 8), "远处应先出发")
        XCTAssertTrue(app.navigationBars["请人帮我拍"].exists, "出发页标题应是“请人帮我拍”")
    }

    /// 点“快到了”通知回到 App：直接回到指引
    func testNotificationResumesJourney() throws {
        launch(extraEnv: ["SEICHI_OPEN_SPOT": bridge, "SEICHI_OPEN_JOURNEY": "scene"])
        XCTAssertTrue(app.buttons["journeyNavigate"].waitForExistence(timeout: 20), "点通知后应直接回到指引")
    }

    // MARK: - 巡礼者的照片 / 我的投稿

    /// 上传现场照片 → 照片出现在详情页 → “我的投稿”里能看到 → 删除
    func testUploadPhotoThenManageInMySubmissions() throws {
        launchAtDetail(suga)
        let upload = app.buttons["uploadCommunityPhoto"]
        XCTAssertTrue(upload.waitForExistence(timeout: 8))
        let before = app.buttons.matching(identifier: "communityPhoto").count
        upload.tap()
        let caption = element("communityCaption")
        XCTAssertTrue(caption.waitForExistence(timeout: 5), "选图后应打开上传确认页")
        caption.tap()
        caption.typeText("sunny day")
        turnOn(app.switches["communityOwnPhoto"])
        let confirm = app.buttons["communityUploadConfirm"]
        XCTAssertTrue(scrollTo(confirm))
        XCTAssertTrue(confirm.isEnabled, "审核通过并勾选本人拍摄后应能上传")
        confirm.tap()
        XCTAssertTrue(waitGone(confirm, timeout: 10), "上传成功后应关闭确认页")
        let after = app.buttons.matching(identifier: "communityPhoto")
        XCTAssertTrue(after.element(boundBy: before).waitForExistence(timeout: 5), "详情页应多一张照片")

        // 我的投稿
        app.swipeDown(velocity: .fast)
        app.swipeDown(velocity: .fast)
        let settings = app.buttons["openSettings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 8))
        settings.tap()
        let mine = app.buttons["openMySubmissions"]
        XCTAssertTrue(scrollTo(mine))
        mine.tap()
        let row = element("mySubmission-photo")
        XCTAssertTrue(row.waitForExistence(timeout: 5), "我的投稿里应有刚上传的照片")
        let rows = app.descendants(matching: .any).matching(identifier: "mySubmission-photo").count
        row.swipeLeft()
        let swipeDelete = app.buttons["删除"].firstMatch
        XCTAssertTrue(swipeDelete.waitForExistence(timeout: 3), "左滑应出现删除")
        swipeDelete.tap()
        let confirmDelete = app.buttons["删除"].firstMatch
        if confirmDelete.waitForExistence(timeout: 3) { confirmDelete.tap() }
        let left = NSPredicate(format: "count < %d", rows)
        let query = app.descendants(matching: .any).matching(identifier: "mySubmission-photo")
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: left, object: query)], timeout: 8),
                       .completed, "删除后应少一条")
    }

    /// 截图类的照片：审核不通过，说明原因，不能上传
    func testUploadRejectsScreenshot() throws {
        launchAtDetail(suga, extraEnv: ["SEICHI_MODERATION": "screenshot"])
        let upload = app.buttons["uploadCommunityPhoto"]
        XCTAssertTrue(upload.waitForExistence(timeout: 8))
        upload.tap()
        XCTAssertTrue(element("moderationProblem").waitForExistence(timeout: 8), "截图应被拦下并说明原因")
        turnOn(app.switches["communityOwnPhoto"])
        let confirm = app.buttons["communityUploadConfirm"]
        XCTAssertTrue(scrollTo(confirm))
        XCTAssertFalse(confirm.isEnabled, "审核不通过时不能上传")
    }

    /// 投稿新名场面：填完必填项 + 选照片 + 同意规则 → 提交成功 → 我的投稿里能看到
    func testSubmitSceneFullFlow() throws {
        launch(heading: 120)
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap()
        typeReliably("zqxw", into: search)
        let open = app.buttons["openSubmit"]
        XCTAssertTrue(open.waitForExistence(timeout: 10))
        open.tap()
        // 按表单从上到下的顺序填
        for (id, text) in [("submitWorkTitle", "测试作品"), ("submitSceneTitle", "测试名场面"),
                           ("submitStory", "两个人在楼梯上擦肩而过，终于回头问出了那句你叫什么名字。"),
                           ("submitPlaceName", "须贺神社 男坂")] {
            let field = element(id)
            XCTAssertTrue(scrollTo(field), "应有 \(id)")
            field.tap()
            if let v = field.value as? String, !v.isEmpty, v != field.placeholderValue {
                field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: v.count))
            }
            field.typeText(text)
        }
        let photo = app.buttons["submitPhoto"]
        XCTAssertTrue(scrollTo(photo))
        photo.tap()
        turnOn(app.switches["submitAgree"])
        let send = app.buttons["submitSend"]
        XCTAssertTrue(scrollTo(send))
        XCTAssertTrue(send.isEnabled, "必填项都填好后应能提交：\(element("submitMissing").label)")
        send.tap()
        XCTAssertTrue(element("submitDone").waitForExistence(timeout: 10), "提交后应显示已收到")
    }

    // MARK: - 请人帮我拍：标记主角 / 手动快门 / 分享给巡礼者 → 相册

    func testPhotographerManualShotToAlbum() throws {
        launch(heading: 216, pitch: 12, extraEnv: ["SEICHI_SIM_SUBJECT": "0.2,0.6,0.3"])
        let card = app.buttons["card-\(suga)"]
        XCTAssertTrue(card.waitForExistence(timeout: 20))
        card.tap()
        let open = app.buttons["openPhotographer"]
        XCTAssertTrue(scrollTo(open))
        open.tap()
        // 标记主角位置：加一张名场面截图，保存构图
        let mark = app.buttons["markSubject"]
        XCTAssertTrue(mark.waitForExistence(timeout: 8))
        mark.tap()
        let addShot = app.buttons["framingAddScreenshot"]
        XCTAssertTrue(addShot.waitForExistence(timeout: 5), "应打开构图编辑")
        addShot.tap()
        app.buttons["saveFraming"].tap()
        let start = app.buttons["startPhotographer"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()
        dismissSystemAlerts(timeout: 4)
        XCTAssertTrue(app.staticTexts["pgInstruction"].waitForExistence(timeout: 8))
        // 关掉自动拍、切换语音，再手动按快门
        app.buttons["pgAutoShutter"].tap()
        app.buttons["pgVoice"].tap()
        app.buttons["pgShutter"].tap()
        let saved = element("pgSaved")
        if !saved.waitForExistence(timeout: 10) { dismissSystemAlerts(timeout: 3) }
        XCTAssertTrue(saved.waitForExistence(timeout: 10), "手动按快门后应保存")
        // 分享给其他巡礼者：打开上传确认页（App 里拍的直接通过审核）
        app.buttons["pgShareToPilgrims"].tap()
        let confirm = app.buttons["communityUploadConfirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "应打开上传确认页")
        XCTAssertFalse(element("moderationProblem").exists, "App 里拍的照片不应被拦下")
        app.buttons["取消"].firstMatch.tap()
        XCTAssertTrue(waitGone(confirm))
    }

    /// 相册：有照片 → 打开 → 分享 / 分享给巡礼者 / 去这个名场面 → 删除
    func testAlbumPhotoActions() throws {
        // 先用“请人帮我拍”拍一张，存进相册
        launch(heading: 216, pitch: 12, extraEnv: ["SEICHI_SIM_SUBJECT": "0.5,0.85,0.45"])
        XCTAssertTrue(app.buttons["card-\(suga)"].waitForExistence(timeout: 20))
        app.buttons["card-\(suga)"].tap()
        let open = app.buttons["openPhotographer"]
        XCTAssertTrue(scrollTo(open))
        open.tap()
        app.buttons["startPhotographer"].tap()
        dismissSystemAlerts(timeout: 4)
        let saved = element("pgSaved")
        if !saved.waitForExistence(timeout: 15) { dismissSystemAlerts(timeout: 3) }
        XCTAssertTrue(saved.waitForExistence(timeout: 10))
        app.terminate()

        launch()
        let albumButton = app.buttons["openAlbum"]
        XCTAssertTrue(albumButton.waitForExistence(timeout: 10))
        albumButton.tap()
        let photos = app.buttons.matching(identifier: "albumPhoto")
        XCTAssertTrue(photos.firstMatch.waitForExistence(timeout: 5), "相册里应有刚拍的照片")
        let count = photos.count
        photos.firstMatch.tap()
        XCTAssertTrue(element("albumShare").waitForExistence(timeout: 5), "应能分享")
        app.buttons["albumShareToPilgrims"].tap()
        XCTAssertTrue(app.buttons["communityUploadConfirm"].waitForExistence(timeout: 5), "应能分享给巡礼者")
        app.buttons["取消"].firstMatch.tap()
        app.buttons["albumDelete"].tap()
        // 确认框里的“从相册删除”（不是工具栏上同名的垃圾桶按钮）
        app.buttons.matching(NSPredicate(format: "label == '从相册删除' AND identifier != 'albumDelete'")).firstMatch.tap()
        let fewer = NSPredicate(format: "count < %d", count)
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: fewer, object: photos)], timeout: 8),
                       .completed, "删除后相册应少一张")
        if photos.firstMatch.exists {
            photos.firstMatch.tap()
            app.buttons["albumOpenSpot"].tap()
            XCTAssertTrue(app.buttons["enterScene"].waitForExistence(timeout: 8), "“去这个名场面”应打开详情页")
        }
    }

    // MARK: - 名场面模式：分享卡保存、详情页再分享

    func testShareCardSaveAndShareFromDetail() throws {
        launch(heading: 218, pitch: 10, extraEnv: ["SEICHI_SIM_SCENE_IMAGE": "1"])
        enterSceneFromBanner()
        XCTAssertTrue(app.staticTexts["celebrationTitle"].waitForExistence(timeout: 10))
        app.buttons["celebratePhoto"].tap()
        XCTAssertTrue(app.otherElements["shareCard"].waitForExistence(timeout: 8))
        app.buttons["saveCard"].tap()
        dismissSystemAlerts(timeout: 3)
        XCTAssertTrue(app.staticTexts["已保存到相册 📸"].waitForExistence(timeout: 5), "保存后应提示已保存")
        app.buttons["closeShare"].tap()
        app.terminate()

        // 巡礼过的名场面：详情页可以再次分享
        launchAtDetail(suga)
        let share = app.buttons["detailShare"]
        XCTAssertTrue(scrollTo(share), "巡礼完成后详情页应有分享")
        share.tap()
        XCTAssertTrue(app.otherElements["shareCard"].waitForExistence(timeout: 8), "应打开分享卡")
    }

    // MARK: - 设置

    /// 设置里选好默认地图：之后出发直接用它，不再询问
    func testSettingsDefaultMapApp() throws {
        launch(resetMapApp: false)
        app.buttons["openSettings"].tap()
        let picker = app.buttons["settingsMapApp"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        picker.tap()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Google'")).firstMatch.tap()
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        // 选中的值显示在这一行右侧（单独的文字，不在按钮标题里）
        let shown = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Google'")).firstMatch
        XCTAssertTrue(shown.waitForExistence(timeout: 3) || picker.label.contains("Google")
                      || ((picker.value as? String) ?? "").contains("Google"),
                      "设置页应显示已选的 Google 地图：\(picker.label)")
        app.buttons["完成"].firstMatch.tap()

        // 去 700 m 外的天桥：点导航直接打开 Google 地图，不弹选择
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        typeReliably("your name", into: search)
        app.buttons["work-君の名は。"].tap()
        let card = app.buttons["card-\(bridge)"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        card.tap()
        app.buttons["enterScene"].tap()
        let navigate = app.buttons["journeyNavigate"]
        XCTAssertTrue(navigate.waitForExistence(timeout: 8))
        navigate.tap()
        let url = lastOpenedURL() ?? ""
        XCTAssertTrue(url.contains("google.com/maps"), "设了默认地图后应直接用 Google 地图：\(url)")
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Apple'")).firstMatch.exists,
                       "设了默认地图后不应再弹选择")

        // 恢复“每次询问”，不影响别的测试
        app.buttons["closeJourney"].firstMatch.tap()
        app.swipeDown(velocity: .fast)
        app.swipeDown(velocity: .fast)
        if app.buttons["openSettings"].waitForExistence(timeout: 5) {
            app.buttons["openSettings"].tap()
            app.buttons["settingsMapApp"].tap()
            app.buttons["每次询问"].firstMatch.tap()
        }
    }

    /// 付费墙：从地图左上角打开，能看到恢复购买，能关闭
    func testPaywallOpenAndClose() throws {
        launch(entitlement: "free", freeUsed: 0)
        let open = app.buttons["openPaywall"]
        XCTAssertTrue(open.waitForExistence(timeout: 10))
        open.tap()
        XCTAssertTrue(app.buttons["restorePurchases"].waitForExistence(timeout: 8))
        app.buttons["closePaywall"].tap()
        XCTAssertTrue(waitGone(app.buttons["restorePurchases"]), "关闭后付费墙应消失")
    }
}
