import Foundation
import UIKit
import ImageIO
import Vision
import Photos
import SeichiCore

/// 上传照片前在手机上做的自动检查（不联网、不花钱）：
/// 1. 照片必须带拍摄位置，且在名场面 1 公里以内拍的——网上下载的图、截图、广告图基本都没有这个信息；
/// 2. 满屏文字的图（截图、广告、联系方式）直接拒绝。
/// 之后还有举报兜底：3 个不同的人举报就自动隐藏。
enum PhotoModeration {
    enum Problem: Equatable {
        case missingLocation
        case tooFar(meters: Double)
        case tooMuchText
    }

    /// 从原图数据里读出拍摄位置（EXIF GPS）
    static func gpsLocation(from data: Data) -> GeoPoint? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let gps = props[kCGImagePropertyGPSDictionary] as? [CFString: Any],
              var lat = gps[kCGImagePropertyGPSLatitude] as? Double,
              var lon = gps[kCGImagePropertyGPSLongitude] as? Double else { return nil }
        if (gps[kCGImagePropertyGPSLatitudeRef] as? String) == "S" { lat = -lat }
        if (gps[kCGImagePropertyGPSLongitudeRef] as? String) == "W" { lon = -lon }
        return GeoPoint(latitude: lat, longitude: lon)
    }

    /// EXIF 里没有位置时，再从照片图库里读（需要用户允许访问照片）
    static func libraryLocation(itemIdentifier: String?) async -> GeoPoint? {
        guard let id = itemIdentifier else { return nil }
        var status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if status == .notDetermined { status = await PHPhotoLibrary.requestAuthorization(for: .readWrite) }
        guard status == .authorized || status == .limited,
              let loc = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject?.location
        else { return nil }
        return GeoPoint(latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude)
    }

    static func check(image: UIImage, photoLocation: GeoPoint?, spot: Spot) async -> Problem? {
        #if DEBUG
        // UI 测试的模拟器照片没有定位
        if ProcessInfo.processInfo.environment["SEICHI_SIM_LAT"] != nil, photoLocation == nil { return nil }
        #endif
        switch PhotoLocationCheck.check(photoLocation: photoLocation, spot: spot.coordinate) {
        case .missingLocation: return .missingLocation
        case .tooFar(let m): return .tooFar(meters: m)
        case .ok: break
        }
        if await hasTooMuchText(image) { return .tooMuchText }
        return nil
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
        case .missingLocation: return L("moderation.missingLocation")
        case .tooFar(let m): return L("moderation.tooFar", NearbySearch.formatDistance(m))
        case .tooMuchText: return L("moderation.tooMuchText")
        }
    }
}
