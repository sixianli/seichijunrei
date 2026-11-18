import Foundation
import MapKit
import UIKit
import SeichiCore

/// 外部导航用的地图 App。
///
/// 日本当地最常用的是 Google 地图，中国游客常用高德 / 百度，所以导航时让用户选择，
/// 也可以在设置里设为默认。没装对应 App 时打开它的网页版。
///
/// 坐标说明：数据是 WGS84。高德 / 百度在中国境外不做 GCJ-02 偏移，
/// 日本的坐标按 WGS84 传入即可（百度显式声明 coord_type=wgs84）。
enum MapApp: String, CaseIterable, Identifiable {
    case google, apple, amap, baidu

    var id: String { rawValue }

    var name: String { L("mapApp.\(rawValue)") }

    /// 设置页里的“默认地图”：nil 表示每次询问
    static let preferenceKey = "preferredMapApp"
    static var preferred: MapApp? {
        get { UserDefaults.standard.string(forKey: preferenceKey).flatMap(MapApp.init(rawValue:)) }
        set { UserDefaults.standard.set(newValue?.rawValue, forKey: preferenceKey) }
    }

    /// 选择列表的顺序：中文用户把高德 / 百度排在前面，其他语言 Google 优先
    static var ordered: [MapApp] {
        AppLanguage.current.hasPrefix("zh") ? [.google, .amap, .baidu, .apple] : [.google, .apple, .amap, .baidu]
    }

    var isInstalled: Bool {
        switch self {
        case .apple: return true
        case .google: return UIApplication.shared.canOpenURL(URL(string: "comgooglemaps://")!)
        case .amap: return UIApplication.shared.canOpenURL(URL(string: "iosamap://")!)
        case .baidu: return UIApplication.shared.canOpenURL(URL(string: "baidumap://")!)
        }
    }

    /// 打开到某个名场面的路线，目的地自动填好（近处步行，远处公共交通）
    func openDirections(to spot: Spot, walking: Bool = false) {
        if self == .apple {
            let item = MKMapItem(placemark: MKPlacemark(coordinate: spot.clCoordinate))
            item.name = spot.placeName
            item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey:
                                                walking ? MKLaunchOptionsDirectionsModeWalking : MKLaunchOptionsDirectionsModeTransit])
            return
        }
        let urls = Self.directionURLs(app: self, latitude: spot.coordinate.latitude,
                                      longitude: spot.coordinate.longitude, name: spot.placeName, walking: walking)
        let target = isInstalled ? urls.app : urls.web
        guard let target else { return }
        UIApplication.shared.open(target)
    }

    /// App 内链接与网页版链接。拆成纯函数，方便测试。
    static func directionURLs(app: MapApp, latitude: Double, longitude: Double,
                              name: String, walking: Bool = false) -> (app: URL?, web: URL?) {
        let lat = String(format: "%.6f", latitude), lon = String(format: "%.6f", longitude)
        let encodedName = name.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) ?? ""
        let src = "ios.com.xianlisi.seichijunrei"
        switch app {
        case .google:
            let mode = walking ? "walking" : "transit"
            return (URL(string: "comgooglemaps://?daddr=\(lat),\(lon)&directionsmode=\(mode)"),
                    URL(string: "https://www.google.com/maps/dir/?api=1&destination=\(lat),\(lon)&travelmode=\(mode)"))
        case .amap:
            // t=1 公共交通；dev=0 表示不再做坐标偏移
            // t=1 公共交通，t=2 步行
            return (URL(string: "iosamap://path?sourceApplication=\(src)&dlat=\(lat)&dlon=\(lon)&dname=\(encodedName)&dev=0&t=\(walking ? 2 : 1)"),
                    URL(string: "https://uri.amap.com/navigation?to=\(lon),\(lat),\(encodedName)&mode=\(walking ? "walk" : "bus")&src=\(src)&coordinate=wgs84&callnative=1"))
        case .baidu:
            let dest = "latlng:\(lat),\(lon)%7Cname:\(encodedName)"   // %7C = "|"
            let mode = walking ? "walking" : "transit"
            return (URL(string: "baidumap://map/direction?destination=\(dest)&coord_type=wgs84&mode=\(mode)&src=\(src)"),
                    URL(string: "https://api.map.baidu.com/direction?destination=\(dest)&coord_type=wgs84&mode=\(mode)&region=%E6%97%A5%E6%9C%AC&output=html&src=\(src)"))
        case .apple:
            return (nil, URL(string: "https://maps.apple.com/?daddr=\(lat),\(lon)&dirflg=\(walking ? "w" : "r")"))
        }
    }
}

private extension CharacterSet {
    /// URL 查询参数值里允许出现的字符（排除 & = ? | 等分隔符）
    static let urlQueryValueAllowed: CharacterSet = {
        // 只放行 ASCII 字母数字（CharacterSet.alphanumerics 会包含汉字等非 ASCII 字符）
        CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
    }()
}
