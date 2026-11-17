import SwiftUI
import PhotosUI
import SeichiCore

struct SpotDetailView: View {
    let spot: Spot
    let onEnterScene: () -> Void
    /// 帮拍模式（请别人帮忙拍）
    var onPhotographer: () -> Void = {}

    @Environment(SpotStore.self) private var store
    @Environment(LocationService.self) private var location
    @Environment(\.openURL) private var openURL
    @Environment(PilgrimageStore.self) private var pilgrimage
    @State private var showShare = false
    @State private var showCalibration = false
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var imageMessage: String?

    private var info: NearbySpot? { store.nearbyInfo(for: spot) }
    private var arrived: Bool { info?.hasArrived(accuracy: location.lastLocation?.horizontalAccuracy ?? 0) ?? false }

    @State private var revealSpoiler = false

    private var showsLocationPhoto: Bool {
        spot.photo != nil && !SceneImageStore.shared.hasImage(for: spot.id)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    SceneArtwork(spot: spot, useLocationPhoto: true)
                        .frame(height: 220)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .overlay(alignment: .topLeading) {
                            if showsLocationPhoto {
                                Label(L("photo.realPlace"), systemImage: "photo")
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .glassSurface(Capsule())
                                    .padding(10)
                            }
                        }
                    if showsLocationPhoto, let photo = spot.photo { PhotoCredit(photo: photo) }
                    sceneImageControls
                }

                header

                if let record = pilgrimage.record(for: spot.id) {
                    HStack {
                        Label(L("detail.completedOn", record.date.formatted(date: .abbreviated, time: .omitted)),
                              systemImage: "checkmark.seal.fill")
                            .font(.subheadline.bold())
                            .foregroundStyle(spot.tintColor)
                        Spacer()
                        Button { showShare = true } label: {
                            Label(L("share.share"), systemImage: "square.and.arrow.up")
                        }
                        .glassButton(prominent: true, tint: spot.tintColor)
                        .accessibilityIdentifier("detailShare")
                    }
                    .padding(12)
                    .background(spot.tintColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }

                VStack(spacing: 10) {
                    Button(action: onEnterScene) {
                        Label(arrived ? L("detail.enterScene") : L("detail.startGuide"),
                              systemImage: arrived ? "camera.viewfinder" : "figure.walk.motion")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 34)
                    }
                    // 页面的主要操作：带主题色的玻璃按钮
                    .glassButton(prominent: true, tint: spot.tintColor)
                    .controlSize(.large)
                    .accessibilityIdentifier("enterScene")

                    Button(action: onPhotographer) {
                        Label(L("detail.photographer"), systemImage: "person.2.crop.square.stack")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 30)
                    }
                    .glassButton(tint: spot.tintColor)
                    .accessibilityIdentifier("openPhotographer")

                    HStack(spacing: 10) {
                        DirectionsButton(spot: spot)
                            .glassButton()
                        // 现场的用户帮忙校准机位（坐标偏差大时，用户可能永远触发不了“到达”，所以详情页也要有入口）
                        Button { showCalibration = true } label: {
                            Label(L("calib.entry"), systemImage: "scope")
                                .frame(maxWidth: .infinity)
                        }
                        .glassButton(tint: spot.tintColor)
                        .accessibilityIdentifier("detailCalibrate")
                    }
                    .font(.subheadline.weight(.semibold))
                }

                if let highlight = spot.highlight {
                    DetailSection(title: L("detail.highlight"), systemImage: "sparkles", tint: spot.tintColor) {
                        Text(highlight).font(.body.weight(.medium)).lineSpacing(4)
                    }
                }

                DetailSection(title: L("detail.story"), systemImage: "book", tint: spot.tintColor) {
                    storyText
                }

                DetailSection(title: L("detail.guide"), systemImage: "map", tint: spot.tintColor) {
                    VStack(alignment: .leading, spacing: 12) {
                        if let access = spot.access {
                            InfoRow(title: L("detail.access"), text: access, systemImage: "tram.fill")
                        }
                        if let best = spot.bestTime {
                            InfoRow(title: L("detail.bestTime"), text: best, systemImage: "sun.horizon.fill")
                        }
                        InfoRow(title: L("detail.shot"), text: shotDescription, systemImage: "camera.metering.center.weighted")
                        if let tips = spot.trivia {
                            InfoRow(title: L("detail.tips"), text: tips, systemImage: "exclamationmark.bubble.fill")
                        }
                    }
                }

                aboutWork

                if !spot.verified {
                    Label(L("detail.unverified"), systemImage: "info.circle")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                #if DEBUG
                Button(L("detail.debugSimulate")) {
                    location.simulate(at: spot.coordinate)
                }
                .font(.caption)
                .accessibilityIdentifier("debugSimulate")
                #endif
            }
            .padding()
        }
        .sheet(isPresented: $showShare) { ShareComposerView(spot: spot) }
        .sheet(isPresented: $showCalibration) { CalibrationView(spot: spot) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(spot.workBadge)
                .font(.subheadline.bold())
                .foregroundStyle(spot.tintColor)
            if let original = spot.originalWorkName {
                Text(original).font(.caption).foregroundStyle(.secondary)
            }
            Text(spot.sceneTitle).font(.title.bold())
            ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 6) {
                if let ep = spot.episode { Tag(text: ep, systemImage: "play.rectangle") }
                Tag(text: spot.placeName, systemImage: "mappin.and.ellipse")
            } }
            if arrived {
                Label(L("detail.atSpot"), systemImage: "figure.stand")
                    .font(.callout.bold())
                    .foregroundStyle(spot.tintColor)
            } else if let info, info.distance.isFinite {
                HStack {
                    Image(systemName: "location.north.fill")
                        .rotationEffect(.degrees(info.bearing))
                    Text(L("detail.distance", NearbySearch.formatDistance(info.distance), Compass.name(info.bearing)))
                }
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
            }
        }
    }

    /// 含剧透的剧情默认打码，用户主动点开
    @ViewBuilder private var storyText: some View {
        if spot.spoiler && !revealSpoiler {
            VStack(alignment: .leading, spacing: 10) {
                Text(spot.story)
                    .font(.body).lineSpacing(5)
                    .lineLimit(4)
                    .blur(radius: 7)
                    .accessibilityHidden(true)
                Button {
                    withAnimation(.easeOut) { revealSpoiler = true }
                } label: {
                    Label(L("detail.revealSpoiler"), systemImage: "eye")
                        .font(.subheadline.weight(.semibold))
                }
                .glassButton(tint: spot.tintColor)
                .accessibilityIdentifier("revealSpoiler")
            }
        } else {
            Text(spot.story).font(.body).lineSpacing(5)
        }
    }

    /// 机位说明：朝哪个方向、抬头还是低头
    private var shotDescription: String {
        let dir = Compass.name(spot.sceneHeading)
        guard let pitch = spot.scenePitch, abs(pitch) >= 5 else { return L("detail.shotLevel", dir) }
        return pitch > 0 ? L("detail.shotUp", dir, Int(pitch.rounded())) : L("detail.shotDown", dir, Int((-pitch).rounded()))
    }

    @ViewBuilder private var aboutWork: some View {
        DetailSection(title: L("detail.aboutWork"), systemImage: spot.mediaType.category.symbolName, tint: spot.tintColor) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    WorkCover(spot: spot, size: 46)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(spot.workName).font(.headline)
                        if let original = spot.originalWorkName {
                            Text(original).font(.subheadline).foregroundStyle(.secondary)
                        }
                        Text([spot.mediaType.label, spot.year.map(String.init), spot.creator]
                                .compactMap { $0 }.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if let synopsis = spot.synopsis {
                    Text(synopsis).font(.callout).foregroundStyle(.secondary).lineSpacing(3)
                }
                if let site = spot.officialURL, let url = URL(string: site) {
                    Link(destination: url) {
                        Label(L("detail.officialSite"), systemImage: "safari")
                            .font(.footnote.weight(.semibold))
                    }
                }
            }
        }
    }
}

private extension SpotDetailView {
    /// 名场面画面：从自己的相册选一张截图（仅保存在本机），或去网上搜索这一幕。
    var sceneImageControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                PhotosPicker(selection: $pickedPhoto, matching: .images) {
                    Label(SceneImageStore.shared.hasImage(for: spot.id) ? L("detail.changeImage") : L("detail.addImage"),
                          systemImage: "photo.badge.plus")
                }
                if SceneImageStore.shared.hasImage(for: spot.id) {
                    Button(role: .destructive) {
                        SceneImageStore.shared.delete(for: spot.id)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .accessibilityLabel(L("detail.deleteImage"))
                }
                Spacer()
                Button {
                    if let url = imageSearchURL { openURL(url) }
                } label: {
                    Label(L("detail.searchWeb"), systemImage: "magnifyingglass")
                }
            }
            .font(.footnote.weight(.semibold))
            .glassButton()

            Text(imageMessage ?? L("detail.imageHint"))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .onChange(of: pickedPhoto) { _, item in
            guard let item else { return }
            Task {
                let data = try? await item.loadTransferable(type: Data.self)
                await MainActor.run {
                    if let data, SceneImageStore.shared.save(data, for: spot.id) {
                        imageMessage = L("detail.imageSet")
                    } else {
                        imageMessage = L("detail.imageFailed")
                    }
                    pickedPhoto = nil
                }
            }
        }
    }

    var imageSearchURL: URL? {
        var c = URLComponents(string: "https://www.google.com/search")
        c?.queryItems = [
            URLQueryItem(name: "tbm", value: "isch"),
            // 用作品原名 + 地点名 + “聖地巡礼” 搜索，日文资料最丰富
            URLQueryItem(name: "q", value: "\(spot.work) \(spot.placeName.components(separatedBy: CharacterSet(charactersIn: "（(")).first ?? spot.placeName) 聖地巡礼"),
        ]
        return c?.url
    }
}

private struct Tag: View {
    let text: String
    let systemImage: String
    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption)
            .lineLimit(1)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(.quaternary, in: Capsule())
    }
}

private struct DetailSection<Content: View>: View {
    let title: String
    let systemImage: String
    let tint: Color
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(.primary)
                .labelStyle(TintedIconLabelStyle(tint: tint))
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct TintedIconLabelStyle: LabelStyle {
    let tint: Color
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon.foregroundStyle(tint)
            configuration.title
        }
    }
}

private struct InfoRow: View {
    let title: String
    let text: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: systemImage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text(text).font(.callout).fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
