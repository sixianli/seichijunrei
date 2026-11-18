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

    /// 罗盘可信时的朝向（精度 30° 以内），否则 nil：不能用会误导人的箭头
    var reliableHeading: Double? {
        if isSimulating, let h = simulatedHeading { return h }
        guard let h = compassHeading, headingAccuracy >= 0, headingAccuracy <= 30 else { return nil }
        return h
    }
    /// 调试 / UI 测试用的模拟朝向
    var simulatedHeading: Double?

    /// 用户当前所在国家（ISO 代码，按定位反查；用来选搜索引擎）。没有定位时为 nil
    private(set) var countryCode: String?
    @ObservationIgnored private var countryCheckedAt: CLLocation?
    @ObservationIgnored private let geocoder = CLGeocoder()

    /// 每移动 50 km 以上才重新反查一次国家（反查有频率限制）
    private func updateCountryIfNeeded(_ loc: CLLocation) {
        if let last = countryCheckedAt, loc.distance(from: last) < 50_000 { return }
        countryCheckedAt = loc
        geocoder.reverseGeocodeLocation(loc) { [weak self] marks, _ in
            guard let code = marks?.first?.isoCountryCode else { return }
            DispatchQueue.main.async { self?.countryCode = code }
        }
    }

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
        // 默认在“静止”时会自动暂停定位且不再恢复，导致 App 拿不到位置、附近列表为空
        manager.pausesLocationUpdatesAutomatically = false
        authorization = manager.authorizationStatus
    }

    func start() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            // 先用系统缓存的最近位置（10 分钟内），不用干等第一次定位
            if !isSimulating, lastLocation == nil, let cached = manager.location,
               cached.horizontalAccuracy >= 0, -cached.timestamp.timeIntervalSinceNow < 600 {
                lastLocation = cached
            }
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
        // 留一个名额给“快到了提醒”（出发去某个名场面时）
        let targets = Array(spots.prefix(Self.maxMonitoredRegions - 1))
        let targetIDs = Set(targets.map(\.id))
        guard targetIDs != monitoredIDs else { return }

        for region in manager.monitoredRegions
        where !targetIDs.contains(region.identifier) && !region.identifier.hasPrefix(Self.journeyPrefix) {
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

    // MARK: 快到了提醒

    static let journeyPrefix = "journey|"

    /// 出发去某个名场面：离它 400 m 时发通知，点通知直接回到“近”的指引。需要“始终允许”定位。
    @discardableResult
    func armJourney(spot: Spot, purpose: JourneyPurpose) -> Bool {
        guard manager.authorizationStatus == .authorizedAlways,
              CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else { return false }
        disarmJourney()
        let region = CLCircularRegion(center: CLLocationCoordinate2D(latitude: spot.coordinate.latitude,
                                                                     longitude: spot.coordinate.longitude),
                                      radius: JourneyStage.nearEnter,
                                      identifier: Self.journeyPrefix + spot.id + "|" + purpose.rawValue)
        region.notifyOnEntry = true
        region.notifyOnExit = false
        manager.startMonitoring(for: region)
        return true
    }

    func disarmJourney() {
        for region in manager.monitoredRegions where region.identifier.hasPrefix(Self.journeyPrefix) {
            manager.stopMonitoring(for: region)
        }
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
        updateCountryIfNeeded(loc)
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
        if region.identifier.hasPrefix(Self.journeyPrefix) {
            let parts = region.identifier.split(separator: "|").map(String.init)
            manager.stopMonitoring(for: region)
            if parts.count == 3 { NotificationService.shared.notifyApproach(spotID: parts[1], purpose: parts[2]) }
            return
        }
        NotificationService.shared.notifyArrival(spotID: region.identifier)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // 定位暂时失败（如室内）时保持上次结果即可
    }
}
