import UIKit

/// 根据对准程度发出越来越密集的轻触反馈，对准时给一次“成功”反馈。
final class Haptics {
    private let light = UIImpactFeedbackGenerator(style: .light)
    private let notification = UINotificationFeedbackGenerator()
    private var lastTick: Date = .distantPast

    func prepare() {
        light.prepare()
        notification.prepare()
    }

    /// - Parameter alignment: 0...1
    func tick(alignment: Double) {
        guard alignment > 0.5 else { return }
        // 对准度越高，间隔越短（0.6s → 0.08s），像“盖革计数器”一样
        let interval = 0.6 - (alignment - 0.5) / 0.5 * 0.52
        let now = Date()
        guard now.timeIntervalSince(lastTick) >= interval else { return }
        lastTick = now
        light.impactOccurred(intensity: CGFloat(alignment))
    }

    func success() {
        notification.notificationOccurred(.success)
    }
}
