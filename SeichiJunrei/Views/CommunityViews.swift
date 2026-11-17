import SwiftUI
import PhotosUI
import MapKit
import SeichiCore

// MARK: - 详情页：巡礼者的照片

/// 详情页里的“巡礼者的照片”：浏览、上传、举报
struct CommunityPhotosSection: View {
    let spot: Spot
    @State private var community = CommunityService.shared
    @State private var picked: PhotosPickerItem?
    @State private var uploadItem: IdentifiedImage?
    @State private var viewing: CommunityPhoto?

    private var photos: [CommunityPhoto] { community.photosBySpot[spot.id] ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if photos.isEmpty {
                Text(L("community.empty")).font(.callout).foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(photos) { photo in
                            Button { viewing = photo } label: {
                                LocalImage(url: photo.imageURL)
                                    .frame(width: 120, height: 150)
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(photo.caption.isEmpty ? L("community.photo") : photo.caption)
                            .accessibilityIdentifier("communityPhoto")
                        }
                    }
                }
            }
            PhotosPicker(selection: $picked, matching: .images) {
                Label(L("community.upload"), systemImage: "camera.badge.ellipsis")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 30)
            }
            .glassButton(tint: spot.tintColor)
            .accessibilityIdentifier("uploadCommunityPhoto")
        }
        .task(id: spot.id) { await community.loadPhotos(spotID: spot.id) }
        .onChange(of: picked) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    await MainActor.run { uploadItem = IdentifiedImage(image: image) }
                }
                await MainActor.run { picked = nil }
            }
        }
        .sheet(item: $uploadItem) { item in
            UploadPhotoSheet(spot: spot, image: item.image)
        }
        .sheet(item: $viewing) { photo in
            CommunityPhotoViewer(photo: photo)
        }
    }
}

struct IdentifiedImage: Identifiable {
    let id = UUID()
    let image: UIImage
}

/// 读取本机缓存的图片文件
struct LocalImage: View {
    let url: URL
    var contentMode: ContentMode = .fill
    var body: some View {
        if let image = UIImage(contentsOfFile: url.path) {
            Image(uiImage: image).resizable().aspectRatio(contentMode: contentMode)
        } else {
            Color.secondary.opacity(0.15)
        }
    }
}

/// 上传前确认：写一句话、确认是本人拍摄的现场照片
struct UploadPhotoSheet: View {
    let spot: Spot
    let image: UIImage
    @Environment(\.dismiss) private var dismiss
    @State private var caption = ""
    @State private var ownPhoto = false
    @State private var uploading = false
    @State private var message: String?

    private var captionProblems: [ContentFilter.Problem] {
        ContentFilter.problems(in: caption, required: false, maxLength: 200)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Image(uiImage: image)
                        .resizable().scaledToFit()
                        .frame(maxHeight: 320)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    Text(spot.badgeWithNumber + " " + spot.quotedSceneTitle).font(.subheadline.bold())
                    TextField(L("community.captionPlaceholder"), text: $caption, axis: .vertical)
                        .lineLimit(1...4)
                        .padding(12)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .accessibilityIdentifier("communityCaption")
                    if let p = captionProblems.first { FilterProblemText(problem: p) }
                    Toggle(isOn: $ownPhoto) {
                        Text(L("community.ownPhoto")).font(.subheadline)
                    }
                    .accessibilityIdentifier("communityOwnPhoto")
                    Text(L("community.rules")).font(.caption).foregroundStyle(.secondary)
                    if let message {
                        Text(message).font(.callout.bold()).foregroundStyle(.orange)
                    }
                    Button {
                        uploading = true
                        Task {
                            let result = await CommunityService.shared.uploadPhoto(image, spotID: spot.id, caption: caption)
                            uploading = false
                            switch result {
                            case .success: dismiss()
                            case .failure(let f): message = CommunityText.failure(f)
                            }
                        }
                    } label: {
                        HStack {
                            if uploading { ProgressView() }
                            Text(L("community.uploadConfirm")).font(.headline)
                        }
                        .frame(maxWidth: .infinity, minHeight: 34)
                    }
                    .glassButton(prominent: true, tint: spot.tintColor)
                    .controlSize(.large)
                    .disabled(!ownPhoto || !captionProblems.isEmpty || uploading)
                    .accessibilityIdentifier("communityUploadConfirm")
                }
                .padding()
            }
            .navigationTitle(L("community.uploadTitle"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("common.cancel")) { dismiss() } }
            }
        }
    }
}

/// 查看一张巡礼者照片：举报 / 屏蔽作者 / 删除自己的
struct CommunityPhotoViewer: View {
    let photo: CommunityPhoto
    @Environment(\.dismiss) private var dismiss
    @State private var reporting = false
    @State private var confirmBlock = false
    @State private var notice: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                LocalImage(url: photo.imageURL, contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                if !photo.caption.isEmpty {
                    Text(photo.caption).font(.body).frame(maxWidth: .infinity, alignment: .leading)
                }
                Text(L("community.postedOn", photo.date.formatted(date: .abbreviated, time: .omitted)))
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let notice {
                    Label(notice, systemImage: "checkmark.circle.fill").font(.callout.bold()).foregroundStyle(.green)
                        .accessibilityIdentifier("communityNotice")
                }
            }
            .padding()
            .navigationTitle(L("community.photo"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(L("common.done")) { dismiss() } }
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        if photo.isMine {
                            Button(L("community.delete"), systemImage: "trash", role: .destructive) {
                                Task {
                                    _ = await CommunityService.shared.delete(photo)
                                    dismiss()
                                }
                            }
                        } else {
                            Button(L("community.report"), systemImage: "exclamationmark.bubble") { reporting = true }
                            if photo.authorID != nil {
                                Button(L("community.block"), systemImage: "hand.raised", role: .destructive) { confirmBlock = true }
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel(L("community.more"))
                    .accessibilityIdentifier("communityMore")
                }
            }
            .confirmationDialog(L("community.reportTitle"), isPresented: $reporting, titleVisibility: .visible) {
                ForEach(CommunityText.reportReasons, id: \.self) { key in
                    Button(L(key)) { report(reason: key) }
                }
                Button(L("common.cancel"), role: .cancel) {}
            }
            .confirmationDialog(L("community.blockTitle"), isPresented: $confirmBlock, titleVisibility: .visible) {
                Button(L("community.block"), role: .destructive) {
                    if let id = photo.authorID { CommunityService.shared.block(userID: id) }
                    dismiss()
                }
                Button(L("common.cancel"), role: .cancel) {}
            } message: {
                Text(L("community.blockMessage"))
            }
        }
    }

    private func report(reason: String) {
        Task {
            let result = await CommunityService.shared.report(targetType: "photo", targetID: photo.id, reason: reason)
            switch result {
            case .success: notice = L("community.reported")
            case .failure(let f): notice = CommunityText.failure(f)
            }
        }
    }
}

enum CommunityText {
    static let reportReasons = ["community.reason.inappropriate", "community.reason.unrelated",
                                "community.reason.copyright", "community.reason.spam"]

    static func failure(_ f: CommunityService.Failure) -> String {
        switch f {
        case .noAccount: return L("community.error.noAccount")
        case .network: return L("community.error.network")
        case .rejected: return L("community.error.rejected")
        case .other(let m): return L("community.error.other", m)
        }
    }
}

struct FilterProblemText: View {
    let problem: ContentFilter.Problem
    var body: some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .font(.footnote)
            .foregroundStyle(.orange)
    }
    private var text: String {
        switch problem {
        case .empty: return L("filter.empty")
        case .tooLong(let max): return L("filter.tooLong", max)
        case .link: return L("filter.link")
        case .contact: return L("filter.contact")
        case .offensive: return L("filter.offensive")
        }
    }
}

// MARK: - 投稿新名场面

/// 投稿一个还没有收录的名场面。先审后发：审核通过后所有人可见。
struct SubmitSceneView: View {
    @Environment(LocationService.self) private var location
    @Environment(\.dismiss) private var dismiss
    @State private var orientation = OrientationService()
    @State private var draft = SceneDraft()
    @State private var useCurrentLocation = true
    @State private var pinned: CLLocationCoordinate2D?
    @State private var manualHeading: Double = 0
    @State private var picked: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var agreed = false
    @State private var submitting = false
    @State private var done = false
    @State private var message: String?
    @State private var camera: MapCameraPosition = .userLocation(fallback: .automatic)

    private var problems: [SceneDraft.Field: [ContentFilter.Problem]] { currentDraft.problems() }

    /// 根据“用当前位置 / 在地图上选”填好坐标和朝向
    private var currentDraft: SceneDraft {
        var d = draft
        if useCurrentLocation, let loc = location.lastLocation {
            d.latitude = loc.coordinate.latitude
            d.longitude = loc.coordinate.longitude
            d.heading = orientation.heading
            d.pitch = orientation.pitch
        } else if let p = pinned {
            d.latitude = p.latitude
            d.longitude = p.longitude
            d.heading = manualHeading
            d.pitch = nil
        } else {
            d.latitude = nil
            d.longitude = nil
        }
        d.hasPhoto = image != nil
        return d
    }

    var body: some View {
        NavigationStack {
            if done {
                ContentUnavailableView {
                    Label(L("submit.doneTitle"), systemImage: "checkmark.seal.fill")
                } description: {
                    Text(L("submit.doneBody"))
                } actions: {
                    Button(L("common.done")) { dismiss() }.glassButton(prominent: true)
                }
                .accessibilityIdentifier("submitDone")
            } else {
                form
            }
        }
        .onAppear {
            orientation.declinationProvider = { [location] in location.declination }
            orientation.compassFallback = { [location] in (location.compassHeading, location.headingAccuracy) }
            orientation.start()
        }
        .onDisappear { orientation.stop() }
    }

    private var form: some View {
        Form {
            Section {
                Text(L("submit.intro")).font(.callout).foregroundStyle(.secondary)
            }
            Section(L("submit.work")) {
                TextField(L("submit.workTitle"), text: $draft.workTitle)
                    .accessibilityIdentifier("submitWorkTitle")
                problemText(.workTitle)
                Picker(L("list.type"), selection: $draft.mediaType) {
                    Text(L("media.anime")).tag(MediaType.anime)
                    Text(L("submit.animeFilm")).tag(MediaType.animeFilm)
                    Text(L("media.drama")).tag(MediaType.drama)
                    Text(L("media.film")).tag(MediaType.film)
                }
            }
            Section(L("submit.scene")) {
                TextField(L("submit.sceneTitle"), text: $draft.sceneTitle)
                    .accessibilityIdentifier("submitSceneTitle")
                problemText(.sceneTitle)
                TextField(L("submit.episode"), text: $draft.episode)
                TextField(L("submit.story"), text: $draft.story, axis: .vertical)
                    .lineLimit(3...8)
                    .accessibilityIdentifier("submitStory")
                problemText(.story)
            }
            Section(L("submit.place")) {
                TextField(L("submit.placeName"), text: $draft.placeName)
                    .accessibilityIdentifier("submitPlaceName")
                problemText(.placeName)
                Picker(L("submit.position"), selection: $useCurrentLocation) {
                    Text(L("submit.useHere")).tag(true)
                    Text(L("submit.pickOnMap")).tag(false)
                }
                .pickerStyle(.segmented)
                if useCurrentLocation {
                    if let loc = location.lastLocation {
                        LabeledContent(L("submit.coordinate"),
                                       value: String(format: "%.5f, %.5f", loc.coordinate.latitude, loc.coordinate.longitude))
                        LabeledContent(L("submit.heading"),
                                       value: orientation.heading.map { "\(Compass.name($0)) \(Int($0.rounded()) % 360)°" } ?? "—")
                        Text(L("submit.hereHint")).font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text(L("scene.locating")).foregroundStyle(.secondary)
                    }
                } else {
                    MapReader { proxy in
                        Map(position: $camera) {
                            if let p = pinned {
                                Marker(L("submit.pin"), systemImage: "camera.fill", coordinate: p)
                            }
                            UserAnnotation()
                        }
                        .onTapGesture(coordinateSpace: .local) { point in
                            if let c = proxy.convert(point, from: .local) { pinned = c }
                        }
                    }
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    Text(L("submit.pinHint")).font(.caption).foregroundStyle(.secondary)
                    VStack(alignment: .leading) {
                        Text(L("submit.manualHeading", Compass.name(manualHeading), Int(manualHeading)))
                        Slider(value: $manualHeading, in: 0...359, step: 1)
                    }
                }
                problemText(.location)
            }
            Section(L("submit.photo")) {
                if let image {
                    Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                PhotosPicker(selection: $picked, matching: .images) {
                    Label(image == nil ? L("submit.addPhoto") : L("submit.changePhoto"), systemImage: "photo.badge.plus")
                }
                Text(L("submit.photoHint")).font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Toggle(L("submit.agree"), isOn: $agreed)
                    .accessibilityIdentifier("submitAgree")
                Text(L("community.rules")).font(.caption).foregroundStyle(.secondary)
                if let message {
                    Text(message).foregroundStyle(.orange)
                }
                Button {
                    guard let image else { return }
                    submitting = true
                    Task {
                        let result = await CommunityService.shared.submitScene(currentDraft, image: image)
                        submitting = false
                        switch result {
                        case .success: withAnimation { done = true }
                        case .failure(let f): message = CommunityText.failure(f)
                        }
                    }
                } label: {
                    HStack {
                        if submitting { ProgressView() }
                        Text(L("submit.send")).font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                }
                .disabled(!agreed || !problems.isEmpty || submitting)
                .accessibilityIdentifier("submitSend")
                if !problems.isEmpty {
                    Text(L("submit.missing")).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(L("submit.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button(L("common.cancel")) { dismiss() } }
        }
        .onChange(of: picked) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                    await MainActor.run { image = img }
                }
                await MainActor.run { picked = nil }
            }
        }
    }

    /// 只显示用户已经填过但有问题的字段（空着的字段不提前报错）
    @ViewBuilder private func problemText(_ field: SceneDraft.Field) -> some View {
        if let p = problems[field]?.first(where: { $0 != .empty }) {
            FilterProblemText(problem: p)
        }
    }
}

// MARK: - 设置页：我的投稿

struct MySubmissionsView: View {
    @State private var community = CommunityService.shared

    var body: some View {
        List {
            if community.mySubmissions.isEmpty {
                Text(L("submit.none")).foregroundStyle(.secondary)
            }
            ForEach(community.mySubmissions) { s in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.title).font(.headline)
                        Text(s.date.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(statusText(s.status))
                        .font(.caption.bold())
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(statusColor(s.status).opacity(0.15), in: Capsule())
                        .foregroundStyle(statusColor(s.status))
                }
            }
        }
        .navigationTitle(L("submit.mine"))
        .task { await community.refreshMySubmissions() }
    }

    private func statusText(_ s: String) -> String {
        switch s {
        case "approved": return L("submit.status.approved")
        case "rejected": return L("submit.status.rejected")
        default: return L("submit.status.pending")
        }
    }

    private func statusColor(_ s: String) -> Color {
        switch s {
        case "approved": return .green
        case "rejected": return .red
        default: return .orange
        }
    }
}
