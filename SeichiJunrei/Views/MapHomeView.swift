import SwiftUI
import UIKit
import MapKit
import SeichiCore

/// 地图上当前聚焦显示的一组名场面（某部作品，或一次搜索的全部结果）
struct MapFocus: Equatable {
    var title: String
    var subtitle: String
    var spots: [Spot]
    var tint: Color
}

struct MapHomeView: View {
    @Environment(SpotStore.self) private var store
    @Environment(LocationService.self) private var location
    @Environment(StoreService.self) private var storeKit
    @State private var showPaywall = false
    @State private var showSettings = false
    /// 地图上被点选的标记（spot id）
    @State private var mapSelection: String?

    @State private var camera: MapCameraPosition = .userLocation(
        fallback: .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 35.6812, longitude: 139.7671),  // 东京站
            span: MKCoordinateSpan(latitudeDelta: 0.2, longitudeDelta: 0.2))))
    @State private var selected: Spot?
    @State private var sceneSpot: Spot?
    @State private var showList = false
    /// 等当前 sheet 收起后要呈现的下一个页面
    @State private var pendingScene: Spot?
    @State private var pendingDetail: Spot?
    @State private var pendingPhotographer: Spot?
    @State private var photographerSpot: Spot?

    // 搜索
    @State private var query = ""
    @State private var isSearching = false
    @State private var mediaFilter: MediaCategory?
    @State private var focus: MapFocus?
    /// 点选搜索建议会顺带触发一次 onSubmit，用这个标记忽略它，避免覆盖刚选中的作品
    @State private var suppressSubmit = false
    /// 首次拿到定位时把地图缩放到用户附近
    @State private var didCenterOnUser = false

    private var searchResults: [SpotSearch.WorkMatch] {
        SpotSearch.search(query, in: store.spots, category: mediaFilter)
    }

    /// 地图上显示的名场面
    private var mapSpots: [Spot] {
        if let focus { return focus.spots }
        if !query.isEmpty { return searchResults.flatMap(\.spots) }
        if let mediaFilter { return store.spots.filter { $0.mediaType.category == mediaFilter } }
        return store.spots
    }

    /// 当前已经站在名场面位置的圣地（最近的一个）
    private var arrivedSpot: NearbySpot? {
        store.nearby.first { $0.hasArrived(accuracy: location.lastLocation?.horizontalAccuracy ?? 0) }
    }

    var body: some View {
        Map(position: $camera, selection: $mapSelection) {
            UserAnnotation()
            // 系统标记：标题显示“日漫《龙猫》”这样的作品名，重叠时 MapKit 会自动隐藏次要的标题
            ForEach(mapSpots) { spot in
                Marker(spot.workBadge, systemImage: spot.mediaType.category.symbolName, coordinate: spot.clCoordinate)
                    .tint(spot.tintColor)
                    .tag(spot.id)
            }
            if let arrived = arrivedSpot {
                Annotation("", coordinate: arrived.spot.clCoordinate, anchor: .center) {
                    ArrivalPulse(tint: arrived.spot.tintColor)
                }
                .annotationTitles(.hidden)
            }
        }
        .onChange(of: mapSelection) { _, id in
            guard let id else { return }
            if let spot = store.spots.first(where: { $0.id == id }) { selected = spot }
            mapSelection = nil
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .mapControls {
            MapUserLocationButton()
            MapCompass()
            MapScaleView()
        }
        .safeAreaInset(edge: .top) { topPanel }
        .safeAreaInset(edge: .bottom) { carousel }
        .navigationTitle(L("map.title"))
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, isPresented: $isSearching,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: Text(L("map.searchPrompt")))
        .searchSuggestions { suggestions }
        .onSubmit(of: .search) {
            guard !suppressSubmit else { return }
            let results = searchResults
            if results.count == 1 {
                focusOn(results[0])
            } else if !results.isEmpty {
                let spots = results.flatMap(\.spots)
                setFocus(MapFocus(title: L("map.queryResults", query),
                                  subtitle: L("map.queryResultsCount", results.count, spots.count),
                                  spots: spots, tint: .accentColor))
            }
        }
        .onChange(of: location.lastLocation) { _, loc in
            guard !didCenterOnUser, focus == nil, let loc else { return }
            didCenterOnUser = true
            withAnimation {
                camera = .region(MKCoordinateRegion(center: loc.coordinate,
                                                    span: MKCoordinateSpan(latitudeDelta: 0.04, longitudeDelta: 0.04)))
            }
        }
        .onChange(of: store.requestedSpotID) { _, _ in openRequestedSpot() }
        .onChange(of: store.spots.count) { _, _ in openRequestedSpot() }
        .onAppear { openRequestedSpot() }
        .onChange(of: mediaFilter) { _, _ in
            // 切换类型时，若当前聚焦的作品不属于该类型则取消聚焦
            if let f = focus, let m = mediaFilter, !f.spots.contains(where: { $0.mediaType.category == m }) {
                clearFocus()
            }
        }
        .toolbar {
            if storeKit.paywallEnabled {
            ToolbarItem(placement: .topBarLeading) {
                Button { showPaywall = true } label: {
                    Image(systemName: storeKit.entitlement.isUnlimited ? "ticket.fill" : "ticket")
                }
                .accessibilityLabel(L("paywall.title"))
                .accessibilityIdentifier("openPaywall")
            }
            }
            ToolbarItem(placement: .topBarLeading) {
                Button { showSettings = true } label: { Image(systemName: "gearshape") }
                    .accessibilityLabel(L("settings.title"))
                    .accessibilityIdentifier("openSettings")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showList = true } label: { Image(systemName: "list.bullet") }
                    .accessibilityLabel(L("map.allScenes"))
                    .accessibilityIdentifier("openList")
            }
        }
        // 先关闭当前 sheet，等它真正收起（onDismiss）后再呈现下一个模态视图。
        // 不能用固定延时：sheet 被拉到全屏高度时收起动画更长，提前呈现会被系统丢弃。
        .sheet(item: $selected, onDismiss: {
            if let next = pendingScene { pendingScene = nil; sceneSpot = next }
            if let next = pendingPhotographer { pendingPhotographer = nil; photographerSpot = next }
        }) { spot in
            SpotDetailView(spot: spot, onEnterScene: {
                pendingScene = spot
                selected = nil
            }, onPhotographer: {
                pendingPhotographer = spot
                selected = nil
            })
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showList, onDismiss: {
            if let next = pendingDetail { pendingDetail = nil; selected = next }
        }) {
            NearbyListView { spot in
                pendingDetail = spot
                showList = false
            }
        }
        .sheet(isPresented: $showPaywall) { PaywallView() }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .fullScreenCover(item: $sceneSpot) { spot in
            SceneModeView(spot: spot)
        }
        .fullScreenCover(item: $photographerSpot) { spot in
            PhotographerModeView(spot: spot)
        }
        .overlay {
            if let err = store.loadError {
                ContentUnavailableView(L("data.loadFailedTitle"), systemImage: "exclamationmark.triangle", description: Text(err))
                    .background(.regularMaterial)
            }
        }
    }

    private var topPanel: some View {
        VStack(spacing: 8) {
            MediaFilterBar(selection: $mediaFilter)
            if let focus {
                FocusChip(focus: focus) { clearFocus() }
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            PermissionBanner()
            if let arrived = arrivedSpot {
                ArrivalBanner(nearby: arrived) { sceneSpot = arrived.spot }
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.horizontal)
        .padding(.top, 4)
        .animation(.spring, value: arrivedSpot?.id)
        .animation(.spring, value: focus)
    }

    @ViewBuilder private var suggestions: some View {
        if searchResults.isEmpty {
            Text(L("map.noResults", query)).foregroundStyle(.secondary)
        } else {
            Section(query.isEmpty ? L("map.allWorks") : L("map.searchResults")) {
                ForEach(searchResults) { match in
                    Button { focusOn(match) } label: { WorkMatchRow(match: match) }
                        .accessibilityIdentifier("work-\(match.work)")
                }
            }
        }
    }

    @ViewBuilder private var carousel: some View {
        if focus != nil || mediaFilter != nil {
            NearbyCarousel(title: focus?.title ?? L("map.typeScenes", mediaFilter?.label ?? ""),
                           items: store.items(for: mapSpots)) { selected = $0 }
        } else {
            let within = store.nearbyWithinRadius
            NearbyCarousel(title: within.isEmpty ? L("map.nearestScenes") : L("map.nearbyScenes"),
                           items: within.isEmpty ? Array(store.nearby.prefix(10)) : within) { selected = $0 }
        }
    }

    /// 处理“点击通知 → 打开对应圣地”的请求（数据可能稍后才加载完）
    private func openRequestedSpot() {
        guard let id = store.requestedSpotID,
              let spot = store.spots.first(where: { $0.id == id }) else { return }
        store.requestedSpotID = nil
        sceneSpot = nil
        selected = spot
        fitCamera(to: [spot])
    }

    private func focusOn(_ match: SpotSearch.WorkMatch) {
        suppressSubmit = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { suppressSubmit = false }
        let first = match.spots.first
        setFocus(MapFocus(title: first?.workBadge ?? L("format.workTitle", match.work),
                          subtitle: L("map.focusSubtitle", first?.originalWorkName ?? match.mediaType.label,
                                      match.spots.count),
                          spots: match.spots,
                          tint: match.spots.first?.tintColor ?? .accentColor))
    }

    private func setFocus(_ f: MapFocus) {
        focus = f
        isSearching = false
        fitCamera(to: f.spots)
        if f.spots.count == 1 { selected = f.spots[0] }
    }

    private func clearFocus() {
        focus = nil
        query = ""
    }

    private func fitCamera(to spots: [Spot]) {
        guard let b = SpotSearch.boundingBox(of: spots) else { return }
        let center = CLLocationCoordinate2D(latitude: (b.minLat + b.maxLat) / 2,
                                            longitude: (b.minLon + b.maxLon) / 2)
        // 留出边距，并且至少显示约 1km 的范围
        let span = MKCoordinateSpan(latitudeDelta: max((b.maxLat - b.minLat) * 1.6, 0.012),
                                    longitudeDelta: max((b.maxLon - b.minLon) * 1.6, 0.012))
        withAnimation(.easeInOut(duration: 0.8)) {
            camera = .region(MKCoordinateRegion(center: center, span: span))
        }
    }
}

/// 类型筛选：全部 / 日漫 / 日剧 / 日影（各语言用当地最常用的叫法）
private struct MediaFilterBar: View {
    @Binding var selection: MediaCategory?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            GlassGroup(spacing: 8) {
                HStack(spacing: 8) {
                    chip(title: L("map.all"), symbol: "square.grid.2x2", value: nil)
                    ForEach(MediaCategory.allCases, id: \.self) { type in
                        chip(title: type.label, symbol: type.symbolName, value: type)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .scrollClipDisabled()
    }

    private func chip(title: String, symbol: String, value: MediaCategory?) -> some View {
        let isOn = selection == value
        return Button {
            withAnimation(.snappy) { selection = value }
        } label: {
            Label(title, systemImage: symbol)
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 14)
                .frame(minHeight: 44)                       // HIG：触控区域 ≥ 44pt
                .foregroundStyle(isOn ? Color.white : Color.primary)
                .glassSurface(Capsule(), tint: isOn ? .accentColor : nil, interactive: true)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// 当前聚焦作品的提示条，可一键取消
private struct FocusChip: View {
    let focus: MapFocus
    let onClear: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "scope").foregroundStyle(focus.tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(focus.title).font(.subheadline.bold()).lineLimit(1)
                Text(focus.subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: onClear) {
                Image(systemName: "xmark.circle.fill").font(.title3).foregroundStyle(.secondary)
                    .minimumHitTarget()
            }
            .accessibilityLabel(L("map.showAll"))
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .glassSurface(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("focusChip")
    }
}

/// 搜索结果中的一部作品
struct WorkMatchRow: View {
    let match: SpotSearch.WorkMatch

    var body: some View {
        HStack(spacing: 12) {
            if let first = match.spots.first { WorkCover(spot: first, size: 34) }
            VStack(alignment: .leading, spacing: 2) {
                // 当前语言的名字在上，原名在下（日语环境只显示原名）
                HStack(spacing: 6) {
                    Text(match.workLocalized ?? match.work).font(.headline).lineLimit(1)
                    Text(match.mediaType.label)
                        .font(.caption2.bold())
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(.quaternary, in: Capsule())
                }
                if match.workLocalized != nil, match.workLocalized != match.work {
                    Text(match.work).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Text(match.spots.map(\.sceneTitle).joined(separator: " · "))
                    .font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
            }
            Spacer()
            Text("\(match.spots.count)")
                .font(.callout.bold().monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }
}

/// 已到达的名场面：在标记下面加一圈脉冲
private struct ArrivalPulse: View {
    let tint: Color
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Circle()
            .stroke(tint, lineWidth: 3)
            .frame(width: 54, height: 54)
            .scaleEffect(pulse ? 1.4 : 0.8)
            .opacity(pulse ? 0 : 1)
            .animation(.easeOut(duration: 1.4).repeatForever(autoreverses: false), value: pulse)
            .onAppear { pulse = !reduceMotion }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private struct ArrivalBanner: View {
    let nearby: NearbySpot
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: "figure.stand")
                    .font(.title2)
                    .symbolEffect(.pulse, options: .repeating)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("map.arrivedTitle")).font(.headline)
                    Text(nearby.spot.workTitle + " " + nearby.spot.quotedSceneTitle)
                        .font(.subheadline).lineLimit(1)
                }
                Spacer()
                Image(systemName: "camera.viewfinder").font(.title2)
            }
            .foregroundStyle(.white)
            .padding()
            .glassSurface(RoundedRectangle(cornerRadius: 24, style: .continuous),
                          tint: nearby.spot.tintColor, interactive: true)
            .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("arrivalBanner")
    }
}

private struct PermissionBanner: View {
    @Environment(LocationService.self) private var location
    @AppStorage("dismissedAlwaysPrompt") private var dismissedAlwaysPrompt = false

    var body: some View {
        switch location.authorization {
        case .denied, .restricted:
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            } label: {
                Label(L("map.needLocation"), systemImage: "location.slash")
                    .font(.footnote)
                    .padding(12)
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(.white)
                    .glassSurface(RoundedRectangle(cornerRadius: 20, style: .continuous), tint: .orange, interactive: true)
            }
            .buttonStyle(.plain)
        case .authorizedWhenInUse where !dismissedAlwaysPrompt:
            HStack(spacing: 6) {
                Button { location.requestAlwaysAuthorization() } label: {
                    Label(L("map.alwaysPrompt"), systemImage: "bell.badge")
                        .font(.caption)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Button { dismissedAlwaysPrompt = true } label: {
                    Image(systemName: "xmark").font(.caption.bold()).foregroundStyle(.secondary)
                        .minimumHitTarget()
                }
                .accessibilityLabel(L("map.dontShowAgain"))
            }
            .buttonStyle(.plain)
            .padding(.leading, 14)
            .glassSurface(RoundedRectangle(cornerRadius: 20, style: .continuous))
        default:
            EmptyView()
        }
    }
}

private struct NearbyCarousel: View {
    let title: String
    let items: [NearbySpot]
    let onSelect: (Spot) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 名场面卡片属于“内容”，保持实底；只有标题这一小块控制层用玻璃
            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .glassSurface(Capsule())
                .padding(.horizontal)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(items) { item in
                        SpotCard(item: item)
                            .onTapGesture { onSelect(item.spot) }
                            .accessibilityElement(children: .combine)
                            .accessibilityAddTraits(.isButton)
                            .accessibilityIdentifier("card-\(item.spot.id)")
                    }
                }
                .padding(.horizontal)
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollClipDisabled()
            .frame(height: 96)   // 横向滚动视图默认会占满纵向空间，必须固定高度
        }
        .padding(.bottom, 8)
    }
}

struct SpotCard: View {
    let item: NearbySpot

    var body: some View {
        HStack(spacing: 10) {
            SceneArtwork(spot: item.spot, compact: true, useLocationPhoto: true)
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 3) {
                Text(item.spot.workBadge).font(.caption).foregroundStyle(item.spot.tintColor).lineLimit(1)
                Text(item.spot.sceneTitle).font(.subheadline.bold()).lineLimit(1)
                if item.distance.isFinite {
                    Label(NearbySearch.formatDistance(item.distance), systemImage: "location.north.line")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Label(item.spot.placeName, systemImage: "mappin.and.ellipse")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(width: 260)
        .background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
    }
}
