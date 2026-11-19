import Foundation
import UIKit
import ImageIO
import Vision
import Photos
import SeichiCore

/// 要上传的照片从哪来
enum UploadSource {
    /// App 里自己的相机（带我去复现 / 请人帮我拍）拍的：拍摄时就在现场
    case inAppCapture(location: GeoPoint?)
    /// 从系统相册选的原图数据
    case library(data: Data, itemIdentifier: String?)
}

/// 上传照片前在手机上做的检查（不联网、不花钱）。只收“在现场用相机拍的原图”，挡掉版权风险最高的三类图：
/// 1. 截图（看番时截的）——系统截图标记 / 没有相机信息；
/// 2. 网上下载、微信保存的图——没有相机信息；
/// 3. 对着屏幕翻拍——拍摄位置不在名场面 1 公里内（在家拍的）。
/// 再加一道：满屏文字的图（广告、聊天截图）。
/// 之后还有举报兜底：以“侵犯版权”举报 1 次就先隐藏，其他原因 3 人举报隐藏。
enum PhotoModeration {
    enum Problem: Equatable {
        case screenshot
        case noCamera
        case missingLocation
        case tooFar(meters: Double)
        case tooMuchText
    }

    struct Metadata {
        var make: String?
        var model: String?
        var location: GeoPoint?
        var isScreenshot = false
    }

    /// 从原图数据里读出相机信息、拍摄位置，以及是否为系统截图
    static func metadata(from data: Data) -> Metadata {
        var m = Metadata()
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] else { return m }
        if let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            m.make = tiff[kCGImagePropertyTIFFMake] as? String
            m.model = tiff[kCGImagePropertyTIFFModel] as? String
        }
        if let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any],
           let comment = exif[kCGImagePropertyExifUserComment] as? String,
           comment.localizedCaseInsensitiveContains("screenshot") {
            m.isScreenshot = true
        }
        if let gps = props[kCGImagePropertyGPSDictionary] as? [CFString: Any],
           var lat = gps[kCGImagePropertyGPSLatitude] as? Double,
           var lon = gps[kCGImagePropertyGPSLongitude] as? Double {
            if (gps[kCGImagePropertyGPSLatitudeRef] as? String) == "S" { lat = -lat }
            if (gps[kCGImagePropertyGPSLongitudeRef] as? String) == "W" { lon = -lon }
            m.location = GeoPoint(latitude: lat, longitude: lon)
        }
        return m
    }

    /// 相册里的这张图：是不是系统截图、拍摄位置（EXIF 里没有时用相册记录的位置）。需要读取照片的权限
    static func libraryInfo(itemIdentifier: String?) async -> (isScreenshot: Bool, location: GeoPoint?) {
        guard let id = itemIdentifier else { return (false, nil) }
        var status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status == .notDetermined { status = await PHPhotoLibrary.requestAuthorization(for: .readWrite) }
        guard status == .authorized || status == .limited,
              let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else { return (false, nil) }
        let loc = asset.location.map { GeoPoint(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude) }
        return (asset.mediaSubtypes.contains(.photoScreenshot), loc)
    }

    static func check(image: UIImage, source: UploadSource, spot: Spot) async -> Problem? {
        switch source {
        case .inAppCapture:
            return await hasTooMuchText(image) ? .tooMuchText : nil
        case .library(let data, let itemIdentifier):
            #if DEBUG
            // UI 测试：模拟器相册里的示例图没有相机信息和定位
            if ProcessInfo.processInfo.environment["SEICHI_SIM_LAT"] != nil { return nil }
            #endif
            var meta = metadata(from: data)
            let lib = await libraryInfo(itemIdentifier: itemIdentifier)
            meta.isScreenshot = meta.isScreenshot || lib.isScreenshot
            if meta.location == nil { meta.location = lib.location }
            switch PhotoProvenance.check(isInAppCapture: false, isScreenshot: meta.isScreenshot,
                                         cameraMake: meta.make, cameraModel: meta.model,
                                         photoLocation: meta.location, spot: spot.coordinate) {
            case .screenshot: return .screenshot
            case .noCamera: return .noCamera
            case .noLocation: return .missingLocation
            case .tooFar(let m): return .tooFar(meters: m)
            case .ok: break
            }
            return await hasTooMuchText(image) ? .tooMuchText : nil
        }
    }

    /// 识别到的文字占画面面积超过 12%，或者字数很多，就当作截图 / 广告
    static func hasTooMuchText(_ image: UIImage) async -> Bool {
        guard let cg = image.cgImage else { return false }
        return await withCheckedContinuation { cont in
            let request = VNRecognizeTextRequest { req, _ in
                let obs = (req.results as? [VNRecognizedTextObservation]) ?? []
                let area = obs.reduce(0.0) { $0 + Double($1.boundingBox.width * $1.boundingBox.height) }
                let chars = obs.compactMap { $0.topCandidates(1).first?.string.count }.reduce(0, +)
                cont.resume(returning: area > 0.12 || chars > 120)
            }
            request.recognitionLevel = .fast
            request.usesLanguageCorrection = false
            DispatchQueue.global(qos: .userInitiated).async {
                do { try VNImageRequestHandler(cgImage: cg, orientation: .up).perform([request]) }
                catch { cont.resume(returning: false) }
            }
        }
    }

    static func message(_ p: Problem) -> String {
        switch p {
        case .screenshot: return L("moderation.screenshot")
        case .noCamera: return L("moderation.noCamera")
        case .missingLocation: return L("moderation.missingLocation")
        case .tooFar(let m): return L("moderation.tooFar", NearbySearch.formatDistance(m))
        case .tooMuchText: return L("moderation.tooMuchText")
        }
    }
}
