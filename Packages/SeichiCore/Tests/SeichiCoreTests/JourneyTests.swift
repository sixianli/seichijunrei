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
        XCTAssertEqual(SceneImageSearch.engine(for: "zh-Hans"), .baidu)
        XCTAssertEqual(SceneImageSearch.engine(for: "ko"), .naver)
        XCTAssertEqual(SceneImageSearch.engine(for: "zh-Hant"), .google)
        let q = SceneImageSearch.query(originalWork: "君の名は。", japanesePlace: "須賀神社 男坂（東京・四谷）",
                                       localizedWork: "너의 이름은.", localizedPlace: "스가 신사 오토코자카 (도쿄)",
                                       language: "ko")
        XCTAssertEqual(q, "君の名は。 須賀神社 男坂 アニメ シーン 너의 이름은. 스가 신사 오토코자카 명장면")
        let ja = SceneImageSearch.query(originalWork: "君の名は。", japanesePlace: "須賀神社 男坂（東京・四谷）",
                                        localizedWork: nil, localizedPlace: "須賀神社 男坂（東京・四谷）", language: "ja")
        XCTAssertEqual(ja, "君の名は。 須賀神社 男坂 シーン")
        XCTAssertEqual(SceneImageSearch.url(query: "a b", language: "ko")?.host, "search.naver.com")
        XCTAssertEqual(SceneImageSearch.url(query: "a b", language: "zh-Hans")?.host, "image.baidu.com")
        XCTAssertTrue(SceneImageSearch.url(query: "a b", language: "en")!.absoluteString.contains("tbm=isch"))
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
