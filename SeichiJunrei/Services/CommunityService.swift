import Foundation
import Observation
import CloudKit
import CoreLocation
import UIKit
import SeichiCore

/// 巡礼者投稿的现场照片
struct CommunityPhoto: Identifiable, Hashable {
    var id: String            // CloudKit recordName
    var spotID: String
    var imageURL: URL         // 已缓存到本机的图片文件
    var caption: String
    var authorID: String?     // 匿名的 iCloud 用户 ID（用于屏蔽）
    var date: Date
    var isMine: Bool
}

/// 我投稿的名场面（只在本机记录 ID，状态从 CloudKit 读）
struct MySubmission: Identifiable, Codable, Hashable {
    var id: String
    var title: String
    var status: String        // pending / approved / rejected
    var date: Date
}

/// 用户投稿：给名场面上传现场照片、投稿新的名场面、举报、屏蔽。
///
/// 全部存在 CloudKit 公共数据库（容器 iCloud.com.xianlisi.seichijunrei），图片用 CKAsset 保存，
/// 不需要自己的服务器或对象存储。记录类型与字段见 README「用户投稿（CloudKit）」。
///
/// 审核策略：
/// - 已有名场面的照片：先发后管。被 3 位不同用户举报自动隐藏；开发者可在 CloudKit Console 把 status 改成 hidden。
/// - 新名场面：先审后发。status 默认 pending，开发者在 Console 改成 approved 后所有人可见。
@Observable
final class CommunityService {
    static let shared = CommunityService()

    enum RecordType {
        static let photo = "SpotPhoto"
        static let scene = "SceneSubmission"
        static let report = "Report"
    }

    enum Failure: Error, Equatable {
        case noAccount
        case network
        case rejected      // 内容没有通过过滤
        case other(String)
    }

    private(set) var approvedScenes: [Spot] = []
    private(set) var photosBySpot: [String: [CommunityPhoto]] = [:]
    private(set) var mySubmissions: [MySubmission] = []
    private(set) var blockedUsers: Set<String> = []

    /// 用到时才创建：没有 iCloud 权限的构建（如 UI 测试）创建 CKContainer 会直接崩溃
    /// 用到时才创建，并一直持有：没有 iCloud 权限的构建（如 UI 测试）创建 CKContainer 会直接崩溃；
    /// 每次临时新建的话，上传还没完成容器就被释放，回调永远不会回来（表现为一直转圈）
    @ObservationIgnored private var cachedContainer: CKContainer?
    private var container: CKContainer {
        if let c = cachedContainer { return c }
        let c = CKContainer(identifier: CalibrationService.containerID)
        cachedContainer = c
        return c
    }
    @ObservationIgnored private var database: CKDatabase { container.publicCloudDatabase }
    @ObservationIgnored private var myUserID: String?
    @ObservationIgnored private let cacheDir: URL
    @ObservationIgnored private let defaults = UserDefaults.standard

    /// UI 测试 / 模拟器：不访问 CloudKit，用内存里的假数据
    @ObservationIgnored private let fake: Bool

    init() {
        cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Community", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        blockedUsers = Set(defaults.stringArray(forKey: "blockedUsers") ?? [])
        if let data = defaults.data(forKey: "mySubmissions"),
           let saved = try? JSONDecoder().decode([MySubmission].self, from: data) {
            mySubmissions = saved
        }
        #if DEBUG
        // UI 测试的构建没有签名、没有 iCloud 权限：一律用假数据（SEICHI_SIM_LAT 只有 UI 测试会设置）
        let env = ProcessInfo.processInfo.environment
        fake = env["SEICHI_FAKE_COMMUNITY"] == "1" || env["SEICHI_SIM_LAT"] != nil
            || env["XCTestConfigurationFilePath"] != nil   // 单元测试宿主
        #else
        fake = false
        #endif
    }

    // MARK: - 读取

    /// 审核通过的用户投稿名场面（App 启动时加载，合并进地图）
    func loadApprovedScenes() async {
        if fake { return }
        let query = CKQuery(recordType: RecordType.scene, predicate: NSPredicate(format: "status == %@", "approved"))
        guard let records = try? await allRecords(query) else { return }
        await resolveMyUserID()
        let spots = records
            .filter { r in !(r.creatorUserRecordID.map { blockedUsers.contains($0.recordName) } ?? false) }
            .compactMap { spot(from: $0) }
        await MainActor.run { approvedScenes = spots }
    }

    /// 某个名场面的巡礼者照片（排除被隐藏、被举报过多、被我屏蔽的）
    func loadPhotos(spotID: String) async {
        if fake { await loadFakePhotos(spotID: spotID); return }
        await resolveMyUserID()
        let query = CKQuery(recordType: RecordType.photo, predicate: NSPredicate(format: "spotID == %@", spotID))
        guard let records = try? await allRecords(query, keys: nil) else { return }
        let visible = records.filter { ($0["status"] as? String) != "hidden" }
        let hidden = await reportedTargets(visible.map(\.recordID.recordName))
        let photos: [CommunityPhoto] = visible.compactMap { r in
            let id = r.recordID.recordName
            let author = r.creatorUserRecordID?.recordName
            guard !hidden.contains(id), !(author.map(blockedUsers.contains) ?? false),
                  let url = cacheAsset(r["image"] as? CKAsset, name: id) else { return nil }
            return CommunityPhoto(id: id, spotID: spotID, imageURL: url, caption: r["caption"] as? String ?? "",
                                  authorID: author, date: r.creationDate ?? Date(),
                                  isMine: author != nil && (author == myUserID || author == CKCurrentUserDefaultName))
        }
        .sorted { $0.date > $1.date }
        await MainActor.run { photosBySpot[spotID] = photos }
    }

    /// 被不同用户举报达到阈值的内容
    private func reportedTargets(_ ids: [String]) async -> Set<String> {
        guard !ids.isEmpty else { return [] }
        let query = CKQuery(recordType: RecordType.report, predicate: NSPredicate(format: "targetID IN %@", ids))
        guard let records = try? await allRecords(query, keys: ["targetID"]) else { return [] }
        let pairs = records.compactMap { r -> (target: String, reporter: String)? in
            guard let t = r["targetID"] as? String else { return nil }
            return (t, r.creatorUserRecordID?.recordName ?? r.recordID.recordName)
        }
        return ReportPolicy.hiddenTargets(pairs)
    }

    // MARK: - 上传

    /// 上传一张现场照片到某个名场面
    @MainActor
    func uploadPhoto(_ image: UIImage, spotID: String, caption: String) async -> Result<Void, Failure> {
        guard ContentFilter.isClean(caption, required: false, maxLength: 200) else { return .failure(.rejected) }
        if fake {
            let url = cacheDir.appendingPathComponent("fake-\(UUID().uuidString).jpg")
            try? Self.jpeg(image)?.write(to: url)
            let photo = CommunityPhoto(id: UUID().uuidString, spotID: spotID, imageURL: url, caption: caption,
                                       authorID: "me", date: Date(), isMine: true)
            photosBySpot[spotID, default: []].insert(photo, at: 0)
            return .success(())
        }
        guard let file = Self.writeTemporaryJPEG(image) else { return .failure(.other("image")) }
        let record = CKRecord(recordType: RecordType.photo)
        record["spotID"] = spotID
        record["image"] = CKAsset(fileURL: file)
        record["caption"] = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        record["status"] = "visible"
        record["width"] = Int(image.size.width)
        record["height"] = Int(image.size.height)
        record["locale"] = Locale.current.identifier
        record["appVersion"] = CalibrationService.appVersion
        let result = await save(record)
        if case .success = result { await loadPhotos(spotID: spotID) }
        return result
    }

    /// 投稿新名场面（先审后发：status = pending）
    @MainActor
    func submitScene(_ draft: SceneDraft, image: UIImage) async -> Result<Void, Failure> {
        guard draft.canSubmit, let lat = draft.latitude, let lon = draft.longitude else { return .failure(.rejected) }
        let id = UUID().uuidString
        let entry = MySubmission(id: id, title: draft.sceneTitle, status: "pending", date: Date())
        if fake {
            mySubmissions.insert(entry, at: 0)
            persistMySubmissions()
            return .success(())
        }
        guard let file = Self.writeTemporaryJPEG(image) else { return .failure(.other("image")) }
        let r = CKRecord(recordType: RecordType.scene, recordID: CKRecord.ID(recordName: id))
        r["workTitle"] = draft.workTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        r["mediaType"] = draft.mediaType.rawValue
        r["sceneTitle"] = draft.sceneTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        r["episode"] = draft.episode.trimmingCharacters(in: .whitespacesAndNewlines)
        r["placeName"] = draft.placeName.trimmingCharacters(in: .whitespacesAndNewlines)
        r["story"] = draft.story.trimmingCharacters(in: .whitespacesAndNewlines)
        r["latitude"] = lat
        r["longitude"] = lon
        r["location"] = CLLocation(latitude: lat, longitude: lon)
        r["heading"] = draft.heading ?? 0
        r["pitch"] = draft.pitch ?? 0
        r["photo"] = CKAsset(fileURL: file)
        r["status"] = "pending"
        r["locale"] = Locale.current.identifier
        r["appVersion"] = CalibrationService.appVersion
        let result = await save(r)
        if case .success = result {
            mySubmissions.insert(entry, at: 0)
            persistMySubmissions()
        }
        return result
    }

    /// 刷新我的投稿的审核状态
    func refreshMySubmissions() async {
        if fake { return }
        let ids = mySubmissions.map { CKRecord.ID(recordName: $0.id) }
        guard !ids.isEmpty, let results = try? await database.records(for: ids, desiredKeys: ["status"]) else { return }
        await MainActor.run {
            for i in mySubmissions.indices {
                if case .success(let r) = results[CKRecord.ID(recordName: mySubmissions[i].id)],
                   let status = r["status"] as? String {
                    mySubmissions[i].status = status
                }
            }
            persistMySubmissions()
        }
    }

    // MARK: - 举报 / 屏蔽 / 删除

    @MainActor
    func report(targetType: String, targetID: String, reason: String) async -> Result<Void, Failure> {
        if fake { return .success(()) }
        let r = CKRecord(recordType: RecordType.report)
        r["targetType"] = targetType
        r["targetID"] = targetID
        r["reason"] = reason
        return await save(r)
    }

    /// 屏蔽某位用户：他的照片和投稿在本机都不再显示
    @MainActor
    func block(userID: String) {
        blockedUsers.insert(userID)
        defaults.set(Array(blockedUsers), forKey: "blockedUsers")
        for (spot, photos) in photosBySpot { photosBySpot[spot] = photos.filter { $0.authorID != userID } }
        approvedScenes.removeAll { $0.communityAuthorID == userID }
    }

    @MainActor
    func unblockAll() {
        blockedUsers = []
        defaults.removeObject(forKey: "blockedUsers")
    }

    /// 删除自己上传的照片
    @MainActor
    func delete(_ photo: CommunityPhoto) async -> Result<Void, Failure> {
        if !fake {
            do {
                _ = try await database.deleteRecord(withID: CKRecord.ID(recordName: photo.id))
            } catch {
                return .failure(Self.map(error))
            }
        }
        photosBySpot[photo.spotID]?.removeAll { $0.id == photo.id }
        return .success(())
    }

    // MARK: - 工具

    private func save(_ record: CKRecord) async -> Result<Void, Failure> {
        let db = database
        let c = container
        do {
            // 最多等 60 秒：网络不好时给用户明确的失败提示，而不是一直转圈
            return try await withThrowingTaskGroup(of: Result<Void, Failure>.self) { group in
                group.addTask {
                    guard try await c.accountStatus() == .available else { return .failure(.noAccount) }
                    try await db.save(record)
                    return .success(())
                }
                group.addTask {
                    try await Task.sleep(for: .seconds(60))
                    return .failure(.network)
                }
                let first = try await group.next() ?? .failure(.network)
                group.cancelAll()
                return first
            }
        } catch {
            return .failure(Self.map(error))
        }
    }

    private static func map(_ error: Error) -> Failure {
        guard let ck = error as? CKError else { return .other(error.localizedDescription) }
        switch ck.code {
        case .notAuthenticated: return .noAccount
        case .networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited, .zoneBusy: return .network
        default: return .other(ck.localizedDescription)
        }
    }

    private func resolveMyUserID() async {
        guard myUserID == nil, !fake else { return }
        myUserID = try? await container.userRecordID().recordName
    }

    private func allRecords(_ query: CKQuery, keys: [String]? = nil) async throws -> [CKRecord] {
        var out: [CKRecord] = []
        var (results, cursor) = try await database.records(matching: query, desiredKeys: keys, resultsLimit: 200)
        out += results.compactMap { try? $0.1.get() }
        while let c = cursor, out.count < 1000 {
            (results, cursor) = try await database.records(continuingMatchFrom: c, desiredKeys: keys, resultsLimit: 200)
            out += results.compactMap { try? $0.1.get() }
        }
        return out
    }

    /// CKAsset 的文件是临时的，复制到缓存目录
    private func cacheAsset(_ asset: CKAsset?, name: String) -> URL? {
        let dest = cacheDir.appendingPathComponent("\(name).jpg")
        if FileManager.default.fileExists(atPath: dest.path) { return dest }
        guard let src = asset?.fileURL else { return nil }
        try? FileManager.default.copyItem(at: src, to: dest)
        return FileManager.default.fileExists(atPath: dest.path) ? dest : nil
    }

    /// 压缩到长边 1600 像素的 JPEG。重新编码会去掉 EXIF（包括 GPS），保护用户隐私。
    static func jpeg(_ image: UIImage) -> Data? {
        let maxSide: CGFloat = 1600
        let scale = min(1, maxSide / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return resized.jpegData(compressionQuality: 0.8)
    }

    private static func writeTemporaryJPEG(_ image: UIImage) -> URL? {
        guard let data = jpeg(image) else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).jpg")
        return (try? data.write(to: url)) != nil ? url : nil
    }

    private func persistMySubmissions() {
        if let data = try? JSONEncoder().encode(mySubmissions) { defaults.set(data, forKey: "mySubmissions") }
    }

    /// 审核通过的投稿 → 名场面
    private func spot(from r: CKRecord) -> Spot? {
        guard let lat = r["latitude"] as? Double, let lon = r["longitude"] as? Double,
              let title = r["sceneTitle"] as? String, let work = r["workTitle"] as? String else { return nil }
        let id = r.recordID.recordName
        var photo: SeichiCore.SpotPhoto?
        if let url = cacheAsset(r["photo"] as? CKAsset, name: "scene-\(id)") {
            photo = SeichiCore.SpotPhoto(url: url.absoluteString, author: L("community.author"), license: L("community.license"))
        }
        var spot = Spot(id: "community-\(id)", work: work,
                        mediaType: MediaType(rawValue: r["mediaType"] as? String ?? "") ?? .anime,
                        placeName: r["placeName"] as? String ?? "", sceneTitle: title,
                        episode: (r["episode"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                        story: r["story"] as? String ?? "",
                        coordinate: GeoPoint(latitude: lat, longitude: lon),
                        sceneHeading: GeoMath.normalize(r["heading"] as? Double ?? 0),
                        scenePitch: r["pitch"] as? Double, arrivalRadius: 40, tint: "#5B7DB1",
                        photo: photo)
        spot.communityAuthorID = r.creatorUserRecordID?.recordName ?? ""
        return spot
    }

    #if DEBUG
    private func loadFakePhotos(spotID: String) async {
        await MainActor.run {
            guard photosBySpot[spotID] == nil else { return }
            let url = cacheDir.appendingPathComponent("fake-sample.jpg")
            if !FileManager.default.fileExists(atPath: url.path) {
                try? Self.jpeg(SimulatedImages.photo())?.write(to: url)
            }
            photosBySpot[spotID] = [CommunityPhoto(id: "fake-1", spotID: spotID, imageURL: url,
                                                   caption: "傍晚六点，光线和片中一样", authorID: "someone",
                                                   date: Date().addingTimeInterval(-86_400), isMine: false)]
        }
    }
    #else
    private func loadFakePhotos(spotID: String) async {}
    #endif
}
