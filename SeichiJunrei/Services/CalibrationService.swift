import Foundation
import Observation
import CloudKit
import CoreLocation
import SeichiCore

/// 把用户在现场的机位校准提交到 CloudKit 公共数据库（无需服务器、无需登录 App）。
///
/// 开发者在 CloudKit Console（容器 iCloud.com.xianlisi.seichijunrei → Public Database → Calibration）
/// 查看、导出这些记录，筛选后合并进 spots.json。
@Observable
final class CalibrationService {
    static let shared = CalibrationService()
    static let containerID = "iCloud.com.xianlisi.seichijunrei"
    static let recordType = "Calibration"

    enum SubmitResult: Equatable {
        case submitted
        /// 暂时无法上传（无网络等），已保存在本机，稍后自动重试
        case queued
        /// 设备未登录 iCloud，已保存在本机
        case noAccount
        case failed(String)
    }

    /// 等待上传的提交（保存在本机）
    private(set) var pending: [CalibrationSubmission] = []
    @ObservationIgnored private let fileURL: URL

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Calibration", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("pending.json")
        if let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode([CalibrationSubmission].self, from: data) {
            pending = saved
        }
    }

    static var appVersion: String {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))"
    }

    @MainActor
    func submit(_ submission: CalibrationSubmission) async -> SubmitResult {
        #if DEBUG
        // UI 测试 / 模拟器：不访问 CloudKit（未签名的测试构建没有 iCloud 权限）
        if ProcessInfo.processInfo.environment["SEICHI_FAKE_SUBMIT"] == "1" { return .submitted }
        #endif
        let result = await upload(submission)
        switch result {
        case .queued, .noAccount: enqueue(submission)
        case .submitted, .failed: break
        }
        return result
    }

    /// App 启动时调用：有待上传的提交才会访问 CloudKit
    @MainActor
    func retryPending() async {
        guard !pending.isEmpty else { return }
        for item in pending {
            if await upload(item) == .submitted {
                pending.removeAll { $0.id == item.id }
            }
        }
        persist()
    }

    private func upload(_ s: CalibrationSubmission) async -> SubmitResult {
        let container = CKContainer(identifier: Self.containerID)
        do {
            guard try await container.accountStatus() == .available else { return .noAccount }
            try await container.publicCloudDatabase.save(Self.record(for: s))
            return .submitted
        } catch let error as CKError {
            switch error.code {
            case .networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited, .zoneBusy:
                return .queued
            case .notAuthenticated:
                return .noAccount
            default:
                return .failed(error.localizedDescription)
            }
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    static func record(for s: CalibrationSubmission) -> CKRecord {
        let r = CKRecord(recordType: recordType, recordID: CKRecord.ID(recordName: s.id))
        r["spotID"] = s.spotID
        r["latitude"] = s.reading.latitude
        r["longitude"] = s.reading.longitude
        r["location"] = CLLocation(latitude: s.reading.latitude, longitude: s.reading.longitude)
        r["horizontalAccuracy"] = s.reading.horizontalAccuracy
        r["heading"] = s.reading.heading.map { NSNumber(value: $0) }
        r["headingAccuracy"] = s.reading.headingAccuracy
        r["pitch"] = s.reading.pitch.map { NSNumber(value: $0) }
        r["note"] = s.note
        r["appVersion"] = s.appVersion
        r["locale"] = s.locale
        r["capturedAt"] = s.createdAt
        return r
    }

    @MainActor
    private func enqueue(_ s: CalibrationSubmission) {
        guard !pending.contains(where: { $0.id == s.id }) else { return }
        pending.append(s)
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(pending) { try? data.write(to: fileURL, options: .atomic) }
    }

    /// 无法使用 CloudKit 时，用户可以复制这段 JSON 发给开发者
    static func json(for s: CalibrationSubmission) -> String {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        return (try? enc.encode(s)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }
}
