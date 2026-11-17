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
    @Environment(PilgrimageStore.self) private var pilgrimage
    @State private var showShare = false
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
                    Text(spot.displayWorkLocalized)
                        .font(.subheadline.bold())
                        .foregroundStyle(spot.tintColor)
                    Text(spot.sceneTitle).font(.title.bold())
                    ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 6) {
                        Tag(text: spot.mediaType.label, systemImage: spot.mediaType.symbolName)
                        if let ep = spot.episode { Tag(text: ep, systemImage: "play.rectangle") }
                        Tag(text: spot.placeName, systemImage: "mappin.and.ellipse")
                    } }
                }

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

                Button(action: onEnterScene) {
                    Label(arrived ? L("detail.enterScene") : L("detail.startGuide"),
                          systemImage: arrived ? "camera.viewfinder" : "location.north.circle")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 34)
                }
                // 页面的主要操作：带主题色的玻璃按钮
                .glassButton(prominent: true, tint: spot.tintColor)
                .controlSize(.large)
                .accessibilityIdentifier("enterScene")

                Section {
                    Text(spot.story).font(.body).lineSpacing(5)
                } header: {
                    SectionHeader(title: L("detail.story"), systemImage: "book")
                }

                if let trivia = spot.trivia {
                    Section {
                        Text(trivia).font(.callout).foregroundStyle(.secondary)
                    } header: {
                        SectionHeader(title: L("detail.tips"), systemImage: "lightbulb")
                    }
                }

                Button {
                    let item = MKMapItem(placemark: MKPlacemark(coordinate: spot.clCoordinate))
                    item.name = spot.placeName
                    item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
                } label: {
                    Label(L("detail.openMaps"), systemImage: "figure.walk")
                        .frame(maxWidth: .infinity)
                }
                .glassButton()

                if !spot.verified {
                    Label(L("detail.unverified"), systemImage: "info.circle")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
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

private struct SectionHeader: View {
    let title: String
    let systemImage: String
    var body: some View {
        Label(title, systemImage: systemImage).font(.headline).padding(.top, 4)
    }
}
