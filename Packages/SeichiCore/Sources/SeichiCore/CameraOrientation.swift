import Foundation

public struct Vector3: Equatable, Sendable {
    public var x, y, z: Double
    public init(_ x: Double, _ y: Double, _ z: Double) { self.x = x; self.y = y; self.z = z }

    public static func + (a: Vector3, b: Vector3) -> Vector3 { .init(a.x + b.x, a.y + b.y, a.z + b.z) }
    public static func * (a: Vector3, s: Double) -> Vector3 { .init(a.x * s, a.y * s, a.z * s) }
    public static prefix func - (a: Vector3) -> Vector3 { .init(-a.x, -a.y, -a.z) }
    public func dot(_ b: Vector3) -> Double { x * b.x + y * b.y + z * b.z }
    public func cross(_ b: Vector3) -> Vector3 {
        .init(y * b.z - z * b.y, z * b.x - x * b.z, x * b.y - y * b.x)
    }
    public var length: Double { sqrt(dot(self)) }
    public var normalized: Vector3? {
        let l = length
        return l > 1e-9 ? self * (1 / l) : nil
    }
}

/// 根据重力向量和磁场向量（都在 iOS 设备坐标系中：x 指向屏幕右侧，y 指向屏幕顶部，
/// z 垂直屏幕指向用户）计算“背面摄像头”所朝的方向。
///
/// 与 CLHeading 只关心“手机顶部”朝向不同，这里直接计算摄像头光轴（设备 -z 方向）的
/// 方位角，手机竖着举起拍照时也稳定；当摄像头几乎垂直朝下/朝上时，退回使用手机顶部方向。
public enum CameraOrientation {
    public struct Result: Equatable, Sendable {
        /// 相对磁北的方位角（0..<360）
        public var magneticHeading: Double
        /// 摄像头光轴的仰角（度）：+90 朝天，-90 朝地
        public var pitch: Double
        /// 是否因为摄像头接近垂直而改用了手机顶部方向
        public var usedTopEdgeFallback: Bool
    }

    /// 只用重力就能得到摄像头光轴的仰角（度）。
    public static func pitch(gravity: Vector3) -> Double? {
        guard let down = gravity.normalized else { return nil }
        let camera = Vector3(0, 0, -1)
        return GeoMath.degrees(asin(max(-1, min(1, -camera.dot(down)))))
    }

    /// - Parameters:
    ///   - gravity: CMDeviceMotion.gravity（指向地面的单位向量，单位 g）
    ///   - magneticField: CMDeviceMotion.magneticField.field（已校准磁场，μT）
    public static func compute(gravity: Vector3, magneticField: Vector3,
                               fallbackPitchThreshold: Double = 70) -> Result? {
        guard let down = gravity.normalized,
              let east = down.cross(magneticField).normalized else { return nil }
        let north = east.cross(down)

        let camera = Vector3(0, 0, -1)
        guard let pitch = pitch(gravity: gravity) else { return nil }

        let useTop = abs(pitch) > fallbackPitchThreshold
        let axis = useTop ? Vector3(0, 1, 0) : camera
        let e = axis.dot(east), n = axis.dot(north)
        guard abs(e) + abs(n) > 1e-6 else { return nil }
        let heading = GeoMath.normalize(GeoMath.degrees(atan2(e, n)))
        return Result(magneticHeading: heading, pitch: pitch, usedTopEdgeFallback: useTop)
    }
}
