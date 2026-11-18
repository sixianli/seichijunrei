import SwiftUI
import CoreLocation
import SeichiCore

extension Color {
    init(hex: String?, fallback: Color = .accentColor) {
        guard var s = hex?.trimmingCharacters(in: .whitespaces) else { self = fallback; return }
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt64(s, radix: 16) else { self = fallback; return }
        self.init(red: Double((v >> 16) & 0xFF) / 255,
                  green: Double((v >> 8) & 0xFF) / 255,
                  blue: Double(v & 0xFF) / 255)
    }
}

extension Spot {
    var clCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }
    /// 全 App 统一的品牌色（靛蓝，深色模式下更亮）。作品自己的主题色不再用于界面，避免五颜六色
    var tintColor: Color { .accentColor }
}

extension CLLocation {
    var geoPoint: GeoPoint { GeoPoint(latitude: coordinate.latitude, longitude: coordinate.longitude) }
}

extension MediaType {
    /// SF Symbols 图标
    var symbolName: String {
        switch self {
        case .anime: return "sparkles.tv.fill"
        case .animeFilm: return "film.fill"
        case .film: return "movieclapper.fill"
        case .drama: return "tv.fill"
        }
    }
}
