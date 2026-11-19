import SwiftUI
import PhotosUI
import SeichiCore

// MARK: - 我的巡礼相册

/// 首页右上角进入：在“带我去复现”“请人帮我拍”里拍的照片，按名场面分组
struct AlbumView: View {
    /// 点“去这个名场面”时调用
    var onOpenSpot: (Spot) -> Void = { _ in }
    @Environment(PilgrimageStore.self) private var pilgrimage
    @Environment(SpotStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var viewing: AlbumPhoto?

    private var groups: [(spot: Spot, photos: [AlbumPhoto])] {
        var order: [String] = []
        var byID: [String: [AlbumPhoto]] = [:]
        for p in pilgrimage.album {
            if byID[p.spotID] == nil { order.append(p.spotID) }
            byID[p.spotID, default: []].append(p)
        }
        return order.compactMap { id in
            guard let spot = store.spots.first(where: { $0.id == id }) else { return nil }
            return (spot, byID[id] ?? [])
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if groups.isEmpty {
                    ContentUnavailableView(L("album.emptyTitle"), systemImage: "photo.stack",
                                           description: Text(L("album.emptyBody")))
                        .padding(.top, 80)
                } else {
                    LazyVStack(alignment: .leading, spacing: 22) {
                        ForEach(groups, id: \.spot.id) { group in
                            VStack(alignment: .leading, spacing: 8) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(group.spot.badgeWithNumber).font(.caption.bold()).foregroundStyle(group.spot.tintColor)
                                    Text(group.spot.sceneTitle).font(.headline)
                                }
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 6)], spacing: 6) {
                                    ForEach(group.photos) { photo in
                                        Button { viewing = photo } label: {
                                            AlbumThumb(photo: photo)
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityIdentifier("albumPhoto")
                                    }
                                }
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle(L("album.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(L("common.done")) { dismiss() } }
            }
            .sheet(item: $viewing) { photo in
                if let spot = store.spots.first(where: { $0.id == photo.spotID }) {
                    AlbumPhotoViewer(photo: photo, spot: spot, onOpenSpot: {
                        viewing = nil
                        dismiss()
                        onOpenSpot(spot)
                    })
                }
            }
        }
    }
}

struct AlbumThumb: View {
    let photo: AlbumPhoto
    @Environment(PilgrimageStore.self) private var pilgrimage

    var body: some View {
        Color.clear
            .aspectRatio(0.8, contentMode: .fit)
            .overlay {
                if let img = pilgrimage.albumImage(photo) {
                    Image(uiImage: img).resizable().scaledToFill()
                } else {
                    Color.secondary.opacity(0.15)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(alignment: .bottomLeading) {
                if photo.kind == .photographer {
                    Image(systemName: "person.fill")
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .padding(5)
                        .background(.black.opacity(0.45), in: Circle())
                        .padding(5)
                }
            }
    }
}

/// 看一张自己拍的照片：分享、分享给其他巡礼者、去这个名场面、删除
struct AlbumPhotoViewer: View {
    let photo: AlbumPhoto
    let spot: Spot
    var onOpenSpot: (() -> Void)?
    @Environment(PilgrimageStore.self) private var pilgrimage
    @Environment(\.dismiss) private var dismiss
    @State private var showShareCard = false
    @State private var showUpload = false
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if let img = pilgrimage.albumImage(photo) {
                    Image(uiImage: img).resizable().scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                VStack(spacing: 2) {
                    Text(spot.badgeWithNumber + " " + spot.quotedSceneTitle).font(.subheadline.bold())
                    Text(photo.date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                }
                HStack(spacing: 10) {
                    if let img = pilgrimage.albumImage(photo) {
                        ShareLink(item: Image(uiImage: img),
                                  preview: SharePreview(spot.quotedSceneTitle, image: Image(uiImage: img))) {
                            Label(L("share.share"), systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity, minHeight: 30)
                        }
                        .glassButton(prominent: true, tint: spot.tintColor)
                        .accessibilityIdentifier("albumShare")
                    }
                    Button { showShareCard = true } label: {
                        Label(L("album.shareCard"), systemImage: "rectangle.portrait.on.rectangle.portrait")
                            .frame(maxWidth: .infinity, minHeight: 30)
                    }
                    .glassButton(tint: spot.tintColor)
                }
                .controlSize(.large)
                Button { showUpload = true } label: {
                    Label(L("community.shareToPilgrims"), systemImage: "person.2.fill")
                        .frame(maxWidth: .infinity, minHeight: 30)
                }
                .glassButton(tint: spot.tintColor)
                if let onOpenSpot {
                    Button(action: onOpenSpot) {
                        Label(L("album.openSpot"), systemImage: "mappin.and.ellipse").font(.footnote.weight(.semibold))
                    }
                    .foregroundStyle(spot.tintColor)
                }
            }
            .padding()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("common.close")) { dismiss() } }
                ToolbarItem(placement: .destructiveAction) {
                    Button(role: .destructive) { confirmDelete = true } label: { Image(systemName: "trash") }
                        .accessibilityLabel(L("album.delete"))
                }
            }
            .confirmationDialog(L("album.deleteConfirm"), isPresented: $confirmDelete, titleVisibility: .visible) {
                Button(L("album.delete"), role: .destructive) { pilgrimage.deleteFromAlbum(photo); dismiss() }
            }
            .sheet(isPresented: $showShareCard) { ShareComposerView(spot: spot) }
            .sheet(isPresented: $showUpload) {
                if let img = pilgrimage.albumImage(photo) {
                    UploadPhotoSheet(spot: spot, image: img, source: .inAppCapture(location: photo.location))
                }
            }
        }
    }
}

/// 详情页：我在这里拍的照片
struct MyPhotosSection: View {
    let spot: Spot
    @Environment(PilgrimageStore.self) private var pilgrimage
    @State private var viewing: AlbumPhoto?

    var body: some View {
        let photos = pilgrimage.albumPhotos(for: spot.id)
        if !photos.isEmpty {
            DetailSection(title: L("album.mine"), systemImage: "photo.stack.fill", tint: spot.tintColor) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(photos) { photo in
                            Button { viewing = photo } label: { AlbumThumb(photo: photo).frame(width: 96) }
                                .buttonStyle(.plain)
                        }
                    }
                }
            }
            .sheet(item: $viewing) { photo in AlbumPhotoViewer(photo: photo, spot: spot) }
        }
    }
}

// MARK: - 对位截图

/// 用户自己存的一张原作截图（只在本机）：相机对位、请人帮拍、分享对比时用
struct SceneScreenshotSection: View {
    let spot: Spot
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var message: String?
    @State private var version = 0

    var body: some View {
        let has = SceneImageStore.shared.hasImage(for: spot.id)
        DetailSection(title: L("detail.alignShot"), systemImage: "square.on.square.dashed", tint: spot.tintColor) {
            VStack(alignment: .leading, spacing: 10) {
                Text(L("detail.alignShotHint")).font(.callout).foregroundStyle(.secondary)
                if has, let img = SceneImageStore.shared.image(for: spot.id) {
                    Image(uiImage: img).resizable().scaledToFit()
                        .frame(maxHeight: 140)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .id(version)
                }
                HStack(spacing: 10) {
                    PhotosPicker(selection: $pickedPhoto, matching: .images) {
                        Label(has ? L("detail.changeImage") : L("detail.addImage"), systemImage: "photo.badge.plus")
                            .frame(maxWidth: .infinity, minHeight: 30)
                    }
                    .glassButton()
                    .accessibilityIdentifier("addSceneImage")
                    if has {
                        Button(role: .destructive) {
                            SceneImageStore.shared.delete(for: spot.id)
                            version += 1
                        } label: {
                            Image(systemName: "trash").frame(minWidth: 30, minHeight: 30)
                        }
                        .glassButton()
                        .accessibilityLabel(L("detail.deleteImage"))
                    }
                }
                .font(.subheadline.weight(.semibold))
                if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
            }
        }
        .onChange(of: pickedPhoto) { _, item in
            guard let item else { return }
            Task {
                let data = try? await item.loadTransferable(type: Data.self)
                await MainActor.run {
                    message = (data.map { SceneImageStore.shared.save($0, for: spot.id) } ?? false)
                        ? L("detail.imageSet") : L("detail.imageFailed")
                    version += 1
                    pickedPhoto = nil
                }
            }
        }
    }
}
