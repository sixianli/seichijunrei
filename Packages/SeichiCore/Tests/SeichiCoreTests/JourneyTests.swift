import XCTest
@testable import SeichiCore

final class JourneyTests: XCTestCase {
    func testStagesWithHysteresis() {
        XCTAssertEqual(JourneyStage.next(from: nil, distance: 9300, arrivalRadius: 40), .far)
        XCTAssertEqual(JourneyStage.next(from: nil, distance: 380, arrivalRadius: 40), .near)
        XCTAssertEqual(JourneyStage.next(from: nil, distance: 30, arrivalRadius: 40), .arrived)
        // 走近到 400 m 才切“近”，在 400–500 m 之间不来回跳
        XCTAssertEqual(JourneyStage.next(from: .far, distance: 450, arrivalRadius: 40), .far)
        XCTAssertEqual(JourneyStage.next(from: .near, distance: 450, arrivalRadius: 40), .near)
        XCTAssertEqual(JourneyStage.next(from: .near, distance: 520, arrivalRadius: 40), .far)
        // 到了以后在半径 1.6 倍内不退出
        XCTAssertEqual(JourneyStage.next(from: .arrived, distance: 55, arrivalRadius: 40), .arrived)
        XCTAssertEqual(JourneyStage.next(from: .arrived, distance: 80, arrivalRadius: 40), .near)
        XCTAssertEqual(JourneyStage.next(from: .near, distance: .infinity, arrivalRadius: 40), .near)
        XCTAssertTrue(JourneyStage.prefersWalking(distance: 1500))
        XCTAssertFalse(JourneyStage.prefersWalking(distance: 9300))
    }

    func testRelativeDirection() {
        XCTAssertEqual(RelativeDirection.of(bearing: 180, heading: 180), .ahead)
        XCTAssertEqual(RelativeDirection.of(bearing: 90, heading: 0), .right)
        XCTAssertEqual(RelativeDirection.of(bearing: 0, heading: 90), .left)
        XCTAssertEqual(RelativeDirection.of(bearing: 135, heading: 0), .behindRight)
        XCTAssertEqual(RelativeDirection.of(bearing: 10, heading: 200), .behind)
        XCTAssertEqual(RelativeDirection.of(bearing: 350, heading: 10), .ahead)
        XCTAssertEqual(RelativeDirection.of(bearing: 320, heading: 10), .aheadLeft)
    }

    func testMonthRanges() {
        typealias R = MonthRanges.Range
        XCTAssertEqual(MonthRanges.ranges([3, 4]), [R(3, 4)])
        XCTAssertEqual(MonthRanges.ranges([11, 12, 1, 2]), [R(11, 2)])
        XCTAssertEqual(MonthRanges.ranges([3, 4, 10, 11]), [R(3, 4), R(10, 11)])
        XCTAssertEqual(MonthRanges.ranges([8]), [R(8, 8)])
        XCTAssertEqual(MonthRanges.ranges(Array(1...12)), [R(1, 12)])
        XCTAssertEqual(MonthRanges.ranges([]), [])
    }

    func testSceneImageSearch() {
        XCTAssertEqual(SceneImageSearch.engine(country: "CN"), .baidu)
        XCTAssertEqual(SceneImageSearch.engine(country: "kr"), .naver)
        XCTAssertEqual(SceneImageSearch.engine(country: "JP"), .google)
        XCTAssertEqual(SceneImageSearch.engine(country: "TW"), .google)
        XCTAssertEqual(SceneImageSearch.engine(country: nil), .google)
        let opts = SceneImageSearch.options(work: "天気の子", terms: ["気象神社", "天井画", "晴れ女"], place: nil,
                                            language: "ja", engine: .google)
        XCTAssertEqual(opts.map(\.query), ["天気の子 気象神社 聖地巡礼 比較", "天気の子 天井画", "天気の子 晴れ女",
                                            "天気の子 気象神社 天井画"])
        // 关键词缺失时用地名兜底
        let fallback = SceneImageSearch.options(work: "天气之子", terms: [], place: "高円寺 冰川神社（东京）",
                                                language: "zh-Hans", engine: .baidu)
        XCTAssertEqual(fallback.map(\.query), ["天气之子 高円寺 冰川神社 圣地巡礼 对比"])
        XCTAssertEqual(SceneImageSearch.language(for: .baidu, userLanguage: "en"), "zh-Hans")
        XCTAssertEqual(SceneImageSearch.language(for: .google, userLanguage: "zh-Hans"), "ja")
        XCTAssertEqual(SceneImageSearch.url(query: "a b", engine: .naver)?.host, "search.naver.com")
        XCTAssertEqual(SceneImageSearch.url(query: "a b", engine: .baidu)?.host, "image.baidu.com")
        XCTAssertTrue(SceneImageSearch.url(query: "a b", engine: .google)!.absoluteString.contains("tbm=isch"))
    }

    /// 英文界面在日本：用日文去搜（结果多），每条配上英文说明
    func testSceneImageSearchBilingualLabels() {
        let ja = SceneImageSearch.Words(language: "ja", work: "ドラえもん",
                                        terms: ["藤子・F・不二雄ミュージアム", "はらっぱ 土管", "川崎"], place: nil)
        let en = SceneImageSearch.Words(language: "en", work: "Doraemon",
                                        terms: ["Fujiko F. Fujio Museum", "vacant lot pipes", "Kawasaki"], place: nil)
        let opts = SceneImageSearch.options(search: ja, display: en, engine: .google)
        XCTAssertEqual(opts.map(\.query), ["ドラえもん 藤子・F・不二雄ミュージアム 聖地巡礼 比較", "ドラえもん はらっぱ 土管",
                                            "ドラえもん 川崎", "ドラえもん 藤子・F・不二雄ミュージアム はらっぱ 土管"])
        XCTAssertEqual(opts.map(\.label), ["Doraemon · Fujiko F. Fujio Museum · pilgrimage comparison",
                                            "Doraemon · vacant lot pipes", "Doraemon · Kawasaki",
                                            "Doraemon · Fujiko F. Fujio Museum · vacant lot pipes"])
        // 真人日剧 / 电影搜“ロケ地”
        let live = SceneImageSearch.options(search: ja, display: en, engine: .google, liveAction: true)
        XCTAssertEqual(live.first?.query, "ドラえもん 藤子・F・不二雄ミュージアム ロケ地 比較")
        XCTAssertEqual(live.first?.label, "Doraemon · Fujiko F. Fujio Museum · filming location")
        // 同语言不配说明
        XCTAssertEqual(SceneImageSearch.options(search: ja, display: ja, engine: .google).compactMap(\.label), [])
        // 关键词对不上（条数不同）时不乱配说明
        var short = en; short.terms = ["Fujiko F. Fujio Museum"]
        XCTAssertEqual(SceneImageSearch.options(search: ja, display: short, engine: .google).compactMap(\.label), [])
    }

    func testDestination() {
        let a = GeoPoint(latitude: 35.68518, longitude: 139.72345)
        let b = GeoMath.destination(from: a, bearing: 120, distance: 70)
        XCTAssertEqual(GeoMath.distance(from: a, to: b), 70, accuracy: 0.5)
        XCTAssertEqual(GeoMath.bearing(from: a, to: b), 120, accuracy: 0.5)
    }

    func testPhotoLocationCheck() {
        let spot = GeoPoint(latitude: 35.68518, longitude: 139.72345)
        XCTAssertEqual(PhotoLocationCheck.check(photoLocation: nil, spot: spot), .missingLocation)
        XCTAssertEqual(PhotoLocationCheck.check(photoLocation: GeoPoint(latitude: 35.6855, longitude: 139.7236), spot: spot), .ok)
        if case .tooFar = PhotoLocationCheck.check(photoLocation: GeoPoint(latitude: 35.70, longitude: 139.72), spot: spot) {} else {
            XCTFail("1.6 km 外应被拒绝")
        }
    }
}
