import SwiftUI
import UIKit
import MapKit
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
            } else if useLocationPhoto, let photo = spot.photo, photo.url.hasPrefix("file:"), let url = URL(string: photo.url) {
                // 用户投稿的名场面：照片已缓存在本机
                LocalImage(url: url)
            } else if useLocationPhoto, let photo = spot.photo, let url = URL(string: photo.url) {
                AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.25))) { phase in
                    switch phase {
                    case .success(let image): image.resizable().scaledToFill()
                    default: placeholder
                    }
                }
            } else if useLocationPhoto {
                // 没有实景照片时用卫星实景缩略图，不让卡片空着
                MapSnapshotImage(spot: spot) { placeholder }
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

/// 作品类型图标：日漫 / 日剧 / 日影各用一个通用图标和颜色，一眼区分类别
struct CategoryIcon: View {
    let category: MediaCategory
    var size: CGFloat = 36

    var body: some View {
        Image(systemName: category.symbolName)
            .font(.system(size: size * 0.46, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(category.color.gradient, in: RoundedRectangle(cornerRadius: size * 0.26, style: .continuous))
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

// MARK: - 没有实景照片时的兜底：Apple 街景 / 卫星实景

/// 详情页顶部的大图：自己的截图 → 实景照片 → Apple 街景（Look Around，可拖动环顾）→ 3D 卫星实景
struct SpotHeroImage: View {
    let spot: Spot
    @State private var lookAround: MKLookAroundScene?
    @State private var checkedLookAround = false

    private enum Source { case screenshot, photo, community, lookAround, satellite }

    /// 巡礼者上传的照片（没有自由许可的实景照片时用第一张）
    private var communityPhoto: CommunityPhoto? { CommunityService.shared.photosBySpot[spot.id]?.first }

    private var source: Source {
        if SceneImageStore.shared.hasImage(for: spot.id) { return .screenshot }
        if spot.photo != nil { return .photo }
        if communityPhoto != nil { return .community }
        return lookAround != nil ? .lookAround : .satellite
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // 先用一个固定大小的容器占位，再把图片铺在上面：
            // 直接对 scaledToFill 的图片设高度，特别宽的照片会把整页撑宽（内容左右被切掉）
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: 240)
                .overlay {
                    switch source {
                    case .screenshot, .photo:
                        SceneArtwork(spot: spot, useLocationPhoto: true)
                    case .community:
                        if let p = communityPhoto { LocalImage(url: p.imageURL) }
                    case .lookAround:
                        LookAroundPreview(initialScene: lookAround, allowsNavigation: true, badgePosition: .bottomTrailing)
                    case .satellite:
                        SatelliteSceneView(spot: spot)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(alignment: .topLeading) {
                if let label = badgeLabel {
                    Label(label.0, systemImage: label.1)
                        .font(.caption2.bold())
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .glassSurface(Capsule())
                        .padding(10)
                        .allowsHitTesting(false)
                }
            }
            if source == .photo, let photo = spot.photo { PhotoCredit(photo: photo) }
        }
        .task(id: spot.id) {
            guard spot.photo == nil, !checkedLookAround else { return }
            checkedLookAround = true
            lookAround = try? await MKLookAroundSceneRequest(coordinate: spot.clCoordinate).scene
        }
    }

    private var badgeLabel: (String, String)? {
        switch source {
        case .screenshot: return nil
        case .photo: return spot.isCommunity ? (L("community.badge"), "person.2.fill") : (L("photo.realPlace"), "photo")
        case .community: return (L("community.badge"), "person.2.fill")
        case .lookAround: return (L("photo.lookAround"), "binoculars.fill")
        case .satellite: return (L("photo.satellite"), "globe.asia.australia.fill")
        }
    }
}

/// 3D 卫星实景：从机位朝镜头方向看过去
private struct SatelliteSceneView: View {
    let spot: Spot
    var body: some View {
        Map(initialPosition: .camera(MapCamera(centerCoordinate: spot.clCoordinate, distance: 420,
                                               heading: spot.sceneHeading, pitch: 55)),
            interactionModes: [.pan, .zoom, .rotate, .pitch]) {
            Marker(spot.sceneTitle, systemImage: "camera.fill", coordinate: spot.clCoordinate)
                .tint(spot.tintColor)
        }
        .mapStyle(.imagery(elevation: .realistic))
    }
}

/// 卡片 / 列表用的卫星实景缩略图（MKMapSnapshotter，结果缓存在内存里）
struct MapSnapshotImage<Placeholder: View>: View {
    let spot: Spot
    @ViewBuilder let placeholder: () -> Placeholder
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                placeholder()
            }
        }
        .task(id: spot.id) { image = await MapSnapshotCache.shared.image(for: spot) }
    }
}

@MainActor
final class MapSnapshotCache {
    static let shared = MapSnapshotCache()
    private var cache: [String: UIImage] = [:]

    func image(for spot: Spot) async -> UIImage? {
        if let hit = cache[spot.id] { return hit }
        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(center: spot.clCoordinate, latitudinalMeters: 260, longitudinalMeters: 260)
        options.size = CGSize(width: 240, height: 240)
        options.preferredConfiguration = MKHybridMapConfiguration(elevationStyle: .flat)
        guard let snapshot = try? await MKMapSnapshotter(options: options).start() else { return nil }
        let image = snapshot.image
        cache[spot.id] = image
        return image
    }
}
