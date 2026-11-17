import Foundation
import Observation
import UIKit
import SeichiCore

/// 巡礼足迹：记录达成的名场面和现场照片（只保存在本机）。
@Observable
final class PilgrimageStore {
    static let shared = PilgrimageStore()

    private(set) var log = PilgrimageLog()
    @ObservationIgnored private var photoCache: [String: UIImage] = [:]
    @ObservationIgnored private let directory: URL

    init(directory: URL? = nil) {
        let dir = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Pilgrimage", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.directory = dir
        if let data = try? Data(contentsOf: logURL), let saved = try? JSONDecoder().decode(PilgrimageLog.self, from: data) {
            log = saved
        }
    }

    private var logURL: URL { directory.appendingPathComponent("log.json") }

    func record(for spotID: String) -> PilgrimageRecord? { log.record(for: spotID) }

    /// 对准名场面时调用
    func markCompleted(spotID: String, heading: Double?, latitude: Double?, longitude: Double?) {
        log.markCompleted(PilgrimageRecord(spotID: spotID, date: Date(), heading: heading,
                                           latitude: latitude, longitude: longitude))
        persist()
    }

    /// 保存现场照片并关联到该圣地（未达成时也会一并记为达成）
    func attachPhoto(_ image: UIImage, spotID: String) {
        guard let data = image.jpegData(compressionQuality: 0.88) else { return }
        let name = "\(spotID.filter { $0.isLetter || $0.isNumber || $0 == "-" })-\(Int(Date().timeIntervalSince1970)).jpg"
        do {
            try data.write(to: directory.appendingPathComponent(name), options: .atomic)
        } catch { return }
        if log.record(for: spotID) == nil {
            log.markCompleted(PilgrimageRecord(spotID: spotID, date: Date()))
        }
        if let old = log.setPhoto(name, for: spotID) {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(old))
            photoCache[old] = nil
        }
        photoCache[name] = image
        persist()
    }

    func photo(for spotID: String) -> UIImage? {
        guard let name = log.record(for: spotID)?.photoFileName else { return nil }
        if let cached = photoCache[name] { return cached }
        let img = UIImage(contentsOfFile: directory.appendingPathComponent(name).path)
        photoCache[name] = img
        return img
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(log) { try? data.write(to: logURL, options: .atomic) }
    }
}
