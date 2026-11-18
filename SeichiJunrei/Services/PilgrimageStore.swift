import Foundation
import Observation
import UIKit
import SeichiCore

/// 巡礼相册里的一张照片（在“带我去复现”或“请人帮我拍”里拍的，关联到名场面）
struct AlbumPhoto: Codable, Identifiable, Hashable {
    enum Kind: String, Codable { case scene, photographer }
    var id: String
    var spotID: String
    var date: Date
    var fileName: String
    var kind: Kind
    var latitude: Double?
    var longitude: Double?

    var location: GeoPoint? {
        guard let latitude, let longitude else { return nil }
        return GeoPoint(latitude: latitude, longitude: longitude)
    }
}

/// 巡礼足迹：记录达成的名场面和现场照片，以及“我的巡礼相册”（只保存在本机）。
@Observable
final class PilgrimageStore {
    static let shared = PilgrimageStore()

    private(set) var log = PilgrimageLog()
    /// 巡礼相册，新拍的在前
    private(set) var album: [AlbumPhoto] = []
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
        try? FileManager.default.createDirectory(at: albumDirectory, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: albumURL), let saved = try? JSONDecoder().decode([AlbumPhoto].self, from: data) {
            album = saved
        }
    }

    private var logURL: URL { directory.appendingPathComponent("log.json") }
    private var albumDirectory: URL { directory.appendingPathComponent("Album", isDirectory: true) }
    private var albumURL: URL { directory.appendingPathComponent("album.json") }

    // MARK: 巡礼相册

    func albumPhotos(for spotID: String) -> [AlbumPhoto] { album.filter { $0.spotID == spotID } }

    func albumFileURL(_ photo: AlbumPhoto) -> URL { albumDirectory.appendingPathComponent(photo.fileName) }

    func albumImage(_ photo: AlbumPhoto) -> UIImage? {
        if let cached = photoCache["album/" + photo.fileName] { return cached }
        let img = UIImage(contentsOfFile: albumFileURL(photo).path)
        photoCache["album/" + photo.fileName] = img
        return img
    }

    /// 拍完的照片存进巡礼相册（同时也已经存进系统相册）
    @discardableResult
    func addToAlbum(_ image: UIImage, spotID: String, kind: AlbumPhoto.Kind, location: GeoPoint?) -> AlbumPhoto? {
        guard let data = image.jpegData(compressionQuality: 0.88) else { return nil }
        let id = UUID().uuidString
        let name = "\(id).jpg"
        do { try data.write(to: albumDirectory.appendingPathComponent(name), options: .atomic) } catch { return nil }
        let photo = AlbumPhoto(id: id, spotID: spotID, date: Date(), fileName: name, kind: kind,
                               latitude: location?.latitude, longitude: location?.longitude)
        album.insert(photo, at: 0)
        photoCache["album/" + name] = image
        persistAlbum()
        return photo
    }

    func deleteFromAlbum(_ photo: AlbumPhoto) {
        album.removeAll { $0.id == photo.id }
        try? FileManager.default.removeItem(at: albumFileURL(photo))
        photoCache["album/" + photo.fileName] = nil
        persistAlbum()
    }

    private func persistAlbum() {
        if let data = try? JSONEncoder().encode(album) { try? data.write(to: albumURL, options: .atomic) }
    }

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
