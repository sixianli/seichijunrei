import Foundation
import CoreLocation
import Observation
import SeichiCore

/// 定位 + 罗盘 + 地理围栏。
@Observable
final class LocationService: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()

    private(set) var authorization: CLAuthorizationStatus = .notDetermined
    private(set) var lastLocation: CLLocation?
    /// CLHeading 给出的真北方位（手机顶部方向），罗盘不可用时为 nil
    private(set) var compassHeading: Double?
    private(set) var headingAccuracy: Double = -1
    /// 磁偏角（真北 − 磁北），用于把磁力计结果换算成真北。日本约为 -7°～-9°。
    private(set) var declination: Double = 0

    /// 调试用：模拟用户站在某个坐标（忽略真实 GPS）
    private(set) var isSimulating = false

    private var monitoredIDs: Set<String> = []
    private static let maxMonitoredRegions = 20   // iOS 每个 App 最多监控 20 个区域

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 3
        manager.activityType = .fitness
        manager.headingFilter = 1
        manager.headingOrientation = .portrait
        authorization = manager.authorizationStatus
    }

    func start() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.startUpdatingLocation()
            if CLLocationManager.headingAvailable() { manager.startUpdatingHeading() }
        default:
            break
        }
    }

    /// 申请“始终允许”，以便在 App 不在前台时也能在接近圣地时推送通知。
    func requestAlwaysAuthorization() {
        manager.requestAlwaysAuthorization()
    }

    /// 监控最近的若干个圣地，进入时推送本地通知。
    func monitorNearestRegions(_ spots: [Spot]) {
        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self),
              manager.authorizationStatus == .authorizedAlways else { return }
        let targets = Array(spots.prefix(Self.maxMonitoredRegions))
        let targetIDs = Set(targets.map(\.id))
        guard targetIDs != monitoredIDs else { return }

        for region in manager.monitoredRegions where !targetIDs.contains(region.identifier) {
            manager.stopMonitoring(for: region)
        }
        for spot in targets where !monitoredIDs.contains(spot.id) {
            let region = CLCircularRegion(
                center: CLLocationCoordinate2D(latitude: spot.coordinate.latitude,
                                               longitude: spot.coordinate.longitude),
                radius: max(spot.arrivalRadius * 4, 100),   // 提前一点提醒
                identifier: spot.id)
            region.notifyOnEntry = true
            region.notifyOnExit = false
            manager.startMonitoring(for: region)
        }
        monitoredIDs = targetIDs
    }

    func simulate(at point: GeoPoint) {
        isSimulating = true
        lastLocation = CLLocation(coordinate: CLLocationCoordinate2D(latitude: point.latitude,
                                                                     longitude: point.longitude),
                                  altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5, timestamp: Date())
    }

    func stopSimulating() {
        isSimulating = false
        lastLocation = manager.location
    }

    // MARK: CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorization = manager.authorizationStatus
        start()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard !isSimulating, let loc = locations.last, loc.horizontalAccuracy >= 0 else { return }
        lastLocation = loc
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        headingAccuracy = newHeading.headingAccuracy
        guard newHeading.headingAccuracy >= 0 else { compassHeading = nil; return }
        if newHeading.trueHeading >= 0 {
            compassHeading = newHeading.trueHeading
            declination = GeoMath.signedDelta(from: newHeading.magneticHeading, to: newHeading.trueHeading)
        } else {
            compassHeading = newHeading.magneticHeading
        }
    }

    func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool {
        // 精度很差时让系统弹出“画 8 字”校准提示
        headingAccuracy < 0 || headingAccuracy > 25
    }

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        NotificationService.shared.notifyArrival(spotID: region.identifier)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // 定位暂时失败（如室内）时保持上次结果即可
    }
}
