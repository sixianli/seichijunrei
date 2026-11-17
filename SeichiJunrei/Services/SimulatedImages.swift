import UIKit

/// 模拟器 / UI 测试用的示意图片（真机不会用到）
enum SimulatedImages {
    static func photo() -> UIImage { cachedPhoto }
    static func scene() -> UIImage { cachedScene }

    private static let cachedPhoto: UIImage =
        render(colors: [UIColor(red: 0.98, green: 0.72, blue: 0.45, alpha: 1), UIColor(red: 0.35, green: 0.55, blue: 0.85, alpha: 1)],
               label: "📷 PHOTO", size: CGSize(width: 900, height: 1200))

    private static let cachedScene: UIImage =
        render(colors: [UIColor(red: 0.25, green: 0.45, blue: 0.95, alpha: 1), UIColor(red: 0.95, green: 0.55, blue: 0.75, alpha: 1)],
               label: "🎬 SCENE", size: CGSize(width: 1600, height: 900))

    private static func render(colors: [UIColor], label: String, size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            let cg = ctx.cgContext
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                      colors: colors.map(\.cgColor) as CFArray, locations: [0, 1])!
            cg.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: size.width / 9, weight: .heavy),
                .foregroundColor: UIColor.white.withAlphaComponent(0.85),
            ]
            let text = label as NSString
            let ts = text.size(withAttributes: attrs)
            text.draw(at: CGPoint(x: (size.width - ts.width) / 2, y: (size.height - ts.height) / 2), withAttributes: attrs)
        }
    }
}
