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

    @State private var camera: MapCameraPosition = .userLocation(
        fallback: .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 35.6812, longitude: 139.7671),  // 东京站
            span: MKCoordinateSpan(latitudeDelta: 0.2, longitudeDelta: 0.2))))
    @State private var selected: Spot?
    @State private var sceneSpot: Spot?
    @State private var showList = false

    // 搜索
    @State private var query = ""
    @State private var isSearching = false
    @State private var mediaFilter: MediaType?
    @State private var focus: MapFocus?
    /// 点选搜索建议会顺带触发一次 onSubmit，用这个标记忽略它，避免覆盖刚选中的作品
    @State private var suppressSubmit = false
    /// 首次拿到定位时把地图缩放到用户附近
    @State private var didCenterOnUser = false

    private var searchResults: [SpotSearch.WorkMatch] {
        SpotSearch.search(query, in: store.spots, mediaType: mediaFilter)
    }

    /// 地图上显示的名场面
    private var mapSpots: [Spot] {
        if let focus { return focus.spots }
        if !query.isEmpty { return searchResults.flatMap(\.spots) }
        if let mediaFilter { return store.spots.filter { $0.mediaType == mediaFilter } }
        return store.spots
    }

    /// 当前已经站在名场面位置的圣地（最近的一个）
    private var arrivedSpot: NearbySpot? {
        store.nearby.first { $0.hasArrived(accuracy: location.lastLocation?.horizontalAccuracy ?? 0) }
    }

    var body: some View {
        Map(position: $camera) {
            UserAnnotation()
            ForEach(mapSpots) { spot in
                Annotation(spot.placeName, coordinate: spot.clCoordinate, anchor: .bottom) {
                    SpotPin(spot: spot, isArrived: arrivedSpot?.id == spot.id)
                        .onTapGesture { selected = spot }
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .mapControls {
            MapUserLocationButton()
            MapCompass()
            MapScaleView()
        }
        .safeAreaInset(edge: .top) { topPanel }
        .safeAreaInset(edge: .bottom) { carousel }
        .navigationTitle("圣地巡礼")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, isPresented: $isSearching,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "搜索动画、电影、电视剧的名字")
        .searchSuggestions { suggestions }
        .onSubmit(of: .search) {
            guard !suppressSubmit else { return }
            let results = searchResults
            if results.count == 1 {
                focusOn(results[0])
            } else if !results.isEmpty {
                let spots = results.flatMap(\.spots)
                setFocus(MapFocus(title: "「\(query)」的搜索结果",
                                  subtitle: "\(results.count) 部作品 · \(spots.count) 个名场面",
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
            if let f = focus, let m = mediaFilter, !f.spots.contains(where: { $0.mediaType == m }) {
                clearFocus()
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showList = true } label: { Image(systemName: "list.bullet") }
                    .accessibilityLabel("全部名场面")
                    .accessibilityIdentifier("openList")
            }
        }
        .sheet(item: $selected) { spot in
            SpotDetailView(spot: spot) {
                selected = nil
                // 等 sheet 收起后再弹出全屏的名场面模式，避免同时呈现两个模态视图
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { sceneSpot = spot }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showList) {
            NearbyListView { spot in
                showList = false
                // 等列表 sheet 收起后再弹出详情
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { selected = spot }
            }
        }
        .fullScreenCover(item: $sceneSpot) { spot in
            SceneModeView(spot: spot)
        }
        .overlay {
            if let err = store.loadError {
                ContentUnavailableView("数据加载失败", systemImage: "exclamationmark.triangle", description: Text(err))
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
            Text("没有找到「\(query)」相关的名场面").foregroundStyle(.secondary)
        } else {
            Section(query.isEmpty ? "全部作品" : "搜索结果") {
                ForEach(searchResults) { match in
                    Button { focusOn(match) } label: { WorkMatchRow(match: match) }
                        .accessibilityIdentifier("work-\(match.work)")
                }
            }
        }
    }

    @ViewBuilder private var carousel: some View {
        if focus != nil || mediaFilter != nil {
            NearbyCarousel(title: focus?.title ?? "\(mediaFilter?.label ?? "")的名场面",
                           items: store.items(for: mapSpots)) { selected = $0 }
        } else {
            let within = store.nearbyWithinRadius
            NearbyCarousel(title: within.isEmpty ? "离你最近的名场面" : "附近的名场面",
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
        let names = match.workLocalized.map { "\(match.work)（\($0)）" } ?? match.work
        setFocus(MapFocus(title: "《\(names)》",
                          subtitle: "\(match.mediaType.label) · \(match.spots.count) 个名场面",
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

/// 类型筛选：全部 / 动画 / 动画电影 / 电影 / 电视剧
private struct MediaFilterBar: View {
    @Binding var selection: MediaType?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(title: "全部", symbol: "square.grid.2x2", value: nil)
                ForEach(MediaType.allCases, id: \.self) { type in
                    chip(title: type.label, symbol: type.symbolName, value: type)
                }
            }
        }
    }

    private func chip(title: String, symbol: String, value: MediaType?) -> some View {
        let isOn = selection == value
        return Button {
            withAnimation(.snappy) { selection = value }
        } label: {
            Label(title, systemImage: symbol)
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(isOn ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Material.ultraThinMaterial),
                            in: Capsule())
                .foregroundStyle(isOn ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
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
            }
            .accessibilityLabel("显示全部名场面")
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("focusChip")
    }
}

/// 搜索结果中的一部作品
struct WorkMatchRow: View {
    let match: SpotSearch.WorkMatch

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: match.mediaType.symbolName)
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background((match.spots.first?.tintColor ?? .accentColor).gradient,
                            in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(match.work).font(.headline).lineLimit(1)
                    Text(match.mediaType.label)
                        .font(.caption2.bold())
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(.quaternary, in: Capsule())
                }
                if let cn = match.workLocalized {
                    Text(cn).font(.caption).foregroundStyle(.secondary).lineLimit(1)
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

private struct SpotPin: View {
    let spot: Spot
    let isArrived: Bool
    @State private var pulse = false

    var body: some View {
        ZStack {
            if isArrived {
                Circle()
                    .stroke(spot.tintColor, lineWidth: 3)
                    .frame(width: 54, height: 54)
                    .scaleEffect(pulse ? 1.4 : 0.8)
                    .opacity(pulse ? 0 : 1)
                    .animation(.easeOut(duration: 1.4).repeatForever(autoreverses: false), value: pulse)
                    .onAppear { pulse = true }
            }
            VStack(spacing: 0) {
                Image(systemName: spot.mediaType.symbolName)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(spot.tintColor, in: Circle())
                    .overlay(Circle().stroke(.white, lineWidth: 2))
                    .shadow(radius: 3)
                Triangle()
                    .fill(spot.tintColor)
                    .frame(width: 10, height: 7)
            }
        }
        .accessibilityLabel("\(spot.work) \(spot.sceneTitle)")
    }
}

private struct Triangle: Shape {
    func path(in r: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: r.minX, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
            p.addLine(to: CGPoint(x: r.midX, y: r.maxY))
            p.closeSubpath()
        }
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
                    Text("你就站在名场面里！").font(.headline)
                    Text("《\(nearby.spot.work)》「\(nearby.spot.sceneTitle)」")
                        .font(.subheadline).lineLimit(1)
                }
                Spacer()
                Image(systemName: "camera.viewfinder").font(.title2)
            }
            .foregroundStyle(.white)
            .padding()
            .background(nearby.spot.tintColor.gradient, in: RoundedRectangle(cornerRadius: 16))
            .shadow(radius: 6)
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
                Label("需要定位权限才能发现附近的圣地，点此前往设置", systemImage: "location.slash")
                    .font(.footnote)
                    .padding(10)
                    .frame(maxWidth: .infinity)
                    .background(.orange.opacity(0.9), in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(.white)
            }
        case .authorizedWhenInUse where !dismissedAlwaysPrompt:
            HStack(spacing: 6) {
                Button { location.requestAlwaysAuthorization() } label: {
                    Label("开启“始终允许”定位，靠近圣地时提醒你", systemImage: "bell.badge")
                        .font(.caption)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Button { dismissedAlwaysPrompt = true } label: {
                    Image(systemName: "xmark").font(.caption.bold()).foregroundStyle(.secondary)
                }
                .accessibilityLabel("不再提示")
            }
            .buttonStyle(.plain)
            .padding(8)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
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
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
                .lineLimit(1)
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
            .frame(height: 96)   // 横向滚动视图默认会占满纵向空间，必须固定高度
        }
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }
}

struct SpotCard: View {
    let item: NearbySpot

    var body: some View {
        HStack(spacing: 10) {
            SceneArtwork(spot: item.spot, compact: true)
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 3) {
                Text(item.spot.work).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Text(item.spot.sceneTitle).font(.subheadline.bold()).lineLimit(1)
                if item.distance.isFinite {
                    Label(NearbySearch.formatDistance(item.distance), systemImage: "location.north.line")
                        .font(.caption)
                        .foregroundStyle(item.spot.tintColor)
                } else {
                    Label(item.spot.mediaType.label, systemImage: item.spot.mediaType.symbolName)
                        .font(.caption)
                        .foregroundStyle(item.spot.tintColor)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(width: 260)
        .background(.background, in: RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
    }
}
