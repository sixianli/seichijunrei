import Foundation
import CoreMotion
import Observation
import SeichiCore

/// 计算“摄像头正对的方向”（真北方位 + 俯仰角）。
///
/// 优先使用 CoreMotion 的重力 + 已校准磁场自行融合（竖持手机时最稳定），
/// 磁力计不可用时退回 CLHeading。
@Observable
final class OrientationService {
    private let motion = CMMotionManager()
    private let queue = OperationQueue()
    private var smoother = HeadingSmoother(factor: 0.2)

    /// 摄像头朝向（真北，度）
    private(set) var heading: Double?
    /// 摄像头俯仰（度）
    private(set) var pitch: Double?
    /// 估计误差（度），负数表示未知
    private(set) var accuracy: Double = -1
    private(set) var isUsingMotionFusion = false

    /// 由外部（LocationService）提供的磁偏角与 CLHeading 后备值
    var declinationProvider: () -> Double = { 0 }
    var compassFallback: () -> (heading: Double?, accuracy: Double) = { (nil, -1) }

    init() {
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .userInteractive
    }

    func start() {
        guard motion.isDeviceMotionAvailable, !motion.isDeviceMotionActive else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 30.0
        let frame: CMAttitudeReferenceFrame =
            CMMotionManager.availableAttitudeReferenceFrames().contains(.xMagneticNorthZVertical)
            ? .xMagneticNorthZVertical : .xArbitraryCorrectedZVertical
        motion.startDeviceMotionUpdates(using: frame, to: queue) { [weak self] dm, _ in
            guard let self, let dm else { return }
            let g = Vector3(dm.gravity.x, dm.gravity.y, dm.gravity.z)
            let field = dm.magneticField
            let fusion: CameraOrientation.Result? =
                field.accuracy == .uncalibrated ? nil
                : CameraOrientation.compute(gravity: g,
                                            magneticField: Vector3(field.field.x, field.field.y, field.field.z))
            let pitch = CameraOrientation.pitch(gravity: g)
            let accuracy: Double = switch field.accuracy {
                case .high: 5
                case .medium: 12
                case .low: 25
                default: -1
            }
            DispatchQueue.main.async {
                self.apply(fusion: fusion, pitch: pitch, fusionAccuracy: accuracy)
            }
        }
    }

    func stop() {
        motion.stopDeviceMotionUpdates()
    }

    private func apply(fusion: CameraOrientation.Result?, pitch: Double?, fusionAccuracy: Double) {
        self.pitch = pitch
        if let fusion {
            isUsingMotionFusion = true
            let trueHeading = GeoMath.normalize(fusion.magneticHeading + declinationProvider())
            heading = smoother.add(trueHeading)
            accuracy = fusionAccuracy
        } else {
            isUsingMotionFusion = false
            let fb = compassFallback()
            if let h = fb.heading { heading = smoother.add(h) }
            accuracy = fb.accuracy
        }
    }
}
