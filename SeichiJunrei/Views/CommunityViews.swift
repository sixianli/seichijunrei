import SwiftUI
import PhotosUI
import MapKit
import SeichiCore

// MARK: - 详情页：巡礼者的照片

/// 封面下面的一排“巡礼者拍的”缩略图：看别人在现场怎么拍；没人上传时只是一个小按钮
struct CommunityPhotoStrip: View {
    let spot: Spot
    @State private var community = CommunityService.shared
    @State private var picked: PhotosPickerItem?
    @State private var uploadItem: IdentifiedImage?
    @State private var viewing: CommunityPhoto?

    private var photos: [CommunityPhoto] { community.photosBySpot[spot.id] ?? [] }

    var body: some View {
        // 一张小卡片：还没人上传时是“来当第一个”+ 上传按钮；有照片后同一位置变成照片条，按钮还在右上角
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Label(photos.isEmpty ? L("community.stripTitleEmpty") : L("community.stripTitle", photos.count),
                          systemImage: "person.2.fill")
                        .font(.subheadline.bold())
                        .fixedSize(horizontal: false, vertical: true)
                    if photos.isEmpty {
                        Text(L("community.beFirst"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                PhotosPicker(selection: $picked, matching: .images, preferredItemEncoding: .current, photoLibrary: .shared()) {
                    Label(L("community.uploadShort"), systemImage: "camera.fill")
                        .font(.subheadline.weight(.bold))
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .foregroundStyle(photos.isEmpty ? Color.white : spot.tintColor)
                        .background(photos.isEmpty ? spot.tintColor : spot.tintColor.opacity(0.14), in: Capsule())
                        .fixedSize()
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("uploadCommunityPhoto")
            }
            if !photos.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(photos) { photo in
                            Button { viewing = photo } label: {
                                LocalImage(url: photo.imageURL)
                                    .frame(width: 92, height: 112)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(photo.caption.isEmpty ? L("community.photo") : photo.caption)
                            .accessibilityIdentifier("communityPhoto")
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .task(id: spot.id) { await community.loadPhotos(spotID: spot.id) }
        .onChange(of: picked) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    let src = UploadSource.library(data: data, itemIdentifier: item.itemIdentifier)
                    await MainActor.run { uploadItem = IdentifiedImage(image: image, source: src) }
                }
                await MainActor.run { picked = nil }
            }
        }
        .sheet(item: $uploadItem) { item in
            UploadPhotoSheet(spot: spot, image: item.image, source: item.source)
        }
        .sheet(item: $viewing) { photo in
            CommunityPhotoViewer(photo: photo)
        }
    }
}

struct IdentifiedImage: Identifiable {
    let id = UUID()
    let image: UIImage
    let source: UploadSource
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
    /// 照片的拍摄位置（App 里拍的取当时定位，相册里选的读 EXIF）
    /// 照片来源：App 相机拍的直接通过；相册里的要查截图 / 相机信息 / 拍摄位置
    let source: UploadSource
    @Environment(\.dismiss) private var dismiss
    @State private var caption = ""
    @State private var ownPhoto = false
    @State private var uploading = false
    @State private var message: String?
    /// 自动检查：nil 表示还在检查
    @State private var checked = false
    @State private var problem: PhotoModeration.Problem?

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
                    if !checked {
                        Label(L("moderation.checking"), systemImage: "hourglass").font(.callout)
                            .foregroundStyle(.secondary)
                    } else if let problem {
                        Label(PhotoModeration.message(problem), systemImage: "exclamationmark.triangle.fill")
                            .font(.callout.bold())
                            .foregroundStyle(.orange)
                            .accessibilityIdentifier("moderationProblem")
                    }
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
                    .disabled(!ownPhoto || !captionProblems.isEmpty || uploading || !checked || problem != nil
                              || CommunityService.shared.uploadsBlocked)
                    .accessibilityIdentifier("communityUploadConfirm")
                }
                .padding()
            }
            .task {
                if CommunityService.shared.uploadsBlocked {
                    problem = nil; checked = true; message = L("moderation.blocked"); return
                }
                problem = await PhotoModeration.check(image: image, source: source, spot: spot)
                checked = true
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
            // 记录短原因（copyright / spam …）：以版权举报 1 次就先隐藏
            let short = reason.replacingOccurrences(of: "community.reason.", with: "")
            let result = await CommunityService.shared.report(targetType: "photo", targetID: photo.id, reason: short)
            switch result {
            case .success:
                notice = L("community.reported")
                if short == ReportPolicy.copyrightReason { CommunityService.shared.hideLocally(photo) }
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
    /// 地点名称是不是自动反查出来的（用户手动改过之后就不再覆盖）
    @State private var placeAutoFilled = false
    @State private var geocoder = CLGeocoder()

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
        .onChange(of: useCurrentLocation) { _, _ in autofillPlaceName() }
        .onChange(of: pinned?.latitude) { _, _ in autofillPlaceName() }
        .task(id: location.lastLocation == nil) { autofillPlaceName() }
    }

    private var form: some View {
        Form {
            Section {
                Text(L("submit.intro")).font(.callout).foregroundStyle(.secondary)
                Text(L("submit.requiredLegend")).font(.caption).foregroundStyle(.secondary)
            }
            Section(L("submit.work")) {
                TextField(L("submit.workTitle") + " *", text: $draft.workTitle)
                    .accessibilityIdentifier("submitWorkTitle")
                problemText(.workTitle)
                Picker(L("list.type") + " *", selection: $draft.mediaType) {
                    Text(L("media.anime")).tag(MediaType.anime)
                    Text(L("submit.animeFilm")).tag(MediaType.animeFilm)
                    Text(L("media.drama")).tag(MediaType.drama)
                    Text(L("media.film")).tag(MediaType.film)
                }
            }
            Section(L("submit.scene")) {
                TextField(L("submit.sceneTitle") + " *", text: $draft.sceneTitle)
                    .accessibilityIdentifier("submitSceneTitle")
                problemText(.sceneTitle)
                TextField(L("submit.episode"), text: $draft.episode)
                TextField(L("submit.story") + " *", text: $draft.story, axis: .vertical)
                    .lineLimit(3...8)
                    .accessibilityIdentifier("submitStory")
                problemText(.story)
            }
            Section {
                Picker(L("submit.position"), selection: $useCurrentLocation) {
                    Text(L("submit.useHere")).tag(true)
                    Text(L("submit.pickOnMap")).tag(false)
                }
                .pickerStyle(.segmented)
                if useCurrentLocation {
                    Text(L("submit.hereHint")).font(.caption).foregroundStyle(.secondary)
                    if let loc = location.lastLocation {
                        LabeledContent(L("submit.coordinate"),
                                       value: String(format: "%.5f, %.5f", loc.coordinate.latitude, loc.coordinate.longitude))
                        LabeledContent(L("submit.heading"),
                                       value: orientation.heading.map { "\(Compass.name($0)) \(Int($0.rounded()) % 360)°" } ?? "—")
                    } else {
                        Text(L("scene.locating")).foregroundStyle(.secondary)
                    }
                } else {
                    Text(L("submit.pinHint")).font(.caption).foregroundStyle(.secondary)
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
                    VStack(alignment: .leading) {
                        Text(L("submit.manualHeading", Compass.name(manualHeading), Int(manualHeading)))
                        Slider(value: $manualHeading, in: 0...359, step: 1)
                    }
                }
                TextField(L("submit.placeName") + " *", text: Binding(
                    get: { draft.placeName },
                    set: { draft.placeName = $0; placeAutoFilled = false }))
                    .accessibilityIdentifier("submitPlaceName")
                Text(L("submit.placeAutoHint")).font(.caption).foregroundStyle(.secondary)
                problemText(.placeName)
            } header: {
                Text(L("submit.place") + " *")
            }
            Section {
                if let image {
                    Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                PhotosPicker(selection: $picked, matching: .images) {
                    Label(image == nil ? L("submit.addPhoto") : L("submit.changePhoto"), systemImage: "photo.badge.plus")
                }
                Text(L("submit.photoHint")).font(.caption).foregroundStyle(.secondary)
            } header: {
                Text(L("submit.photo") + " *")
            }
            Section {
                Toggle(L("submit.agree") + " *", isOn: $agreed)
                    .accessibilityIdentifier("submitAgree")
                Text(L("community.rules")).font(.caption).foregroundStyle(.secondary)
                if let message {
                    Text(message).foregroundStyle(.orange)
                }
            }
            Section {
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
                        if submitting { ProgressView().tint(.white) }
                        Text(L("submit.send")).font(.headline)
                    }
                    .frame(maxWidth: .infinity, minHeight: 34)
                }
                // 置灰时也保持按钮的样子，不能变成一行纯文字
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!missingFields.isEmpty || submitting)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .accessibilityIdentifier("submitSend")
            } footer: {
                if !missingFields.isEmpty {
                    Text(L("submit.stillMissing", missingFields.joined(separator: L("submit.listSeparator"))))
                        .accessibilityIdentifier("submitMissing")
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

    /// 还没填好的必填项（用于按钮下方的提示）
    private var missingFields: [String] {
        let p = problems
        var out: [String] = []
        if p[.workTitle] != nil { out.append(L("submit.workTitleShort")) }
        if p[.sceneTitle] != nil { out.append(L("submit.sceneTitleShort")) }
        if p[.story] != nil { out.append(L("submit.storyShort")) }
        if p[.placeName] != nil { out.append(L("submit.placeNameShort")) }
        if p[.location] != nil { out.append(L(useCurrentLocation ? "submit.locationShort" : "submit.pinShort")) }
        if p[.heading] != nil { out.append(L("submit.headingShort")) }
        if p[.photo] != nil { out.append(L("submit.photoShort")) }
        if !agreed { out.append(L("submit.agreeShort")) }
        return out
    }

    /// 根据机位坐标反查地址，自动填写地点名称（用户手动改过就不覆盖）
    private func autofillPlaceName() {
        guard draft.placeName.isEmpty || placeAutoFilled,
              let lat = currentDraft.latitude, let lon = currentDraft.longitude else { return }
        geocoder.cancelGeocode()
        geocoder.reverseGeocodeLocation(CLLocation(latitude: lat, longitude: lon),
                                        preferredLocale: Locale(identifier: AppLanguage.current)) { marks, _ in
            guard let m = marks?.first else { return }
            let name = [m.name, m.locality].compactMap { $0 }.reduce(into: [String]()) { acc, part in
                if !acc.contains(part) { acc.append(part) }
            }
            guard let first = name.first else { return }
            let text = name.count > 1 ? L("submit.placeFormat", first, name[1]) : first
            DispatchQueue.main.async {
                guard draft.placeName.isEmpty || placeAutoFilled else { return }
                draft.placeName = text
                placeAutoFilled = true
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

/// 我的投稿：新名场面、现场照片、机位校准，各自的审核状态；可以删除
struct MySubmissionsView: View {
    @State private var community = CommunityService.shared
    @State private var deleting: MySubmission?
    @State private var message: String?

    private let kinds: [MySubmission.Kind] = [.scene, .photo, .calibration]

    var body: some View {
        List {
            if community.mySubmissions.isEmpty {
                Text(L("submit.none")).foregroundStyle(.secondary)
            }
            ForEach(kinds, id: \.self) { kind in
                let items = community.mySubmissions.filter { $0.resolvedKind == kind }
                if !items.isEmpty {
                    Section(sectionTitle(kind)) {
                        ForEach(items) { s in
                            row(s)
                                .swipeActions {
                                    Button(role: .destructive) { deleting = s } label: {
                                        Label(L("submit.delete"), systemImage: "trash")
                                    }
                                }
                        }
                    }
                }
            }
            if let message {
                Text(message).font(.footnote).foregroundStyle(.orange)
            }
            Section {
                Text(L("submit.mineFooter")).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle(L("submit.mine"))
        .task { await community.refreshMySubmissions() }
        .confirmationDialog(L("submit.deleteConfirm"), isPresented: Binding(get: { deleting != nil },
                                                                           set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible) {
            Button(L("submit.delete"), role: .destructive) {
                guard let d = deleting else { return }
                Task {
                    if case .failure(let f) = await community.deleteMySubmission(d) { message = CommunityText.failure(f) }
                }
            }
        }
    }

    private func row(_ s: MySubmission) -> some View {
        HStack {
            Image(systemName: icon(s.resolvedKind)).foregroundStyle(.secondary).frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(s.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                Text(s.date.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(statusText(s.status))
                .font(.caption.bold())
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(statusColor(s.status).opacity(0.15), in: Capsule())
                .foregroundStyle(statusColor(s.status))
        }
        .accessibilityIdentifier("mySubmission-\(s.resolvedKind.rawValue)")
    }

    private func sectionTitle(_ k: MySubmission.Kind) -> String {
        switch k {
        case .scene: return L("submit.kind.scene")
        case .photo: return L("submit.kind.photo")
        case .calibration: return L("submit.kind.calibration")
        }
    }

    private func icon(_ k: MySubmission.Kind) -> String {
        switch k {
        case .scene: return "film"
        case .photo: return "photo"
        case .calibration: return "scope"
        }
    }

    private func statusText(_ s: String) -> String {
        switch s {
        case "approved": return L("submit.status.approved")
        case "rejected": return L("submit.status.rejected")
        case "visible": return L("submit.status.visible")
        case "hidden": return L("submit.status.hidden")
        case "received": return L("submit.status.received")
        case "removed": return L("submit.status.removed")
        default: return L("submit.status.pending")
        }
    }

    private func statusColor(_ s: String) -> Color {
        switch s {
        case "approved", "visible", "received": return .green
        case "rejected", "hidden", "removed": return .red
        default: return .orange
        }
    }
}
