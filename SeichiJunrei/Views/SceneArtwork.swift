import SwiftUI
import UIKit
import MapKit
import ImageIO
import SeichiCore

/// 名场面画面。
/// - 封面 / 卡片（useLocationPhoto）：封面插画 → 真实地点照片 → 卫星图。用户自己存的原作截图不出现在这里。
/// - 相机对位 / 分享对比：用户自己存的原作截图 → 有授权的 sceneImage → 插画风占位图。
/// 请勿打包未经授权的动画截图 / 剧照 / 海报。
struct SceneArtwork: View {
    let spot: Spot
    var compact = false
    /// 没有名场面截图时，是否用真实地点的照片（Wikimedia Commons，需要另外显示署名）。
    /// 相机对位、分享卡片里的“名场面”一侧不能用实景照片冒充画面，所以默认关闭。
    var useLocationPhoto = false

    var body: some View {
        Group {
            if !useLocationPhoto, let userImage = SceneImageStore.shared.image(for: spot.id) {
                Image(uiImage: userImage).resizable().scaledToFill()
            } else if useLocationPhoto, let ill = spot.illustration,
                      let image = IllustrationImages.shared.image(ill.file, thumbnail: compact) {
                // 封面插画（据实景照片重绘的动画背景风格，随 App 打包）
                Image(uiImage: image).resizable().scaledToFill()
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
                // 小缩略图里放不下文字（会被截成半截），只留图标
                if !compact {
                    Text(spot.sceneTitle)
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
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

/// 打包的封面插画。卡片 / 列表用缩小解码的版本，省内存。
@MainActor
final class IllustrationImages {
    static let shared = IllustrationImages()
    private let cache = NSCache<NSString, UIImage>()

    func image(_ name: String, thumbnail: Bool) -> UIImage? {
        let key = "\(name)|\(thumbnail)" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        guard let url = Bundle.main.url(forResource: name, withExtension: "jpg") else { return nil }
        let image: UIImage?
        if thumbnail {
            guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, [
                      kCGImageSourceCreateThumbnailFromImageAlways: true,
                      kCGImageSourceThumbnailMaxPixelSize: 480,
                      kCGImageSourceCreateThumbnailWithTransform: true,
                  ] as CFDictionary) else { return nil }
            image = UIImage(cgImage: cg)
        } else {
            image = UIImage(contentsOfFile: url.path)
        }
        if let image { cache.setObject(image, forKey: key) }
        return image
    }
}

/// 插画的署名：据谁的照片绘制（CC 许可证要求注明作者、许可证；CC BY-SA 照片的改编插画同样按 CC BY-SA 提供）
struct IllustrationCredit: View {
    let illustration: SpotIllustration
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            if let p = illustration.basedOn, let s = p.pageURL ?? p.licenseURL, let url = URL(string: s) { openURL(url) }
        } label: {
            Label(text, systemImage: "paintbrush")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .buttonStyle(.plain)
        .disabled(illustration.basedOn == nil)
        .accessibilityIdentifier("illustrationCredit")
    }

    private var text: String {
        if let p = illustration.basedOn { return L("illustration.creditPhoto", p.author, p.license) }
        return L("illustration.creditOwn")
    }
}

// MARK: - 没有实景照片时的兜底：Apple 街景 / 卫星实景

/// 详情页顶部的大图：封面插画（可切换看实景照片）→ 实景照片 → 巡礼者照片 → Apple 街景（Look Around，可拖动环顾）→ 3D 卫星实景。
/// 右下角“看原作画面”：原作截图有版权不能收录，帮用户去网上搜。
struct SpotHeroImage: View {
    let spot: Spot
    @State private var lookAround: MKLookAroundScene?
    @State private var checkedLookAround = false
    /// 有插画时，用户点了“看实景”
    @State private var showingRealPhoto = false
    @State private var showSearch = false

    private enum Source { case illustration, photo, community, lookAround, satellite }
    @Environment(\.openURL) private var openURL
    @Environment(LocationService.self) private var location

    /// 插画和实景照片视角接近时才提供切换；差得多就只显示插画，免得对不上
    private var canToggle: Bool {
        spot.illustration?.showsRealPhoto == true && spot.photo != nil
    }

    /// 巡礼者上传的照片（没有自由许可的实景照片时用第一张）
    private var communityPhoto: CommunityPhoto? { CommunityService.shared.photosBySpot[spot.id]?.first }

    private var source: Source {
        if spot.illustration != nil, !(showingRealPhoto && canToggle) { return .illustration }
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
                    case .illustration:
                        SceneArtwork(spot: spot, useLocationPhoto: true)
                    case .photo where spot.illustration == nil:
                        SceneArtwork(spot: spot, useLocationPhoto: true)
                    case .photo:
                        // 有插画、用户点了“看实景”：直接显示目录里的实景照片
                        if let photo = spot.photo, let url = URL(string: photo.url) {
                            AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.25))) { phase in
                                if case .success(let image) = phase { image.resizable().scaledToFill() }
                                else { Color(.secondarySystemBackground).overlay(ProgressView()) }
                            }
                        }
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
            .overlay(alignment: .topTrailing) {
                if canToggle {
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) { showingRealPhoto.toggle() }
                    } label: {
                        Label(showingRealPhoto ? L("illustration.showArt") : L("illustration.showPhoto"),
                              systemImage: showingRealPhoto ? "paintbrush.fill" : "photo")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(.black.opacity(0.55), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(10)
                    .accessibilityIdentifier("heroToggle")
                }
            }
            // 封面下方：左边是图片来源（ⓘ 里说明原作画面为什么没收录），右边是“看原作画面”（不盖在图上）
            HStack(alignment: .center, spacing: 10) {
                HStack(spacing: 4) {
                    if source == .illustration, let ill = spot.illustration { IllustrationCredit(illustration: ill) }
                    if source == .photo, let photo = spot.photo { PhotoCredit(photo: photo) }
                    InfoButton(text: L("detail.originalNotIncluded"))
                }
                Spacer(minLength: 0)
                Button { showSearch = true } label: {
                    Label(L("detail.searchOriginal"), systemImage: "magnifyingglass")
                        .font(.footnote.bold())
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Color.accentColor.opacity(0.14), in: Capsule())
                        .foregroundStyle(Color.accentColor)
                        .fixedSize()
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("searchScene")
                .popover(isPresented: $showSearch) {
                    SceneSearchList(spot: spot, country: location.countryCode) { showSearch = false }
                        .presentationCompactAdaptation(.popover)
                }
            }
        }
        .task(id: spot.id) {
            guard spot.photo == nil, !checkedLookAround else { return }
            checkedLookAround = true
            lookAround = try? await MKLookAroundSceneRequest(coordinate: spot.clCoordinate).scene
        }
    }

    private var badgeLabel: (String, String)? {
        switch source {
        case .illustration: return (L("illustration.badge"), "sparkles")
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

/// “网上搜这一幕”：搜索引擎按用户所在国家（定位优先，没有定位用手机地区设置），
/// 搜索词用和搜索引擎匹配的一种语言：作品名 + 粉丝常用的地点 / 场景关键词 + 巡礼词，给出几条让用户挑
enum SceneSearchLink {
    @MainActor
    static func options(for spot: Spot, country: String?) -> [SceneImageSearch.Option] {
        let engine = SceneImageSearch.engine(country: country ?? Locale.current.region?.identifier)
        let searchLang = SceneImageSearch.language(for: engine, userLanguage: AppLanguage.current)
        // 用搜索引擎的语言去搜（结果多）；界面语言不同时，每条配上用户看得懂的说明
        return SceneImageSearch.options(search: words(spot, searchLang), display: words(spot, AppLanguage.current),
                                        engine: engine, liveAction: spot.mediaType.category != .anime)
    }

    private static func words(_ spot: Spot, _ lang: String) -> SceneImageSearch.Words {
        let s = spot.localized(to: lang)
        let work = lang == "ja" ? spot.work : (s.workLocalized ?? spot.work)
        return SceneImageSearch.Words(language: lang, work: work, terms: s.searchTerms, place: s.placeName)
    }

    static func url(_ option: SceneImageSearch.Option) -> URL? {
        SceneImageSearch.url(query: option.query, engine: option.engine)
    }
}

/// “看原作画面”弹出的几条搜索：大字是用户的语言，小字是实际去搜的词（比如日文）
struct SceneSearchList: View {
    let spot: Spot
    let country: String?
    var onPick: () -> Void
    @Environment(\.openURL) private var openURL

    var body: some View {
        let options = SceneSearchLink.options(for: spot, country: country)
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text(L("detail.searchOriginalTitle")).font(.headline)
                Text(L("detail.searchOriginalHint")).font(.footnote).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(options, id: \.query) { opt in
                    Button {
                        onPick()
                        if let url = SceneSearchLink.url(opt) { openURL(url) }
                    } label: {
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(opt.label ?? opt.query)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                if opt.label != nil {
                                    Text(opt.query).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                            Image(systemName: "arrow.up.right").font(.caption.bold()).foregroundStyle(Color.accentColor)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("searchOption")
                }
            }
            .padding()
        }
        .frame(idealWidth: 340, idealHeight: 440)
    }
}

/// 小小的 ⓘ：点开才显示说明，页面上不堆小字
struct InfoButton: View {
    let text: String
    @State private var showing = false

    var body: some View {
        Button { showing = true } label: {
            Image(systemName: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(minWidth: 28, minHeight: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L("common.moreInfo"))
        .popover(isPresented: $showing) {
            Text(text)
                .font(.callout)
                .padding()
                .frame(idealWidth: 280)
                .fixedSize(horizontal: false, vertical: true)
                .presentationCompactAdaptation(.popover)
        }
    }
}
