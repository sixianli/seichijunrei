import Foundation

/// “转身对准名场面”的指引计算。纯函数，不依赖传感器，便于测试。
public struct SceneGuidance: Equatable, Sendable {
    public enum Turn: Equatable, Sendable {
        case left, right, aligned
    }

    public enum Tilt: Equatable, Sendable {
        case up, down, level
    }

    /// 需要转动的有符号角度：正数向右，负数向左。
    public var yawDelta: Double
    /// 需要调整的俯仰角：正数抬头，负数低头。没有俯仰数据时为 nil。
    public var pitchDelta: Double?
    public var turn: Turn
    public var tilt: Tilt
    /// 0...1，越接近 1 越对准（用于渐显名场面画面、驱动震动强度）。
    public var alignment: Double
    /// 水平与俯仰都在容差范围内。
    public var isAligned: Bool { turn == .aligned && tilt == .level }

    public struct Tolerance: Equatable, Sendable {
        public var yaw: Double
        public var pitch: Double
        /// 罗盘精度较差时，额外放宽的角度上限
        public var maxHeadingAccuracyBonus: Double
        public init(yaw: Double = 10, pitch: Double = 12, maxHeadingAccuracyBonus: Double = 10) {
            self.yaw = yaw; self.pitch = pitch; self.maxHeadingAccuracyBonus = maxHeadingAccuracyBonus
        }
        public static let `default` = Tolerance()
    }

    /// - Parameters:
    ///   - deviceHeading: 手机背面摄像头朝向（真北，度）
    ///   - devicePitch: 摄像头相对水平面的仰角（度），未知时为 nil
    ///   - sceneHeading / scenePitch: 名场面的镜头朝向
    ///   - headingAccuracy: 罗盘误差（度），负数代表无效
    public static func compute(deviceHeading: Double, devicePitch: Double?,
                               sceneHeading: Double, scenePitch: Double?,
                               headingAccuracy: Double = 0,
                               tolerance: Tolerance = .default) -> SceneGuidance {
        let yaw = GeoMath.signedDelta(from: deviceHeading, to: sceneHeading)
        let bonus = headingAccuracy > 0 ? min(headingAccuracy / 2, tolerance.maxHeadingAccuracyBonus) : 0
        let yawTol = tolerance.yaw + bonus
        let turn: Turn = abs(yaw) <= yawTol ? .aligned : (yaw > 0 ? .right : .left)

        var pitchDelta: Double? = nil
        var tilt: Tilt = .level
        if let dp = devicePitch, let sp = scenePitch {
            let d = sp - dp
            pitchDelta = d
            if abs(d) > tolerance.pitch { tilt = d > 0 ? .up : .down }
        }

        // 对齐度：水平方向占主导，用余弦曲线让接近目标时变化更平滑
        let yawScore = max(0, cos(GeoMath.radians(min(abs(yaw), 90))))
        let pitchScore = pitchDelta.map { max(0, cos(GeoMath.radians(min(abs($0), 90)))) } ?? 1
        let alignment = yawScore * (0.8 + 0.2 * pitchScore)

        return SceneGuidance(yawDelta: yaw, pitchDelta: pitchDelta, turn: turn, tilt: tilt,
                             alignment: alignment)
    }

    /// 需要转动的角度（取整，绝对值）
    public var yawDegrees: Int { Int(abs(yawDelta).rounded()) }
    /// 需要调整的俯仰角度（取整，绝对值）
    public var pitchDegrees: Int { Int(abs(pitchDelta ?? 0).rounded()) }
}

/// 防抖：连续对准一段时间才触发“成就”，偏离较多才取消，避免在阈值边缘反复闪烁。
public struct AlignmentLatch: Sendable {
    public private(set) var isLocked = false
    private var alignedSince: Double?
    public let holdDuration: Double
    public let releaseFactor: Double

    public init(holdDuration: Double = 0.8, releaseFactor: Double = 1.8) {
        self.holdDuration = holdDuration
        self.releaseFactor = releaseFactor
    }

    /// - Returns: 本次更新是否“刚刚锁定”（用于触发一次性的庆祝动画和震动）。
    public mutating func update(guidance: SceneGuidance, tolerance: SceneGuidance.Tolerance = .default,
                                at time: Double) -> Bool {
        if isLocked {
            let releaseYaw = tolerance.yaw * releaseFactor
            if abs(guidance.yawDelta) > releaseYaw {
                isLocked = false
                alignedSince = nil
            }
            return false
        }
        guard guidance.isAligned else { alignedSince = nil; return false }
        if let since = alignedSince {
            if time - since >= holdDuration { isLocked = true; return true }
        } else {
            alignedSince = time
        }
        return false
    }
}

/// 罗盘读数低通滤波（在圆周上做指数平滑）。
public struct HeadingSmoother: Sendable {
    public private(set) var value: Double?
    public var factor: Double

    public init(factor: Double = 0.25) { self.factor = factor }

    public mutating func add(_ heading: Double) -> Double {
        guard let v = value else { value = GeoMath.normalize(heading); return value! }
        let next = GeoMath.normalize(v + GeoMath.signedDelta(from: v, to: heading) * factor)
        value = next
        return next
    }
}
