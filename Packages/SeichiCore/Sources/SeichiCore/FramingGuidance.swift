import Foundation

/// 名场面里主角在画面中的位置与大小（归一化坐标，原点在左上角，竖屏画面）。
///
/// 用于“帮拍模式”：被拍的人站在主角的位置，拍照的人按指引调整远近、左右和高低，
/// 让被拍的人在取景框里的位置和大小与原作一致。
public struct SubjectFraming: Codable, Hashable, Sendable {
    /// 人物水平中心（0 = 左边缘，1 = 右边缘）
    public var centerX: Double
    /// 人物脚底所在的高度（0 = 顶部，1 = 底部）
    public var footY: Double
    /// 人物身高占画面高度的比例
    public var height: Double

    public init(centerX: Double, footY: Double, height: Double) {
        self.centerX = min(max(centerX, 0), 1)
        self.footY = min(max(footY, 0), 1)
        self.height = min(max(height, 0.05), 1)
    }

    /// 没有原作参考时的默认构图：人物居中、全身入镜、占画面约 45%
    public static let `default` = SubjectFraming(centerX: 0.5, footY: 0.85, height: 0.45)

    /// 由人物外接框（归一化，原点左上）得到构图
    public init(box: NormalizedRect) {
        self.init(centerX: box.midX, footY: box.maxY, height: box.height)
    }

    /// 对应的人物外接框（按常见人体宽高比 0.38 估算宽度，画面宽高比 aspect = 宽/高）
    public func box(aspect: Double) -> NormalizedRect {
        let w = height * 0.38 / max(aspect, 0.1)
        return NormalizedRect(x: centerX - w / 2, y: footY - height, width: w, height: height)
    }
}

/// 归一化矩形（0…1，原点左上）
public struct NormalizedRect: Codable, Hashable, Sendable {
    public var x: Double, y: Double, width: Double, height: Double
    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }
    public var midX: Double { x + width / 2 }
    public var maxY: Double { y + height }
}

/// 帮拍指引：给拍照的人的一条最优先的提示。
public struct FramingGuidance: Equatable, Sendable {
    public enum Step: Equatable, Sendable {
        /// 画面里找不到人
        case findSubject
        /// 转动手机朝向（度，正数向右）
        case turn(degrees: Int)
        /// 抬高 / 压低镜头角度（度，正数向上）
        case tilt(degrees: Int)
        /// 往前走（米）
        case moveCloser(meters: Double)
        /// 往后退（米）
        case moveBack(meters: Double)
        /// 横向平移（米，正数向右）
        case sidestep(meters: Double)
        /// 把手机举高
        case raise
        /// 把手机放低（蹲下一点）
        case lower
        /// 全部对齐
        case perfect
    }

    public var step: Step
    /// 0…1，整体对齐程度（用于进度环）
    public var score: Double
    /// 当前估算的拍摄距离（米），检测不到人时为 nil
    public var estimatedDistance: Double?

    public init(step: Step, score: Double, estimatedDistance: Double?) {
        self.step = step; self.score = score; self.estimatedDistance = estimatedDistance
    }

    public struct Tolerance: Sendable {
        public var headingDegrees = 12.0
        public var pitchDegrees = 8.0
        /// 人物大小允许的相对误差
        public var size = 0.14
        /// 水平位置允许的误差（画面宽度的比例）
        public var horizontal = 0.07
        /// 脚底位置允许的误差（画面高度的比例）
        public var vertical = 0.08
        public init() {}
    }

    /// 人的平均身高（米），用于根据画面中的人物大小估算距离
    public static let personHeight = 1.65

    /// - Parameters:
    ///   - target: 原作中主角的构图
    ///   - subject: 当前画面中检测到的人物外接框（归一化，原点左上）；nil 表示没检测到
    ///   - headingDelta: 场景朝向 − 手机朝向（度，正数表示需要向右转）；nil 表示没有指南针数据
    ///   - pitchDelta: 场景俯仰 − 手机俯仰（度，正数表示需要抬头）
    ///   - verticalFOV / horizontalFOV: 取景画面的视场角（度）
    ///   - zoomCorrectable: App 能靠自动变焦把人物大小放大 / 缩小的倍数范围（例如 0.8...2.0）。
    ///     需要的倍数落在这个范围内时，不必让拍照的人走动，交给自动变焦。
    public static func compute(target: SubjectFraming, subject: NormalizedRect?,
                               headingDelta: Double?, pitchDelta: Double?,
                               verticalFOV: Double, horizontalFOV: Double,
                               zoomCorrectable: ClosedRange<Double> = 1...1,
                               tolerance: Tolerance = Tolerance()) -> FramingGuidance {
        // 1. 方向：先让镜头朝向原作的方向（这一步不需要被拍的人）
        let yawOK = abs(headingDelta ?? 0) <= tolerance.headingDegrees
        let pitchOK = abs(pitchDelta ?? 0) <= tolerance.pitchDegrees
        let directionScore = 0.5 * closeness(abs(headingDelta ?? 0), tolerance.headingDegrees * 4)
            + 0.5 * closeness(abs(pitchDelta ?? 0), tolerance.pitchDegrees * 4)

        if let h = headingDelta, !yawOK {
            return FramingGuidance(step: .turn(degrees: Int(h.rounded())), score: directionScore * 0.4,
                                   estimatedDistance: subject.map { distance(to: $0, verticalFOV: verticalFOV) })
        }
        guard let subject, subject.height > 0.02 else {
            return FramingGuidance(step: .findSubject, score: directionScore * 0.4, estimatedDistance: nil)
        }
        let d = distance(to: subject, verticalFOV: verticalFOV)

        // 2. 远近：人物大小与原作一致。距离与画面中的人物高度成反比。
        let ratio = subject.height / target.height
        let targetDistance = d * ratio
        let neededZoom = 1 / ratio
        let sizeOK = abs(ratio - 1) <= tolerance.size || zoomCorrectable.contains(neededZoom)

        // 3. 左右：保持朝向不变，横向平移相机（人物偏右 → 相机往右走）
        let dx = subject.midX - target.centerX
        let frameWidth = 2 * d * tan(radians(horizontalFOV) / 2)
        let sideOK = abs(dx) <= tolerance.horizontal

        // 4. 高低：朝向固定时，相机举高会让人物在画面里往下移
        let dy = subject.maxY - target.footY
        let heightOK = abs(dy) <= tolerance.vertical

        let sizeError = sizeOK ? 0 : abs(ratio - 1)
        let framingScore = (closeness(sizeError, tolerance.size * 4)
            + closeness(abs(dx), tolerance.horizontal * 4)
            + closeness(abs(dy), tolerance.vertical * 4)) / 3
        let score = 0.4 * directionScore + 0.6 * framingScore

        let step: Step
        if !sizeOK {
            // 只需走到自动变焦能接手的范围即可
            let reachable = ratio > 1 ? 1 / zoomCorrectable.lowerBound : 1 / zoomCorrectable.upperBound
            let delta = d * ratio / max(reachable, 0.01) - d
            _ = targetDistance
            step = delta > 0 ? .moveBack(meters: roundHalf(delta)) : .moveCloser(meters: roundHalf(-delta))
        } else if !sideOK {
            step = .sidestep(meters: roundHalf(dx * frameWidth, minimum: 0.3))
        } else if let p = pitchDelta, !pitchOK {
            step = .tilt(degrees: Int(p.rounded()))
        } else if !heightOK {
            step = dy < 0 ? .raise : .lower
        } else {
            step = .perfect
        }
        return FramingGuidance(step: step, score: step == .perfect ? 1 : min(score, 0.95), estimatedDistance: d)
    }

    /// 由人物在画面中的高度估算距离（米）
    public static func distance(to subject: NormalizedRect, verticalFOV: Double) -> Double {
        let visibleHeight = personHeight / max(subject.height, 0.02)
        return visibleHeight / (2 * tan(radians(verticalFOV) / 2))
    }

    static func radians(_ d: Double) -> Double { d * .pi / 180 }
    static func closeness(_ error: Double, _ scale: Double) -> Double { max(0, 1 - error / scale) }
    /// 四舍五入到 0.5 米，且不小于 minimum（避免出现“移动 0 米”）
    static func roundHalf(_ v: Double, minimum: Double = 0.5) -> Double {
        let r = (abs(v) * 2).rounded() / 2
        return (v < 0 ? -1 : 1) * max(r, minimum)
    }
}

/// 拍完后按原作构图自动裁切：把检测到的人移到主角的位置、缩放到主角的大小。
public enum AutoReframe {
    /// 返回裁切区域（相对整张照片归一化，保持原照片的宽高比）；不需要或无法裁切时返回 nil。
    /// - Parameter maxZoom: 最多裁掉多少（1.6 表示最多放大 1.6 倍，避免画质损失太大）
    public static func cropRect(subject: NormalizedRect, target: SubjectFraming,
                                maxZoom: Double = 1.6) -> NormalizedRect? {
        // 裁切框的边长比例 = 人物当前高度 / 目标高度（只能放大，不能缩小）
        let s = min(1, max(1 / maxZoom, subject.height / target.height))
        var x = subject.midX - target.centerX * s
        var y = subject.maxY - target.footY * s
        x = min(max(x, 0), 1 - s)
        y = min(max(y, 0), 1 - s)
        if s > 0.98 && abs(x) < 0.01 && abs(y) < 0.01 { return nil }
        return NormalizedRect(x: x, y: y, width: s, height: s)
    }
}
