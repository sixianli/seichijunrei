import SwiftUI
import UIKit
import SeichiCore

/// 名场面画面。优先级：用户自己选的截图 → （可选）真实地点照片 → 有授权的 sceneImage → 插画风占位图。
/// 请勿打包未经授权的动画截图 / 剧照 / 海报。
struct SceneArtwork: View {
    let spot: Spot
    var compact = false
    /// 没有名场面截图时，是否用真实地点的照片（Wikimedia Commons，需要另外显示署名）。
    /// 相机对位、分享卡片里的“名场面”一侧不能用实景照片冒充画面，所以默认关闭。
    var useLocationPhoto = false

    var body: some View {
        Group {
            if let userImage = SceneImageStore.shared.image(for: spot.id) {
                Image(uiImage: userImage).resizable().scaledToFill()
            } else if useLocationPhoto, let photo = spot.photo, let url = URL(string: photo.url) {
                AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.25))) { phase in
                    switch phase {
                    case .success(let image): image.resizable().scaledToFill()
                    default: placeholder
                    }
                }
            } else if let src = spot.sceneImage, src.hasPrefix("http"), let url = URL(string: src) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image): image.resizable().scaledToFill()
                    default: placeholder
                    }
                }
            } else if let name = spot.sceneImage, UIImage(named: name) != nil {
                Image(name).resizable().scaledToFill()
            } else {
                placeholder
            }
        }
        .clipped()
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(colors: [spot.tintColor.opacity(0.95), spot.tintColor.opacity(0.45), .black.opacity(0.85)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            // 胶片齿孔装饰
            VStack {
                filmStrip
                Spacer()
                filmStrip
            }
            VStack(spacing: compact ? 4 : 10) {
                Image(systemName: "film.stack")
                    .font(compact ? .title3 : .system(size: 44, weight: .light))
                Text(spot.sceneTitle)
                    .font(compact ? .caption.bold() : .title2.bold())
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                if !compact {
                    Text(spot.work).font(.subheadline).opacity(0.85)
                }
            }
            .foregroundStyle(.white)
            .padding()
        }
    }

    private var filmStrip: some View {
        HStack(spacing: compact ? 6 : 10) {
            ForEach(0..<14, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(.white.opacity(0.25))
                    .frame(width: compact ? 5 : 9, height: compact ? 4 : 7)
            }
        }
        .padding(.vertical, compact ? 4 : 8)
    }
}

/// 作品“封面”：用作品主题色 + 作品名首字生成，不使用受版权保护的海报 / 封面图。
struct WorkCover: View {
    let spot: Spot
    var size: CGFloat = 44

    private var glyph: String {
        let name = spot.workName.trimmingCharacters(in: .whitespaces)
        return name.first.map { String($0).uppercased() } ?? "?"
    }

    var body: some View {
        ZStack {
            Color.black
            LinearGradient(colors: [spot.tintColor, spot.tintColor.opacity(0.55)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Text(glyph)
                .font(.system(size: size * 0.5, weight: .heavy, design: .serif))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.5)
                .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
            Image(systemName: spot.mediaType.category.symbolName)
                .font(.system(size: size * 0.2, weight: .bold))
                .foregroundStyle(.white.opacity(0.85))
                .padding(size * 0.08)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
        .frame(width: size, height: size * 1.3)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: size * 0.16, style: .continuous).stroke(.white.opacity(0.2), lineWidth: 0.5))
        .accessibilityHidden(true)
    }
}

/// 实景照片的署名（CC 许可证要求注明作者、许可证并附链接）
struct PhotoCredit: View {
    let photo: SpotPhoto
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            if let s = photo.pageURL ?? photo.licenseURL, let url = URL(string: s) { openURL(url) }
        } label: {
            Label(L("photo.credit", photo.author, photo.license), systemImage: "camera")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("photoCredit")
    }
}
