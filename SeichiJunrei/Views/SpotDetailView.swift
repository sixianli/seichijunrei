import SwiftUI
import MapKit
import PhotosUI
import SeichiCore

struct SpotDetailView: View {
    let spot: Spot
    let onEnterScene: () -> Void

    @Environment(SpotStore.self) private var store
    @Environment(LocationService.self) private var location
    @Environment(\.openURL) private var openURL
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var imageMessage: String?

    private var info: NearbySpot? { store.nearbyInfo(for: spot) }
    private var arrived: Bool { info?.hasArrived(accuracy: location.lastLocation?.horizontalAccuracy ?? 0) ?? false }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SceneArtwork(spot: spot)
                    .frame(height: 220)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 18))

                sceneImageControls

                VStack(alignment: .leading, spacing: 6) {
                    Text(spot.displayWork)
                        .font(.subheadline.bold())
                        .foregroundStyle(spot.tintColor)
                    Text(spot.sceneTitle).font(.title.bold())
                    ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 6) {
                        Tag(text: spot.mediaType.label, systemImage: spot.mediaType.symbolName)
                        if let ep = spot.episode { Tag(text: ep, systemImage: "play.rectangle") }
                        Tag(text: spot.placeName, systemImage: "mappin.and.ellipse")
                    } }
                }

                if let info {
                    HStack {
                        Image(systemName: "location.north.fill")
                            .rotationEffect(.degrees(info.bearing))
                        Text("距离 \(NearbySearch.formatDistance(info.distance)) · 在你的\(GeoMath.compassName(info.bearing))方")
                    }
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                }

                Button(action: onEnterScene) {
                    Label(arrived ? "进入名场面！" : "开启方向指引",
                          systemImage: arrived ? "camera.viewfinder" : "location.north.circle")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(spot.tintColor.gradient, in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(.white)
                }

                Section {
                    Text(spot.story).font(.body).lineSpacing(5)
                } header: {
                    SectionHeader(title: "剧情背景", systemImage: "book")
                }

                if let trivia = spot.trivia {
                    Section {
                        Text(trivia).font(.callout).foregroundStyle(.secondary)
                    } header: {
                        SectionHeader(title: "巡礼小贴士", systemImage: "lightbulb")
                    }
                }

                Button {
                    let item = MKMapItem(placemark: MKPlacemark(coordinate: spot.clCoordinate))
                    item.name = spot.placeName
                    item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
                } label: {
                    Label("在地图 App 中导航", systemImage: "figure.walk")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                if !spot.verified {
                    Label("该地点的机位坐标与朝向为参考值，尚未经过实地校准。", systemImage: "info.circle")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                #if DEBUG
                Button("（调试）模拟站在这个机位") {
                    location.simulate(at: spot.coordinate)
                }
                .font(.caption)
                #endif
            }
            .padding()
        }
    }
}

private extension SpotDetailView {
    /// 名场面画面：从自己的相册选一张截图（仅保存在本机），或去网上搜索这一幕。
    var sceneImageControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                PhotosPicker(selection: $pickedPhoto, matching: .images) {
                    Label(SceneImageStore.shared.hasImage(for: spot.id) ? "更换名场面截图" : "添加名场面截图",
                          systemImage: "photo.badge.plus")
                }
                if SceneImageStore.shared.hasImage(for: spot.id) {
                    Button(role: .destructive) {
                        SceneImageStore.shared.delete(for: spot.id)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .accessibilityLabel("删除名场面截图")
                }
                Spacer()
                Button {
                    if let url = imageSearchURL { openURL(url) }
                } label: {
                    Label("网上搜这一幕", systemImage: "magnifyingglass")
                }
            }
            .font(.footnote.weight(.semibold))
            .buttonStyle(.bordered)

            Text(imageMessage ?? "截图只保存在你的手机上，到达机位后会叠加在相机画面中，帮你对准同一个构图。")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .onChange(of: pickedPhoto) { _, item in
            guard let item else { return }
            Task {
                let data = try? await item.loadTransferable(type: Data.self)
                await MainActor.run {
                    if let data, SceneImageStore.shared.save(data, for: spot.id) {
                        imageMessage = "已设置名场面截图 ✓"
                    } else {
                        imageMessage = "图片读取失败，请换一张试试"
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
            URLQueryItem(name: "q", value: "\(spot.work) \(spot.placeName.components(separatedBy: "（").first ?? spot.placeName) 聖地巡礼"),
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

private struct SectionHeader: View {
    let title: String
    let systemImage: String
    var body: some View {
        Label(title, systemImage: systemImage).font(.headline).padding(.top, 4)
    }
}
