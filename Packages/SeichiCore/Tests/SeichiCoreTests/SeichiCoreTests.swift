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
        XCTAssertEqual(GeoMath.compassName(44), "东北")
        XCTAssertEqual(GeoMath.compassName(359), "北")
        XCTAssertEqual(GeoMath.compassName(200), "南")
    }
}

final class SceneGuidanceTests: XCTestCase {
    func testTurnDirection() {
        let g = SceneGuidance.compute(deviceHeading: 0, devicePitch: nil, sceneHeading: 90, scenePitch: nil)
        XCTAssertEqual(g.turn, .right)
        XCTAssertEqual(g.yawDelta, 90)
        XCTAssertEqual(g.instruction, "向右转 90°")

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
        XCTAssertEqual(g.instruction, "方向对了，再稍微抬头 35°")
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

    /// 校验 App 内置的圣地数据可以正确解码。
    func testBundledSpotsJSONIsValid() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("SeichiJunrei/Resources/spots.json")
        let spots = try SpotCatalog.decode(Data(contentsOf: url))
        XCTAssertGreaterThanOrEqual(spots.count, 8)
        for s in spots {
            XCTAssertTrue((0..<360).contains(s.sceneHeading), s.id)
            XCTAssertTrue((24...46).contains(s.coordinate.latitude), "\(s.id) 不在日本范围内")
            XCTAssertTrue((122...154).contains(s.coordinate.longitude), "\(s.id) 不在日本范围内")
            XCTAssertFalse(s.story.isEmpty, s.id)
        }
        // 编码 → 解码往返
        let round = try SpotCatalog.decode(JSONEncoder().encode(spots))
        XCTAssertEqual(round, spots)
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
