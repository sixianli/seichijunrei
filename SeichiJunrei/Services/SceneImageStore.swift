import Foundation
import Observation
import UIKit

/// 用户自己提供的名场面截图（从相册选择），只保存在本机。
/// 这样 App 本身不需要分发有版权的动画画面，也能实现“画面重叠对比”的体验。
@Observable
final class SceneImageStore {
    static let shared = SceneImageStore()

    /// 每次增删图片时递增，SwiftUI 视图读取它来触发刷新
    private(set) var revision = 0
    @ObservationIgnored private var cache: [String: UIImage] = [:]

    private var directory: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SceneImages", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func fileURL(for spotID: String) -> URL {
        // id 只包含字母数字和连字符，这里再做一次保护
        let safe = spotID.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        return directory.appendingPathComponent("\(safe).jpg")
    }

    func image(for spotID: String) -> UIImage? {
        _ = revision
        #if DEBUG
        if ProcessInfo.processInfo.environment["SEICHI_SIM_SCENE_IMAGE"] == "1" { return SimulatedImages.scene() }
        #endif
        if let cached = cache[spotID] { return cached }
        guard let img = UIImage(contentsOfFile: fileURL(for: spotID).path) else { return nil }
        cache[spotID] = img
        return img
    }

    func hasImage(for spotID: String) -> Bool { image(for: spotID) != nil }

    /// 保存图片（缩放到最长边 1600px 并压缩为 JPEG）。
    @discardableResult
    func save(_ data: Data, for spotID: String) -> Bool {
        guard let original = UIImage(data: data) else { return false }
        let image = original.downscaled(maxDimension: 1600)
        guard let jpeg = image.jpegData(compressionQuality: 0.85) else { return false }
        do {
            try jpeg.write(to: fileURL(for: spotID), options: .atomic)
            cache[spotID] = image
            revision += 1
            return true
        } catch {
            return false
        }
    }

    func delete(for spotID: String) {
        try? FileManager.default.removeItem(at: fileURL(for: spotID))
        cache[spotID] = nil
        revision += 1
    }
}

private extension UIImage {
    func downscaled(maxDimension: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxDimension else { return self }
        let scale = maxDimension / longest
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
