import XCTest
@testable import SeichiCore

final class GeoMathTests: XCTestCase {
    let tokyoStation = GeoPoint(latitude: 35.681236, longitude: 139.767125)
    let shinjuku = GeoPoint(latitude: 35.690921, longitude: 139.700258)

    func testDistanceTokyoToShinjuku() {
        // 东京站 ↔ 新宿站 直线约 6.1 km
        XCTAssertEqual(GeoMath.distance(from: tokyoStation, to: shinjuku), 6_130, accuracy: 60)
        XCTAssertEqual(GeoMath.distance(from: tokyoStation, to: tokyoStation), 0, accuracy: 1e-6)
    }

    func testBearingCardinalDirections() {
        let o = GeoPoint(latitude: 35, longitude: 139)
        XCTAssertEqual(GeoMath.bearing(from: o, to: .init(latitude: 35.01, longitude: 139)), 0, accuracy: 0.01)
        XCTAssertEqual(GeoMath.bearing(from: o, to: .init(latitude: 35, longitude: 139.01)), 90, accuracy: 0.01)
        XCTAssertEqual(GeoMath.bearing(from: o, to: .init(latitude: 34.99, longitude: 139)), 180, accuracy: 0.01)
        XCTAssertEqual(GeoMath.bearing(from: o, to: .init(latitude: 35, longitude: 138.99)), 270, accuracy: 0.01)
        // 新宿在东京站西偏北
        XCTAssertEqual(GeoMath.bearing(from: tokyoStation, to: shinjuku), 279.9, accuracy: 1)
    }

    func testSignedDeltaWrapsAround() {
        XCTAssertEqual(GeoMath.signedDelta(from: 350, to: 10), 20)
        XCTAssertEqual(GeoMath.signedDelta(from: 10, to: 350), -20)
        XCTAssertEqual(GeoMath.signedDelta(from: 0, to: 180), 180)
        XCTAssertEqual(GeoMath.signedDelta(from: 90, to: 90), 0)
        XCTAssertEqual(GeoMath.normalize(-30), 330)
        XCTAssertEqual(GeoMath.normalize(725), 5)
        XCTAssertEqual(GeoMath.normalize(-1e-15), 0)
    }

    func testCircularMean() {
        XCTAssertEqual(GeoMath.circularMean([350, 10])!, 0, accuracy: 1e-9)
        XCTAssertNil(GeoMath.circularMean([]))
        XCTAssertEqual(GeoMath.compassIndex(44), 1)
        XCTAssertEqual(GeoMath.compassIndex(359), 0)
        XCTAssertEqual(GeoMath.compassIndex(200), 4)
        XCTAssertEqual(GeoMath.compassIndex(315), 7)
    }
}

final class SceneGuidanceTests: XCTestCase {
    func testTurnDirection() {
        let g = SceneGuidance.compute(deviceHeading: 0, devicePitch: nil, sceneHeading: 90, scenePitch: nil)
        XCTAssertEqual(g.turn, .right)
        XCTAssertEqual(g.yawDelta, 90)
        XCTAssertEqual(g.yawDegrees, 90)

        let l = SceneGuidance.compute(deviceHeading: 30, devicePitch: nil, sceneHeading: 300, scenePitch: nil)
        XCTAssertEqual(l.turn, .left)
        XCTAssertEqual(l.yawDelta, -90)
    }

    func testAlignedAcrossNorth() {
        let g = SceneGuidance.compute(deviceHeading: 355, devicePitch: 5, sceneHeading: 3, scenePitch: 0)
        XCTAssertTrue(g.isAligned)
        XCTAssertGreaterThan(g.alignment, 0.98)
    }

    func testPitchGuidance() {
        let g = SceneGuidance.compute(deviceHeading: 100, devicePitch: -5, sceneHeading: 100, scenePitch: 30)
        XCTAssertEqual(g.turn, .aligned)
        XCTAssertEqual(g.tilt, .up)
        XCTAssertFalse(g.isAligned)
        XCTAssertEqual(g.pitchDegrees, 35)
    }

    func testPoorCompassWidensTolerance() {
        let strict = SceneGuidance.compute(deviceHeading: 0, devicePitch: nil, sceneHeading: 15, scenePitch: nil, headingAccuracy: 0)
        let loose = SceneGuidance.compute(deviceHeading: 0, devicePitch: nil, sceneHeading: 15, scenePitch: nil, headingAccuracy: 30)
        XCTAssertEqual(strict.turn, .right)
        XCTAssertEqual(loose.turn, .aligned)
    }

    func testAlignmentLatchRequiresHoldAndHysteresis() {
        var latch = AlignmentLatch(holdDuration: 1.0)
        let on = SceneGuidance.compute(deviceHeading: 0, devicePitch: nil, sceneHeading: 2, scenePitch: nil)
        let nearEdge = SceneGuidance.compute(deviceHeading: 0, devicePitch: nil, sceneHeading: 15, scenePitch: nil)
        let off = SceneGuidance.compute(deviceHeading: 0, devicePitch: nil, sceneHeading: 40, scenePitch: nil)

        XCTAssertFalse(latch.update(guidance: on, at: 0))
        XCTAssertFalse(latch.update(guidance: on, at: 0.5))
        XCTAssertTrue(latch.update(guidance: on, at: 1.1))   // 刚锁定，只触发一次
        XCTAssertFalse(latch.update(guidance: on, at: 1.5))
        XCTAssertTrue(latch.isLocked)
        _ = latch.update(guidance: nearEdge, at: 2)          // 轻微偏离不解锁
        XCTAssertTrue(latch.isLocked)
        _ = latch.update(guidance: off, at: 3)
        XCTAssertFalse(latch.isLocked)
    }

    func testHeadingSmootherWrapsNorth() {
        var s = HeadingSmoother(factor: 0.5)
        XCTAssertEqual(s.add(350), 350)
        XCTAssertEqual(s.add(10), 0, accuracy: 1e-9)   // 不应该平均成 180
    }
}

final class CatalogTests: XCTestCase {
    func testNearbySortingAndArrival() {
        let user = GeoPoint(latitude: 35.0, longitude: 135.0)
        let near = Spot(id: "a", work: "A", placeName: "p", sceneTitle: "s", story: "",
                        coordinate: .init(latitude: 35.0001, longitude: 135.0), sceneHeading: 0, arrivalRadius: 20)
        let far = Spot(id: "b", work: "B", placeName: "p", sceneTitle: "s", story: "",
                       coordinate: .init(latitude: 35.1, longitude: 135.0), sceneHeading: 0)
        let result = NearbySearch.nearby([far, near], from: user, within: 5_000)
        XCTAssertEqual(result.map(\.id), ["a"])
        XCTAssertTrue(result[0].hasArrived())
        XCTAssertEqual(result[0].bearing, 0, accuracy: 0.01)
        XCTAssertEqual(NearbySearch.formatDistance(842.4), "842 m")
        XCTAssertEqual(NearbySearch.formatDistance(1530), "1.5 km")
    }

    func testDecodeRejectsDuplicates() throws {
        let json = """
        [{"id":"x","work":"W","placeName":"P","sceneTitle":"S","story":"..","latitude":35,"longitude":139,"sceneHeading":-90},
         {"id":"x","work":"W","placeName":"P","sceneTitle":"S","story":"..","latitude":35,"longitude":139,"sceneHeading":0}]
        """
        XCTAssertThrowsError(try SpotCatalog.decode(Data(json.utf8))) { error in
            XCTAssertEqual(error as? SpotCatalog.CatalogError, .duplicateID("x"))
        }
    }

    /// 新版 catalog 格式：作品信息合并进每个名场面，各语言文案进入 translations。
    func testDecodeCatalogFormat() throws {
        let json = """
        {"works":[{"id":"totoro","title":"となりのトトロ","mediaType":"animeFilm","year":1988,
                   "creator":"宮崎駿","tint":"#3E8E5A","aliases":["My Neighbor Totoro"],
                   "text":{"zh-Hans":{"title":"龙猫","creator":"宫崎骏","synopsis":"简介"},
                           "ja":{"title":"","synopsis":"あらすじ"},
                           "en":{"title":"My Neighbor Totoro","creator":"Hayao Miyazaki","synopsis":"Synopsis"}}}],
         "spots":[{"id":"totoro-a","workID":"totoro","latitude":35.78,"longitude":139.42,"sceneHeading":-90,
                   "arrivalRadius":60,"spoiler":true,
                   "photo":{"url":"https://upload.wikimedia.org/x.jpg","author":"A","license":"CC BY-SA 4.0"},
                   "text":{"zh-Hans":{"placeName":"地点","sceneTitle":"场景","episode":"剧场版","highlight":"看点",
                                      "story":"剧情","access":"交通","bestTime":"夏天","tips":"贴士"},
                           "en":{"placeName":"Place","sceneTitle":"Scene","story":"Story","access":"Access"}}}]}
        """
        let spots = try SpotCatalog.decode(Data(json.utf8))
        XCTAssertEqual(spots.count, 1)
        let s = spots[0]
        XCTAssertEqual(s.workID, "totoro")
        XCTAssertEqual(s.work, "となりのトトロ")
        XCTAssertEqual(s.workLocalized, "龙猫")
        XCTAssertEqual(s.mediaType.category, .anime)
        XCTAssertEqual(s.sceneHeading, 270)
        XCTAssertEqual(s.trivia, "贴士")
        XCTAssertEqual(s.highlight, "看点")
        XCTAssertTrue(s.spoiler)
        XCTAssertEqual(s.photo?.license, "CC BY-SA 4.0")
        XCTAssertEqual(s.year, 1988)
        XCTAssertEqual(s.creator, "宫崎骏")
        let en = s.localized(to: "en")
        XCTAssertEqual(en.workLocalized, "My Neighbor Totoro")
        XCTAssertEqual(en.access, "Access")
        XCTAssertEqual(en.bestTime, "夏天")                 // 缺翻译时沿用基础内容
        XCTAssertEqual(en.creator, "Hayao Miyazaki")
        XCTAssertNil(s.localized(to: "ja").workLocalized)
        XCTAssertEqual(s.localized(to: "ja").synopsis, "あらすじ")
        XCTAssertEqual(SpotSearch.search("龙猫", in: spots).first?.workID, "totoro")
    }

    func testCatalogRejectsUnknownWork() {
        let json = """
        {"works":[],"spots":[{"id":"a","workID":"nope","latitude":35,"longitude":139,"sceneHeading":0,
          "text":{"zh-Hans":{"placeName":"p","sceneTitle":"s","story":"x"}}}]}
        """
        XCTAssertThrowsError(try SpotCatalog.decode(Data(json.utf8))) { error in
            XCTAssertEqual(error as? SpotCatalog.CatalogError, .unknownWork(spot: "a", work: "nope"))
        }
    }

    /// 校验 App 内置的圣地数据（tools/catalog.py 生成的 catalog.json）可以正确解码。
    func testBundledCatalogIsValid() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("SeichiJunrei/Resources/catalog.json")
        let spots = try SpotCatalog.decode(Data(contentsOf: url))
        XCTAssertGreaterThanOrEqual(spots.count, 60)
        for s in spots {
            XCTAssertTrue((0..<360).contains(s.sceneHeading), s.id)
            XCTAssertTrue((24...46).contains(s.coordinate.latitude), "\(s.id) 不在日本范围内")
            XCTAssertTrue((122...154).contains(s.coordinate.longitude), "\(s.id) 不在日本范围内")
            XCTAssertFalse(s.story.isEmpty, s.id)
            XCTAssertNotNil(s.highlight, s.id)
            XCTAssertNotNil(s.access, s.id)
            XCTAssertNotNil(s.synopsis, s.id)
            // 多语言：每个名场面都有 4 种语言
            XCTAssertEqual(Set(s.translations.keys), ["zh-Hant", "ja", "en", "ko"], s.id)
            for lang in ["zh-Hant", "ja", "en", "ko"] {
                let l = s.localized(to: lang)
                XCTAssertNotEqual(l.story, s.story, "\(s.id) 缺少 \(lang) 剧情")
                XCTAssertNotEqual(l.access, s.access, "\(s.id) 缺少 \(lang) 交通")
            }
        }
        // 编码 → 解码往返
        let round = try SpotCatalog.decode(JSONEncoder().encode(spots))
        XCTAssertEqual(round, spots)

        // 老版本用户的巡礼记录以 id 为键，这些 id 必须保留
        let ids = Set(spots.map(\.id))
        for id in ["kiminonawa-suga-shrine", "slamdunk-kamakurakokomae", "tokyolovestory-baishinji",
                   "hanataba-meidaimae", "yurucamp-motosu", "amachan-kosode"] {
            XCTAssertTrue(ids.contains(id), "缺少旧数据 \(id)")
        }

        // 用真实数据验证搜索
        XCTAssertEqual(SpotSearch.search("灌篮高手", in: spots).first?.work, "SLAM DUNK")
        XCTAssertEqual(SpotSearch.search("slam dunk", in: spots).first?.work, "SLAM DUNK")
        XCTAssertEqual(SpotSearch.search("东京爱情故事", in: spots).first?.mediaType, .drama)
        XCTAssertEqual(SpotSearch.search("花束", in: spots).first?.mediaType, .film)
        XCTAssertEqual(SpotSearch.search("龙猫", in: spots).first?.work, "となりのトトロ")
        XCTAssertEqual(SpotSearch.search("너의 이름은", in: spots).first?.work, "君の名は。")
        XCTAssertEqual(SpotSearch.search("Laid-Back Camp", in: spots).first?.work, "ゆるキャン△")
        XCTAssertEqual(SpotSearch.search("灌籃高手", in: spots).first?.work, "SLAM DUNK")
        XCTAssertTrue(Set(SpotSearch.search("新海诚", in: spots).map(\.work))
            .isSuperset(of: ["君の名は。", "天気の子", "秒速5センチメートル"]))
        for category in MediaCategory.allCases {
            XCTAssertGreaterThanOrEqual(SpotSearch.search("", in: spots, category: category).count, 8,
                                        "\(category) 类作品太少")
        }
    }
}

final class CameraOrientationTests: XCTestCase {
    // 日本附近的地磁场：水平分量约 30μT，向下分量约 35μT
    func field(north: Vector3, down: Vector3) -> Vector3 { north * 30 + down * 35 }

    func testUprightFacingNorth() throws {
        // 竖持手机，摄像头朝北：设备 -z = 北，-y = 下
        let down = Vector3(0, -1, 0), north = Vector3(0, 0, -1)
        let r = try XCTUnwrap(CameraOrientation.compute(gravity: down, magneticField: field(north: north, down: down)))
        XCTAssertEqual(r.magneticHeading, 0, accuracy: 1e-6)
        XCTAssertEqual(r.pitch, 0, accuracy: 1e-6)
        XCTAssertFalse(r.usedTopEdgeFallback)
    }

    func testUprightFacingEast() throws {
        // 摄像头朝东时，屏幕右侧（+x）指向南，所以北 = -x
        let down = Vector3(0, -1, 0), north = Vector3(-1, 0, 0)
        let r = try XCTUnwrap(CameraOrientation.compute(gravity: down, magneticField: field(north: north, down: down)))
        XCTAssertEqual(r.magneticHeading, 90, accuracy: 1e-6)
    }

    func testUprightFacingSouthWest() throws {
        // 摄像头朝西南(225°)：北 在设备坐标里 = 0.707*(+x) + 0.707*(+z)
        let down = Vector3(0, -1, 0)
        let s = 1 / 2.0.squareRoot()
        let north = Vector3(s, 0, s)
        let r = try XCTUnwrap(CameraOrientation.compute(gravity: down, magneticField: field(north: north, down: down)))
        XCTAssertEqual(r.magneticHeading, 225, accuracy: 1e-6)
    }

    func testTiltedUpThirtyDegrees() throws {
        // 摄像头朝北并上仰 30°：绕 x 轴旋转后，重力在设备坐标中的分量
        let a = GeoMath.radians(30)
        let down = Vector3(0, -cos(a), sin(a))
        let north = Vector3(0, sin(a), -cos(a))
        let r = try XCTUnwrap(CameraOrientation.compute(gravity: down, magneticField: field(north: north, down: down)))
        XCTAssertEqual(r.pitch, 30, accuracy: 1e-6)
        XCTAssertEqual(r.magneticHeading, 0, accuracy: 1e-6)
    }

    func testFlatOnTableUsesTopEdge() throws {
        // 平放、屏幕朝上、手机顶部指向东
        let down = Vector3(0, 0, -1), north = Vector3(-1, 0, 0)
        let r = try XCTUnwrap(CameraOrientation.compute(gravity: down, magneticField: field(north: north, down: down)))
        XCTAssertTrue(r.usedTopEdgeFallback)
        XCTAssertEqual(r.pitch, -90, accuracy: 1e-6)
        XCTAssertEqual(r.magneticHeading, 90, accuracy: 1e-6)
    }

    func testDegenerateInputReturnsNil() {
        XCTAssertNil(CameraOrientation.compute(gravity: Vector3(0, 0, 0), magneticField: Vector3(1, 0, 0)))
        // 磁场与重力平行（磁极附近）无法确定方向
        XCTAssertNil(CameraOrientation.compute(gravity: Vector3(0, -1, 0), magneticField: Vector3(0, -40, 0)))
    }
}

final class ViewfinderProjectionTests: XCTestCase {
    func testCenterAndEdges() throws {
        let fov = ViewfinderProjection.FieldOfView(horizontal: 40, vertical: 70)
        let c = try XCTUnwrap(ViewfinderProjection.project(yawDelta: 0, pitchDelta: 0, fov: fov))
        XCTAssertEqual(c.x, 0); XCTAssertEqual(c.y, 0)
        let right = try XCTUnwrap(ViewfinderProjection.project(yawDelta: 20, pitchDelta: 0, fov: fov))
        XCTAssertEqual(right.x, 1, accuracy: 1e-9)          // 恰好在右边缘
        let up = try XCTUnwrap(ViewfinderProjection.project(yawDelta: 0, pitchDelta: 35, fov: fov))
        XCTAssertEqual(up.y, 1, accuracy: 1e-9)
        XCTAssertNil(ViewfinderProjection.project(yawDelta: 120, pitchDelta: 0, fov: fov))
    }

    func testVisibleFOVForTallPortraitScreen() {
        // 4:3 传感器、长边 69°，放进 9:19.5 的竖屏：上下完整，左右被裁切
        let f = ViewfinderProjection.visibleFieldOfView(sensorFOV: 69, sensorAspect: 4.0 / 3.0,
                                                        viewWidth: 390, viewHeight: 845)
        XCTAssertEqual(f.vertical, 69, accuracy: 1e-9)
        XCTAssertEqual(f.horizontal, 35.2, accuracy: 0.5)
        // 宽屏视图：左右完整，上下被裁切
        let w = ViewfinderProjection.visibleFieldOfView(sensorFOV: 69, sensorAspect: 4.0 / 3.0,
                                                        viewWidth: 900, viewHeight: 900)
        XCTAssertEqual(w.horizontal, 54.5, accuracy: 0.5)
        XCTAssertLessThan(w.vertical, 69)
    }
}

final class SpotSearchTests: XCTestCase {
    func spot(_ id: String, _ work: String, _ cn: String? = nil, _ type: MediaType = .anime,
              aliases: [String] = [], scene: String = "场景", place: String = "地点",
              lat: Double = 35, lon: Double = 139) -> Spot {
        Spot(id: id, work: work, workLocalized: cn, mediaType: type, aliases: aliases, placeName: place,
             sceneTitle: scene, story: "s", coordinate: .init(latitude: lat, longitude: lon), sceneHeading: 0)
    }

    lazy var catalog: [Spot] = [
        spot("k1", "君の名は。", "你的名字。", .animeFilm, aliases: ["Your Name", "Kimi no Na wa"],
             scene: "阶梯上的重逢", place: "須賀神社", lat: 35.68, lon: 139.72),
        spot("k2", "君の名は。", "你的名字。", .animeFilm, aliases: ["Your Name"],
             scene: "寻找糸守町", place: "飛騨古川駅", lat: 36.24, lon: 137.19),
        spot("y1", "ゆるキャン△", "摇曳露营△", .anime, aliases: ["Yuru Camp", "Laid-Back Camp"],
             scene: "夜空下的富士山", place: "本栖湖"),
        spot("t1", "東京ラブストーリー", "东京爱情故事", .drama, aliases: ["Tokyo Love Story"],
             scene: "月台上的手帕", place: "梅津寺駅"),
        spot("h1", "花束みたいな恋をした", "花束般的恋爱", .film, scene: "错过末班车的夜晚", place: "明大前駅"),
    ]

    func testNormalize() {
        XCTAssertEqual(SpotSearch.normalize("君の名は。"), SpotSearch.normalize("君の名は"))
        XCTAssertEqual(SpotSearch.normalize("ゆるキャン△"), "ゆるきゃん")
        XCTAssertEqual(SpotSearch.normalize("ＹＯＵＲ　Name"), "yourname")
        XCTAssertEqual(SpotSearch.normalize("らき☆すた"), "らきすた")
        XCTAssertEqual(SpotSearch.normalize("スラムダンク"), "すらむだんく")
        XCTAssertEqual(SpotSearch.normalize("ラブライブ！"), "らぶらいぶ")
    }

    func testSearchByJapaneseChineseEnglish() {
        for q in ["君の名は", "你的名字", "your name", "YourName", "kimi no na wa", "君の"] {
            let r = SpotSearch.search(q, in: catalog)
            XCTAssertEqual(r.first?.work, "君の名は。", "query: \(q)")
            XCTAssertEqual(r.first?.spots.count, 2, "作品名匹配应返回全部名场面：\(q)")
        }
    }

    func testKatakanaHiraganaInterchangeable() {
        XCTAssertEqual(SpotSearch.search("ゆるきゃん", in: catalog).first?.work, "ゆるキャン△")
        XCTAssertEqual(SpotSearch.search("らぶすとーりー", in: catalog).first?.work,
                       "東京ラブストーリー")
    }

    func testSceneOrPlaceMatchReturnsOnlyThatSpot() {
        let r = SpotSearch.search("飛騨", in: catalog)
        XCTAssertEqual(r.count, 1)
        XCTAssertEqual(r[0].spots.map(\.id), ["k2"])
    }

    func testWorkMatchRanksAboveSceneMatch() {
        // “东京” 既是《东京爱情故事》作品名前缀，也可能出现在其他地点
        let cat = catalog + [spot("x", "某作品", place: "东京塔")]
        let r = SpotSearch.search("东京", in: cat)
        XCTAssertEqual(r.map(\.work), ["東京ラブストーリー", "某作品"])
    }

    func testMediaTypeFilterAndEmptyQuery() {
        XCTAssertEqual(SpotSearch.search("", in: catalog).map(\.work),
                       ["君の名は。", "ゆるキャン△", "東京ラブストーリー", "花束みたいな恋をした"])
        XCTAssertEqual(SpotSearch.search("", in: catalog, category: .drama).map(\.work), ["東京ラブストーリー"])
        XCTAssertTrue(SpotSearch.search("你的名字", in: catalog, category: .drama).isEmpty)
        // 动画电影归入“日漫”
        XCTAssertEqual(SpotSearch.search("", in: catalog, category: .anime).map(\.work), ["君の名は。", "ゆるキャン△"])
        XCTAssertTrue(SpotSearch.search("不存在的作品", in: catalog).isEmpty)
    }

    func testBoundingBox() throws {
        let box = try XCTUnwrap(SpotSearch.boundingBox(of: Array(catalog.prefix(2))))
        XCTAssertEqual(box.minLat, 35.68); XCTAssertEqual(box.maxLat, 36.24)
        XCTAssertEqual(box.minLon, 137.19); XCTAssertEqual(box.maxLon, 139.72)
        XCTAssertNil(SpotSearch.boundingBox(of: []))
    }
}

final class LocalizationTests: XCTestCase {
    let spot = Spot(id: "k", work: "君の名は。", workLocalized: "你的名字。", placeName: "須賀神社（东京）",
                    sceneTitle: "阶梯上的重逢", episode: "剧场版", story: "中文剧情", trivia: "中文贴士",
                    coordinate: .init(latitude: 35, longitude: 139), sceneHeading: 0,
                    translations: [
                        "en": SpotTranslation(workLocalized: "Your Name.", placeName: "Suga Shrine",
                                              sceneTitle: "Reunion on the stairs", story: "English story"),
                        "ja": SpotTranslation(workLocalized: "", sceneTitle: "階段での再会"),
                        "ko": SpotTranslation(workLocalized: "너의 이름은."),
                    ])

    func testLocalizedReplacesOnlyProvidedFields() {
        let en = spot.localized(to: "en")
        XCTAssertEqual(en.workLocalized, "Your Name.")
        XCTAssertEqual(en.sceneTitle, "Reunion on the stairs")
        XCTAssertEqual(en.story, "English story")
        XCTAssertEqual(en.trivia, "中文贴士")              // 没有翻译的字段沿用基础内容
        XCTAssertEqual(en.translations.count, 3)            // 翻译保留，供搜索使用

        let ja = spot.localized(to: "ja")
        XCTAssertNil(ja.workLocalized)                      // 日语环境下不显示译名
        XCTAssertEqual(ja.sceneTitle, "階段での再会")
        XCTAssertEqual(ja.displayWork, "君の名は。")

        XCTAssertEqual(spot.localized(to: "zh-Hans"), spot)
        XCTAssertEqual(spot.localized(to: "fr"), spot)      // 没有该语言时不变
        XCTAssertEqual(spot.localized(to: "en-GB").sceneTitle, "Reunion on the stairs")
    }

    func testLanguageFamily() {
        XCTAssertEqual(Spot.languageFamily("en-US"), "en")
        XCTAssertEqual(Spot.languageFamily("zh-Hant-TW"), "zh-Hant")
        XCTAssertEqual(Spot.languageFamily("zh-TW"), "zh-Hant")
        XCTAssertEqual(Spot.languageFamily("zh-CN"), "zh-Hans")
        XCTAssertEqual(Spot.languageFamily("ja_JP"), "ja")
    }

    func testSearchMatchesTranslatedTitles() {
        XCTAssertEqual(SpotSearch.search("너의 이름은", in: [spot]).first?.work, "君の名は。")
        XCTAssertEqual(SpotSearch.search("reunion", in: [spot]).first?.spots.count, 1)
        // 编码往返保留翻译
        let data = try! JSONEncoder().encode([spot])
        XCTAssertEqual(try! SpotCatalog.decode(data), [spot])
    }
}

final class MonetizationTests: XCTestCase {
    let cal = Calendar(identifier: .gregorian)
    func day(_ d: Int) -> Date { cal.date(from: DateComponents(timeZone: TimeZone(identifier: "UTC"), year: 2026, month: 11, day: d, hour: 12))! }

    func testPassExpiryStacksConsecutivePurchases() {
        XCTAssertNil(AccessPolicy.passExpiry([], calendar: cal))
        XCTAssertEqual(AccessPolicy.passExpiry([.init(purchaseDate: day(1), days: 7)], calendar: cal), day(8))
        // 第 3 天再买 7 天：从第 8 天顺延到第 15 天
        XCTAssertEqual(AccessPolicy.passExpiry([.init(purchaseDate: day(3), days: 7),
                                                .init(purchaseDate: day(1), days: 7)], calendar: cal), day(15))
        // 过期后再买：从购买当天重新计算
        XCTAssertEqual(AccessPolicy.passExpiry([.init(purchaseDate: day(1), days: 7),
                                                .init(purchaseDate: day(20), days: 30)], calendar: cal),
                       cal.date(byAdding: .day, value: 30, to: day(20)))
    }

    func testEntitlementPriority() {
        XCTAssertEqual(AccessPolicy.entitlement(now: day(5), hasLifetime: true, passExpiry: nil, freeUsed: 9), .lifetime)
        XCTAssertEqual(AccessPolicy.entitlement(now: day(5), hasLifetime: false, passExpiry: day(8), freeUsed: 3), .pass(until: day(8)))
        XCTAssertEqual(AccessPolicy.entitlement(now: day(9), hasLifetime: false, passExpiry: day(8), freeUsed: 1), .free(remaining: 2))
        XCTAssertEqual(AccessPolicy.entitlement(now: day(9), hasLifetime: false, passExpiry: nil, freeUsed: 5), .free(remaining: 0))
        // 收费关闭（免费公测期）：额度用完也不受限制
        let beta = AccessPolicy.entitlement(now: day(9), hasLifetime: false, passExpiry: nil, freeUsed: 5, paywallEnabled: false)
        XCTAssertEqual(beta, .complimentary)
        XCTAssertTrue(beta.isUnlimited)
        XCTAssertTrue(FreeSceneAllowance(usedSpotIDs: ["a", "b", "c"]).canEnter("z", entitlement: beta))
    }

    func testFreeAllowanceCountsDistinctSpots() {
        var a = FreeSceneAllowance(limit: 2)
        XCTAssertTrue(a.consume("a"))
        XCTAssertTrue(a.consume("a"))        // 重复进入不扣次数
        XCTAssertTrue(a.consume("b"))
        XCTAssertEqual(a.remaining, 0)
        XCTAssertFalse(a.canEnter("c"))
        XCTAssertFalse(a.consume("c"))
        XCTAssertTrue(a.canEnter("a"))       // 体验过的仍可再进
        XCTAssertTrue(a.canEnter("c", entitlement: .lifetime))
        XCTAssertTrue(a.canEnter("c", entitlement: .pass(until: day(30))))
        XCTAssertFalse(a.canEnter("c", entitlement: .free(remaining: 0)))
        // 持久化往返
        let data = try! JSONEncoder().encode(a)
        XCTAssertEqual(try! JSONDecoder().decode(FreeSceneAllowance.self, from: data), a)
    }
}

final class PilgrimageTests: XCTestCase {
    func testMarkCompletedKeepsFirstDateAndUpdatesPhoto() {
        var log = PilgrimageLog()
        let d1 = Date(timeIntervalSince1970: 1_000), d2 = Date(timeIntervalSince1970: 2_000)
        log.markCompleted(.init(spotID: "a", date: d1, heading: 270))
        log.markCompleted(.init(spotID: "a", date: d2, heading: 10, latitude: 35, longitude: 139, photoFileName: "p1.jpg"))
        let r = log.record(for: "a")!
        XCTAssertEqual(r.date, d1, "保留第一次达成的日期")
        XCTAssertEqual(r.heading, 270)
        XCTAssertEqual(r.latitude, 35)
        XCTAssertEqual(r.photoFileName, "p1.jpg")
        XCTAssertEqual(log.completedCount, 1)

        XCTAssertEqual(log.setPhoto("p2.jpg", for: "a"), "p1.jpg", "返回旧照片以便删除")
        XCTAssertNil(log.setPhoto("x.jpg", for: "unknown"))
        let data = try! JSONEncoder().encode(log)
        XCTAssertEqual(try! JSONDecoder().decode(PilgrimageLog.self, from: data), log)
    }

    func testHashtags() {
        XCTAssertEqual(ShareFormatting.hashtag("君の名は。"), "#君の名は")
        XCTAssertEqual(ShareFormatting.hashtag("Your Name."), "#YourName")
        XCTAssertEqual(ShareFormatting.hashtag("らき☆すた"), "#らきすた")
        XCTAssertEqual(ShareFormatting.hashtag("SLAM DUNK"), "#SLAMDUNK")
        XCTAssertNil(ShareFormatting.hashtag("☆。！"))
        XCTAssertEqual(ShareFormatting.hashtags(["聖地巡礼", "君の名は。", nil, "君の名は"]), ["#聖地巡礼", "#君の名は"])
        XCTAssertEqual(ShareFormatting.coordinate(latitude: 35.68540, longitude: 139.72271), "35.6854°N 139.7227°E")
        XCTAssertEqual(ShareFormatting.coordinate(latitude: -33.9, longitude: -70.5), "33.9000°S 70.5000°W")
    }
}

final class CalibrationTests: XCTestCase {
    let listed = GeoPoint(latitude: 35.68540, longitude: 139.72265)

    func reading(acc: Double = 5, heading: Double? = 270, hAcc: Double = 8,
                 lat: Double = 35.68541, lon: Double = 139.72266) -> CalibrationReading {
        CalibrationReading(latitude: lat, longitude: lon, horizontalAccuracy: acc,
                           heading: heading, headingAccuracy: hAcc, pitch: 10)
    }

    func testGoodReadingHasNoIssues() {
        XCTAssertEqual(CalibrationQuality.issues(for: reading(), listed: listed), [])
        XCTAssertTrue(CalibrationQuality.isGood(reading(), listed: listed))
        XCTAssertTrue(CalibrationQuality.canSubmit(reading()))
    }

    func testPoorSensorsAreReported() {
        let r = reading(acc: 40, hAcc: 35)
        XCTAssertEqual(CalibrationQuality.issues(for: r, listed: listed), [.poorGPS(40), .poorCompass(35)])
        XCTAssertFalse(CalibrationQuality.isGood(r, listed: listed))
        XCTAssertTrue(CalibrationQuality.canSubmit(r), "精度差也允许提交，由开发者筛选")
        XCTAssertEqual(CalibrationQuality.issues(for: reading(heading: nil), listed: listed), [.noHeading])
        XCTAssertFalse(CalibrationQuality.canSubmit(reading(heading: nil)))
        XCTAssertFalse(CalibrationQuality.canSubmit(reading(acc: -1)))
    }

    func testFarFromListedIsOnlyAWarning() {
        // 现有坐标可能偏差很大（例如 2km），用户在真实机位提交时只提示、不阻止
        let r = reading(lat: 35.70340, lon: 139.72265)
        let issues = CalibrationQuality.issues(for: r, listed: listed)
        XCTAssertEqual(issues.count, 1)
        guard case .farFromListed(let d) = issues[0] else { return XCTFail() }
        XCTAssertEqual(d, 2_000, accuracy: 30)
        XCTAssertTrue(CalibrationQuality.isGood(r, listed: listed))
    }

    func testSubmissionTrimsNoteAndRoundTrips() throws {
        let s = CalibrationSubmission(spotID: "x", reading: reading(), note: String(repeating: "あ", count: 800),
                                      appVersion: "0.1.0 (5)", locale: "ja_JP")
        XCTAssertEqual(s.note.count, 500)
        let data = try JSONEncoder().encode(s)
        XCTAssertEqual(try JSONDecoder().decode(CalibrationSubmission.self, from: data), s)
    }
}

final class FramingGuidanceTests: XCTestCase {
    let target = SubjectFraming(centerX: 0.5, footY: 0.85, height: 0.4)
    let vfov = 60.0, hfov = 48.0

    func guide(_ box: UnitRect?, yaw: Double? = 0, pitch: Double? = 0) -> FramingGuidance {
        FramingGuidance.compute(target: target, subject: box, headingDelta: yaw, pitchDelta: pitch,
                                verticalFOV: vfov, horizontalFOV: hfov)
    }

    func box(cx: Double = 0.5, foot: Double = 0.85, h: Double = 0.4) -> UnitRect {
        UnitRect(x: cx - 0.08, y: foot - h, width: 0.16, height: h)
    }

    func testTurnFirstThenFindSubject() {
        XCTAssertEqual(guide(box(), yaw: 40).step, .turn(degrees: 40))
        XCTAssertEqual(guide(nil).step, .findSubject)
    }

    func testPerfectWhenEverythingMatches() {
        let g = guide(box())
        XCTAssertEqual(g.step, .perfect)
        XCTAssertEqual(g.score, 1)
        // 身高 1.65m 占 60° 视场的 40% → 约 3.6m
        XCTAssertEqual(g.estimatedDistance ?? 0, 3.57, accuracy: 0.05)
    }

    func testSubjectTooBigMeansStepBack() {
        // 人物占 80%：太近，需要退到两倍距离
        guard case .moveBack(let m) = guide(box(foot: 0.95, h: 0.8)).step else { return XCTFail() }
        XCTAssertEqual(m, 2, accuracy: 0.51)
        guard case .moveCloser = guide(box(h: 0.2)).step else { return XCTFail() }
    }

    func testSidestepTowardsTheSubject() {
        guard case .sidestep(let m) = guide(box(cx: 0.7)).step else { return XCTFail() }
        XCTAssertGreaterThan(m, 0, "人物偏右 → 拍照的人往右走")
        guard case .sidestep(let l) = guide(box(cx: 0.3)).step else { return XCTFail() }
        XCTAssertLessThan(l, 0)
    }

    func testTiltThenHeight() {
        XCTAssertEqual(guide(box(), pitch: 15).step, .tilt(degrees: 15))
        XCTAssertEqual(guide(box(foot: 0.65)).step, .raise, "脚在画面中偏高 → 把相机举高")
        XCTAssertEqual(guide(box(foot: 0.98)).step, .lower)
    }

    func testAutoZoomAbsorbsSmallSizeErrors() {
        // 人物偏小 1.5 倍：在自动变焦范围内，不提示走动
        let g = FramingGuidance.compute(target: target, subject: box(foot: 0.85, h: 0.27), headingDelta: 0,
                                        pitchDelta: 0, verticalFOV: vfov, horizontalFOV: hfov,
                                        zoomCorrectable: 0.8...2.0)
        if case .moveCloser = g.step { XCTFail("自动变焦能处理，不应让拍照的人走动") }
    }

    func testAutoReframeMovesSubjectToTarget() throws {
        let subject = UnitRect(x: 0.35, y: 0.4, width: 0.1, height: 0.3)
        let crop = try XCTUnwrap(AutoReframe.cropRect(subject: subject, target: target))
        XCTAssertEqual(crop.width, 0.75, accuracy: 1e-9)
        // 裁切后人物中心与脚底应落在目标位置
        XCTAssertEqual((subject.midX - crop.x) / crop.width, target.centerX, accuracy: 0.01)
        XCTAssertEqual((subject.maxY - crop.y) / crop.height, target.footY, accuracy: 0.01)
        XCTAssertNil(AutoReframe.cropRect(subject: box(), target: target))
    }

    func testFramingFromBoxRoundTrips() {
        let f = SubjectFraming(box: UnitRect(x: 0.2, y: 0.3, width: 0.2, height: 0.5))
        XCTAssertEqual(f.centerX, 0.3, accuracy: 1e-9)
        XCTAssertEqual(f.footY, 0.8, accuracy: 1e-9)
        XCTAssertEqual(f.box(aspect: 0.75).height, 0.5, accuracy: 1e-9)
    }
}
