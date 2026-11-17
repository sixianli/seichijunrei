import SwiftUI
import UIKit
import LinkPresentation
import SeichiCore

/// 巡礼分享卡（竖版 4:5，导出为 1080×1350）。
/// 设计目标：一眼看出“我真的来到了这里”——现场照片 / 作中 vs 现实对比、到达日期、坐标与朝向、“巡礼达成”印章。
struct ShareCardView: View {
    enum Layout: String, CaseIterable, Identifiable {
        case comparison, single
        var id: String { rawValue }
    }

    static let size = CGSize(width: 360, height: 450)
    /// 图片区域的精确尺寸（卡片宽度减去左右边距）
    static let imageSize = CGSize(width: 360 - 36, height: 232)

    let spot: Spot
    let record: PilgrimageRecord?
    let photo: UIImage?
    let sceneImage: UIImage?
    let layout: Layout

    private var date: Date { record?.date ?? Date() }

    var body: some View {
        ZStack {
            LinearGradient(colors: [spot.tintColor, spot.tintColor.opacity(0.55), .black],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(alignment: .leading, spacing: 9) {
                header
                imageArea
                    .frame(width: Self.imageSize.width, height: Self.imageSize.height)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(alignment: .bottomTrailing) {
                        PilgrimageStamp(date: date).padding(8)
                    }
                Text(L("share.headline"))
                    .font(.system(size: 12, weight: .semibold))
                    .opacity(0.85)
                Text(spot.workTitle)
                    .font(.system(size: 22, weight: .heavy))
                    .lineLimit(1).minimumScaleFactor(0.5)
                Text(spot.quotedSceneTitle)
                    .font(.system(size: 15, weight: .bold))
                    .lineLimit(1).minimumScaleFactor(0.6)
                details
                Spacer(minLength: 0)
                footer
            }
            .padding(18)
            .foregroundStyle(.white)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .environment(\.colorScheme, .dark)
    }

    private var header: some View {
        HStack {
            Label(L("share.badge"), systemImage: "checkmark.seal.fill")
                .font(.system(size: 12, weight: .bold))
            Spacer()
            Text(date.formatted(date: .long, time: .omitted))
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .opacity(0.85)
        }
    }

    @ViewBuilder private var imageArea: some View {
        let w = Self.imageSize.width
        let h = Self.imageSize.height
        if layout == .comparison {
            // 上下各占一半，用精确尺寸 + 裁剪，避免 scaledToFill 的图片溢出盖住另一半
            let half = (h - 2) / 2
            VStack(spacing: 2) {
                labeled(L("share.labelScene"), width: w, height: half) { sceneView }
                labeled(L("share.labelReal"), width: w, height: half) { photoView }
            }
        } else {
            photoView.frame(width: w, height: h).clipped()
        }
    }

    @ViewBuilder private var sceneView: some View {
        if let sceneImage {
            Image(uiImage: sceneImage).resizable().scaledToFill()
        } else {
            SceneArtwork(spot: spot, compact: true)
        }
    }

    @ViewBuilder private var photoView: some View {
        if let photo {
            Image(uiImage: photo).resizable().scaledToFill()
        } else {
            SceneArtwork(spot: spot)
        }
    }

    private func labeled<Content: View>(_ label: String, width: CGFloat, height: CGFloat,
                                        @ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(width: width, height: height)
            .clipped()
            .overlay(alignment: .topLeading) {
                Text(label)
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(.black.opacity(0.55), in: Capsule())
                    .padding(6)
            }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(spot.placeName, systemImage: "mappin.and.ellipse")
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
            HStack(spacing: 8) {
                Label(ShareFormatting.coordinate(latitude: record?.latitude ?? spot.coordinate.latitude,
                                                 longitude: record?.longitude ?? spot.coordinate.longitude),
                      systemImage: "location.fill")
                if let h = record?.heading ?? Optional(spot.sceneHeading) {
                    Label(L("share.facing", Compass.name(h), Int(h.rounded()) % 360), systemImage: "safari")
                }
            }
            .font(.system(size: 10, weight: .medium).monospacedDigit())
            .opacity(0.85)
        }
    }

    private var footer: some View {
        HStack(alignment: .lastTextBaseline) {
            Image(systemName: "sparkles.tv.fill")
            Text(L("map.title")).font(.system(size: 12, weight: .bold))
            Spacer()
            Text("#\(L("share.hashtagApp"))").font(.system(size: 10, weight: .medium)).opacity(0.75)
        }
    }
}

/// 仿印章（御朱印风）的“巡礼达成”戳
struct PilgrimageStamp: View {
    let date: Date
    private let red = Color(red: 0.86, green: 0.16, blue: 0.2)

    var body: some View {
        ZStack {
            Circle().stroke(red, lineWidth: 3)
            Circle().inset(by: 5).stroke(red, lineWidth: 1)
            VStack(spacing: 1) {
                Text(L("share.stamp"))
                    .font(.system(size: 14, weight: .heavy))
                    .lineLimit(1).minimumScaleFactor(0.5)
                Text(date.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits)))
                    .font(.system(size: 8, weight: .bold).monospacedDigit())
            }
            .foregroundStyle(red)
            .padding(10)
        }
        .frame(width: 74, height: 74)
        .background(Circle().fill(.white.opacity(0.88)))
        .rotationEffect(.degrees(-12))
        .shadow(color: .black.opacity(0.3), radius: 3)
    }
}

/// 分享页：预览卡片、切换版式、分享（图片 + 文案）或保存到相册。
struct ShareComposerView: View {
    let spot: Spot

    @Environment(PilgrimageStore.self) private var pilgrimage
    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale
    @State private var layout: ShareCardView.Layout = .single
    @State private var rendered: UIImage?
    @State private var showActivity = false
    @State private var message: String?

    private var sceneImage: UIImage? { SceneImageStore.shared.image(for: spot.id) }
    private var photo: UIImage? { pilgrimage.photo(for: spot.id) }

    private var card: ShareCardView {
        ShareCardView(spot: spot, record: pilgrimage.record(for: spot.id), photo: photo,
                      sceneImage: sceneImage, layout: layout)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    card
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(L("share.title"))
                        .accessibilityIdentifier("shareCard")

                    Picker(L("share.layout"), selection: $layout) {
                        Text(L("share.layoutSingle")).tag(ShareCardView.Layout.single)
                        Text(L("share.layoutCompare")).tag(ShareCardView.Layout.comparison)
                    }
                    .pickerStyle(.segmented)

                    if photo == nil {
                        hint(L("share.noPhotoHint"), symbol: "camera")
                    }
                    if layout == .comparison && sceneImage == nil {
                        hint(L("share.noSceneImageHint"), symbol: "photo.badge.plus")
                    }

                    HStack(spacing: 12) {
                        Button {
                            rendered = renderCard()
                            showActivity = rendered != nil
                        } label: {
                            Label(L("share.share"), systemImage: "square.and.arrow.up")
                                .font(.headline)
                                .frame(maxWidth: .infinity, minHeight: 34)
                        }
                        .glassButton(prominent: true, tint: spot.tintColor)
                        .controlSize(.large)
                        .accessibilityIdentifier("shareButton")
                        Button {
                            if let image = renderCard() {
                                UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                                message = L("camera.saved")
                            }
                        } label: {
                            Image(systemName: "square.and.arrow.down")
                                .font(.headline)
                                .frame(minWidth: 34, minHeight: 34)
                        }
                        .glassButton()
                        .controlSize(.large)
                        .accessibilityLabel(L("share.save"))
                        .accessibilityIdentifier("saveCard")
                    }
                    if let message {
                        Text(message).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .padding()
            }
            .navigationTitle(L("share.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("common.close")) { dismiss() }.accessibilityIdentifier("closeShare")
                }
            }
            .sheet(isPresented: $showActivity) {
                if let rendered {
                    ActivityView(items: [ShareImageItem(image: rendered, title: L("share.title")), shareText])
                        .presentationDetents([.medium, .large])
                }
            }
            .onAppear {
                // 有名场面截图时默认用“作中 vs 现实”对比版
                if sceneImage != nil && photo != nil { layout = .comparison }
            }
        }
    }

    private func hint(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 渲染为 1080×1350 的图片
    @MainActor private func renderCard() -> UIImage? {
        let renderer = ImageRenderer(content: card)
        renderer.scale = 1080 / ShareCardView.size.width
        return renderer.uiImage
    }

    /// 分享文案：一句话 + 话题标签
    private var shareText: String {
        let line = L("share.text", spot.workTitle, spot.quotedSceneTitle)
        let tags = ShareFormatting.hashtags([L("share.hashtagPilgrimage"), "聖地巡礼", spot.work, spot.workLocalized])
        return line + "\n" + tags.joined(separator: " ")
    }
}

/// 让系统分享面板顶部显示分享卡缩略图和标题（而不是只显示文字）
/// 分享时把卡片写成 PNG 文件：系统分享面板会稳定显示缩略图，各家 App 也都能直接接收图片文件
final class ShareImageItem: NSObject, UIActivityItemSource {
    let image: UIImage
    let title: String
    private let fileURL: URL?

    init(image: UIImage, title: String) {
        self.image = image
        self.title = title
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("SeichiJunrei-Pilgrimage.png")
        if let data = image.pngData(), (try? data.write(to: url, options: .atomic)) != nil {
            fileURL = url
        } else {
            fileURL = nil
        }
    }

    func activityViewControllerPlaceholderItem(_ controller: UIActivityViewController) -> Any { image }

    func activityViewController(_ controller: UIActivityViewController,
                                itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
        fileURL ?? image
    }

    func activityViewControllerLinkMetadata(_ controller: UIActivityViewController) -> LPLinkMetadata? {
        let metadata = LPLinkMetadata()
        metadata.title = title
        if let fileURL { metadata.originalURL = fileURL; metadata.url = fileURL }
        let provider = NSItemProvider(object: image)
        metadata.imageProvider = provider
        metadata.iconProvider = provider
        return metadata
    }
}

/// 系统分享面板（同时分享图片和文字，兼容 X、LINE、微信、Instagram 等）
struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
