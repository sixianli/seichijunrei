import Foundation
import UserNotifications
import SeichiCore

/// 靠近圣地时的本地通知。
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationService()

    /// 用户点击通知后要打开的圣地。App 还没准备好时先暂存，准备好后再取走。
    private var pendingSpotID: String?
    var onOpenSpot: ((String) -> Void)? {
        didSet {
            if let id = pendingSpotID, let handler = onOpenSpot {
                pendingSpotID = nil
                handler(id)
            }
        }
    }

    /// spotID → 圣地（直接读取内置数据，保证 App 在后台被地理围栏唤醒时也能拿到文案）
    private lazy var spotsByID: [String: Spot] = {
        guard let url = Bundle.main.url(forResource: "spots", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let spots = try? SpotCatalog.decode(data) else { return [:] }
        let language = AppLanguage.current
        return Dictionary(uniqueKeysWithValues: spots.map { ($0.id, $0.localized(to: language)) })
    }()

    func requestAuthorization() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func notifyArrival(spotID: String) {
        guard let spot = spotsByID[spotID] else { return }
        let content = UNMutableNotificationContent()
        content.title = L("notif.title", spot.workTitle)
        content.body = L("notif.body", spot.quotedSceneTitle)
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

    // 点击通知：跳转到对应圣地
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if let id = response.notification.request.content.userInfo["spotID"] as? String {
            DispatchQueue.main.async {
                if let handler = self.onOpenSpot { handler(id) } else { self.pendingSpotID = id }
            }
        }
        completionHandler()
    }
}
