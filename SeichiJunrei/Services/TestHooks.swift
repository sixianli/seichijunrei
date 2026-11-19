import SwiftUI
import PhotosUI
import UIKit

/// 端到端测试用的开关：只在 Debug 构建、并且 UI 测试设置了 SEICHI_UITEST=1 时生效，正式版里永远是关的。
/// - 选图：系统相册是另一个进程，测试点不到，改成直接给一张模拟照片，后面的审核、上传、提示照常走。
/// - 外部链接 / 地图 App：不真的跳出 App，而是把要打开的地址显示在一个测试能读到的小标签里。
enum TestHooks {
    static var isActive: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.environment["SEICHI_UITEST"] == "1"
        #else
        return false
        #endif
    }

    /// 每个测试开始前清掉会被测试改动、又会影响别的测试的偏好（自动拍、语音、叠图、“始终允许”提示）
    static func resetPreferencesIfNeeded() {
        guard isActive, ProcessInfo.processInfo.environment["SEICHI_RESET_PREFS"] == "1" else { return }
        for key in ["pgAutoShutter", "pgVoice", "pgGhost", "dismissedAlwaysPrompt"] {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    /// 测试指定的上传审核结果（screenshot / noCamera / missingLocation / tooFar / tooMuchText），不设就是通过
    static var moderationOverride: PhotoModeration.Problem?? {
        guard isActive, let v = ProcessInfo.processInfo.environment["SEICHI_MODERATION"] else { return nil }
        switch v {
        case "screenshot": return .some(.screenshot)
        case "noCamera": return .some(.noCamera)
        case "missingLocation": return .some(.missingLocation)
        case "tooFar": return .some(.tooFar(meters: 5200))
        case "tooMuchText": return .some(.tooMuchText)
        default: return .some(nil)
        }
    }
}

/// 打开 App 外面的东西（网页、地图 App、系统设置）都走这里
@MainActor
enum ExternalLinks {
    static func open(_ url: URL) {
        if TestHooks.isActive { TestURLProbe.record(url.absoluteString); return }
        UIApplication.shared.open(url)
    }

    /// SwiftUI 的 Link / openURL 也拦下来（挂在根视图上）
    static var action: OpenURLAction {
        OpenURLAction { url in
            guard TestHooks.isActive else { return .systemAction }
            // 打开链接的回调本来就在主线程
            MainActor.assumeIsolated { TestURLProbe.record(url.absoluteString) }
            return .handled
        }
    }
}

/// 测试读“刚才要打开的地址”：放在最上层的一个不接收点击的小窗口里，弹出的 sheet 也盖不住它
@MainActor
enum TestURLProbe {
    private static var window: UIWindow?
    private static var label: UILabel?

    static func record(_ text: String) {
        guard TestHooks.isActive else { return }
        if window == nil,
           let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
            let w = UIWindow(windowScene: scene)
            w.windowLevel = .alert + 1
            w.isUserInteractionEnabled = false
            w.backgroundColor = .clear
            let vc = UIViewController()
            vc.view.backgroundColor = .clear
            let l = UILabel()
            l.font = .systemFont(ofSize: 7)
            l.textColor = .systemGray
            l.numberOfLines = 1
            l.accessibilityIdentifier = "debugLastURL"
            l.translatesAutoresizingMaskIntoConstraints = false
            vc.view.addSubview(l)
            NSLayoutConstraint.activate([
                l.leadingAnchor.constraint(equalTo: vc.view.leadingAnchor, constant: 4),
                l.trailingAnchor.constraint(lessThanOrEqualTo: vc.view.trailingAnchor, constant: -4),
                l.bottomAnchor.constraint(equalTo: vc.view.bottomAnchor, constant: -2),
            ])
            w.rootViewController = vc
            w.isHidden = false
            window = w
            label = l
        }
        label?.text = text
        label?.accessibilityLabel = text
    }
}

/// 选一张照片的按钮：平时是系统相册选择器；端到端测试时直接给一张模拟照片
struct PhotoPickerButton<Label: View>: View {
    /// 需要相册里的照片 ID（读取拍摄位置、是否截图）时用 .shared()
    var usesSharedLibrary = false
    var onPick: (Data, String?) -> Void
    @ViewBuilder var label: () -> Label
    @State private var picked: PhotosPickerItem?

    var body: some View {
        if TestHooks.isActive {
            Button {
                if let data = SimulatedImages.photo().jpegData(compressionQuality: 0.85) { onPick(data, nil) }
            } label: { label() }
        } else {
            picker
                .onChange(of: picked) { _, item in
                    guard let item else { return }
                    Task {
                        if let data = try? await item.loadTransferable(type: Data.self) {
                            await MainActor.run { onPick(data, item.itemIdentifier) }
                        }
                        await MainActor.run { picked = nil }
                    }
                }
        }
    }

    @ViewBuilder private var picker: some View {
        if usesSharedLibrary {
            PhotosPicker(selection: $picked, matching: .images, preferredItemEncoding: .current,
                         photoLibrary: .shared()) { label() }
        } else {
            PhotosPicker(selection: $picked, matching: .images) { label() }
        }
    }
}
