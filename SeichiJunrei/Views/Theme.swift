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
    var tintColor: Color { Color(hex: tint, fallback: .pink) }
}

extension CLLocation {
    var geoPoint: GeoPoint { GeoPoint(latitude: coordinate.latitude, longitude: coordinate.longitude) }
}
