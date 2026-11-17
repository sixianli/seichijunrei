import Foundation

/// 把“名场面方向”投影到相机取景画面上的位置，实现轻量级的 AR 效果：
/// 名场面画框会悬浮在真实世界中它所在的方向，用户转身时画框随之滑入画面中央。
public enum ViewfinderProjection {
    /// 取景器可见视场角（度）
    public struct FieldOfView: Equatable, Sendable {
        public var horizontal: Double
        public var vertical: Double
        public init(horizontal: Double, vertical: Double) {
            self.horizontal = horizontal; self.vertical = vertical
        }
        /// iPhone 主摄竖屏全屏预览的典型值（无法读取相机参数时使用）
        public static let typicalPortrait = FieldOfView(horizontal: 36, vertical: 69)
    }

    /// 根据相机传感器参数计算竖屏 aspect-fill 预览中实际可见的视场角。
    /// - Parameters:
    ///   - sensorFOV: 传感器长边方向视场角（AVCaptureDevice.Format.videoFieldOfView）
    ///   - sensorAspect: 传感器长边/短边，例如 4:3 → 1.333
    ///   - viewSize: 预览视图尺寸（竖屏，宽 < 高）
    public static func visibleFieldOfView(sensorFOV: Double, sensorAspect: Double,
                                          viewWidth: Double, viewHeight: Double) -> FieldOfView {
        guard sensorFOV > 0, sensorAspect > 0, viewWidth > 0, viewHeight > 0 else { return .typicalPortrait }
        let tanLong = tan(GeoMath.radians(sensorFOV / 2))
        let tanShort = tanLong / sensorAspect
        // 竖屏时传感器长边对应屏幕高度
        let sensorRatio = 1 / sensorAspect          // 宽/高
        let viewRatio = viewWidth / viewHeight
        var tanH = tanShort, tanV = tanLong
        if viewRatio < sensorRatio {
            tanH = tanShort * (viewRatio / sensorRatio)   // 左右被裁切
        } else {
            tanV = tanLong * (sensorRatio / viewRatio)     // 上下被裁切
        }
        return FieldOfView(horizontal: GeoMath.degrees(2 * atan(tanH)),
                           vertical: GeoMath.degrees(2 * atan(tanV)))
    }

    /// 目标方向在画面中的归一化坐标：x ∈ [-1, 1] 从左到右，y ∈ [-1, 1] 从下到上。
    /// 超出 ±1 表示在画面之外；目标在身后（|yaw| ≥ 90°）时返回 nil。
    public static func project(yawDelta: Double, pitchDelta: Double,
                               fov: FieldOfView) -> (x: Double, y: Double)? {
        guard abs(yawDelta) < 89, abs(pitchDelta) < 89 else { return nil }
        let x = tan(GeoMath.radians(yawDelta)) / tan(GeoMath.radians(fov.horizontal / 2))
        let y = tan(GeoMath.radians(pitchDelta)) / tan(GeoMath.radians(fov.vertical / 2))
        return (x, y)
    }
}
