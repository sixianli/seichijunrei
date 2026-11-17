import Foundation
import UserNotifications
import SeichiCore

/// 靠近圣地时的本地通知。
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationService()

    /// spotID → 圣地（直接读取内置数据，保证 App 在后台被地理围栏唤醒时也能拿到文案）
    private lazy var spotsByID: [String: Spot] = {
        guard let url = Bundle.main.url(forResource: "spots", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let spots = try? SpotCatalog.decode(data) else { return [:] }
        return Dictionary(uniqueKeysWithValues: spots.map { ($0.id, $0) })
    }()

    func requestAuthorization() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func notifyArrival(spotID: String) {
        guard let spot = spotsByID[spotID] else { return }
        let content = UNMutableNotificationContent()
        content.title = "你已来到《\(spot.work)》的圣地"
        content.body = "「\(spot.sceneTitle)」就在附近，打开 App 寻找名场面的视角吧！"
        content.sound = .default
        content.userInfo = ["spotID": spotID]
        let request = UNNotificationRequest(identifier: "arrival-\(spotID)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    // App 在前台时也显示横幅
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
