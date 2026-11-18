import SwiftUI
import PhotosUI
import MapKit
import SeichiCore

struct SpotDetailView: View {
    let spot: Spot
    let onEnterScene: () -> Void
    /// 帮拍模式（请别人帮忙拍）
    var onPhotographer: () -> Void = {}

    @Environment(SpotStore.self) private var store
    @Environment(LocationService.self) private var location
    @Environment(PilgrimageStore.self) private var pilgrimage
    @State private var showShare = false
    @State private var showCalibration = false

    private var info: NearbySpot? { store.nearbyInfo(for: spot) }
    private var arrived: Bool { info?.hasArrived(accuracy: location.lastLocation?.horizontalAccuracy ?? 0) ?? false }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // 封面：AI 插画 / 实景照片（右下角可以去网上看原作画面）
                SpotHeroImage(spot: spot)

                // 巡礼者在现场拍的照片：紧挨着封面，看完插画顺手看真实的样子
                CommunityPhotoStrip(spot: spot)

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

                actions

                if let highlight = spot.highlight {
                    DetailSection(title: L("detail.highlight"), systemImage: "sparkles", tint: spot.tintColor) {
                        ExpandableText(text: highlight, font: .body.weight(.medium), tint: spot.tintColor,
                                       identifier: "highlightText")
                    }
                }

                DetailSection(title: L("detail.story"), systemImage: "book.fill", tint: spot.tintColor) {
                    ExpandableText(text: spot.story, font: .body, tint: spot.tintColor, identifier: "storyText")
                }

                guide

                MyPhotosSection(spot: spot)

                aboutWork

                SceneScreenshotSection(spot: spot)

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
        VStack(alignment: .leading, spacing: 4) {
            Text(spot.badgeWithNumber)
                .font(.subheadline.bold())
                .foregroundStyle(spot.tintColor)
            // 原名：和译名同色、字号小一档，加“原名《》”让人一眼看出是原作的名字
            if let original = spot.originalWorkName {
                Text(L("detail.originalTitle", L("format.workTitle", original)))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(spot.tintColor)
                    .accessibilityIdentifier("originalTitle")
            }
            Text(spot.sceneTitle).font(.title.bold()).padding(.top, 2)
            ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 6) {
                if let ep = spot.episode { Tag(text: ep, systemImage: "play.rectangle") }
                Tag(text: spot.placeName, systemImage: "mappin.and.ellipse")
            } }
            .padding(.top, 2)
            if arrived {
                Label(L("detail.atSpot"), systemImage: "figure.stand")
                    .font(.callout.bold())
                    .foregroundStyle(spot.tintColor)
            } else if let info, info.distance.isFinite {
                LiveDirectionRow(spot: spot, distance: info.distance, bearing: info.bearing)
            }
        }
    }

    // MARK: 两个同等重要的入口：拍风景 / 自己入镜

    private var actions: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                ActionCard(title: arrived ? L("detail.enterScene") : L("detail.startGuide"),
                           subtitle: L("detail.recreateSubtitle"),
                           systemImage: "camera.viewfinder", tint: .accentColor,
                           identifier: "enterScene", action: onEnterScene)
                ActionCard(title: L("detail.photographer"),
                           subtitle: L("detail.photographerSubtitle"),
                           systemImage: "person.crop.rectangle.badge.plus", tint: spot.tintColor,
                           identifier: "openPhotographer", action: onPhotographer)
            }
            Text(actionHint)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
    }

    private var actionHint: String {
        if arrived { return L("detail.actionHintArrived") }
        guard let info, info.distance.isFinite else { return L("detail.actionHintUnknown") }
        if info.distance > JourneyStage.nearEnter {
            return L("detail.actionHintFar", NearbySearch.formatDistance(info.distance))
        }
        return L("detail.actionHintNear", NearbySearch.formatDistance(info.distance))
    }

    // MARK: 巡礼攻略

    private var guide: some View {
        DetailSection(title: L("detail.guide"), systemImage: "map.fill", tint: spot.tintColor) {
            VStack(alignment: .leading, spacing: 14) {
                if let access = spot.access {
                    InfoRow(title: L("detail.access"), text: access, systemImage: "tram.fill")
                    if spot.accessPoint != nil {
                        AccessRouteMap(spot: spot)
                    }
                }
                if !spot.bestMonths.isEmpty || spot.bestTime != nil {
                    VStack(alignment: .leading, spacing: 6) {
                        InfoRow(title: L("detail.bestTime"), text: spot.bestTime ?? "", systemImage: "sun.horizon.fill",
                                emphasis: spot.bestMonths.isEmpty ? nil : MonthText.best(spot.bestMonths))
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    InfoRow(title: L("detail.shot"), text: spot.verified ? L("detail.shotVerified") : L("detail.shotEstimated"),
                            systemImage: "camera.metering.center.weighted")
                    ShotMap(spot: spot)
                    Button { showCalibration = true } label: {
                        Label(L("detail.calibrateLink"), systemImage: "scope")
                            .font(.footnote.weight(.semibold))
                    }
                    .foregroundStyle(spot.tintColor)
                    .accessibilityIdentifier("detailCalibrate")
                }
                if let tips = spot.trivia {
                    InfoRow(title: L("detail.tips"), text: tips, systemImage: "exclamationmark.bubble.fill")
                }
            }
        }
    }

    @ViewBuilder private var aboutWork: some View {
        DetailSection(title: L("detail.aboutWork"), systemImage: "film.stack", tint: spot.tintColor) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 12) {
                    CategoryIcon(category: spot.mediaType.category, size: 40)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(spot.quotedWorkName).font(.headline)
                        if let original = spot.originalWorkName {
                            Text(L("detail.originalTitle", L("format.workTitle", original)))
                                .font(.subheadline).foregroundStyle(spot.tintColor)
                        }
                        Text([spot.mediaLabel, spot.year.map(String.init), spot.creator]
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

// MARK: - 组件

/// 两个主入口之一：大图标 + 标题 + 一行说明，实心填充，同等分量
private struct ActionCard: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    let identifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 26, weight: .semibold))
                Text(title)
                    .font(.headline)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle)
                    .font(.caption)
                    .opacity(0.9)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .foregroundStyle(.white)
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 140, alignment: .topLeading)
            .background(tint.gradient, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier(identifier)
    }
}

/// 详情页的方位：箭头跟着手机罗盘实时转动，文字给出东南西北和“右后方”这样的相对方向
struct LiveDirectionRow: View {
    let spot: Spot
    let distance: Double
    let bearing: Double
    @Environment(LocationService.self) private var location

    var body: some View {
        let heading = location.reliableHeading
        HStack(spacing: 8) {
            if let heading {
                Image(systemName: "location.north.fill")
                    .foregroundStyle(spot.tintColor)
                    .rotationEffect(.degrees(GeoMath.signedDelta(from: heading, to: bearing)))
                    .animation(.interactiveSpring(response: 0.3), value: heading)
                    .accessibilityHidden(true)
            } else {
                Image(systemName: "mappin.and.ellipse").accessibilityHidden(true)
            }
            Text(text(heading: heading))
                .contentTransition(.numericText())
        }
        .font(.callout.monospacedDigit())
        .foregroundStyle(.secondary)
        .accessibilityIdentifier("liveDirection")
    }

    private func text(heading: Double?) -> String {
        let base = L("detail.distance", NearbySearch.formatDistance(distance), Compass.name(bearing))
        guard let heading else { return base }
        let rel = RelativeDirection.of(bearing: bearing, heading: heading)
        return base + " · " + L("relative.\(rel.rawValue)")
    }
}

/// 收起时只显示前几行，点“展开全文”看全部（不打码：来巡礼的人大多知道剧情）
private struct ExpandableText: View {
    let text: String
    let font: Font
    let tint: Color
    let identifier: String
    var collapsedLines = 3
    @State private var expanded = false
    @State private var shownHeight: CGFloat = 0
    @State private var fullHeight: CGFloat = 0

    private var truncated: Bool { fullHeight > shownHeight + 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(text)
                .font(font)
                .lineSpacing(5)
                .lineLimit(expanded ? nil : collapsedLines)
                .fixedSize(horizontal: false, vertical: true)
                .background(GeometryReader { g in
                    Color.clear.preference(key: ShownHeightKey.self, value: g.size.height)
                })
                // 量一下全文高度，判断是否真的被截断，没截断就不显示“展开”
                .background(alignment: .top) {
                    Text(text).font(font).lineSpacing(5)
                        .fixedSize(horizontal: false, vertical: true)
                        .hidden()
                        .background(GeometryReader { g in
                            Color.clear.preference(key: FullHeightKey.self, value: g.size.height)
                        })
                }
                .onPreferenceChange(ShownHeightKey.self) { shownHeight = $0 }
                .onPreferenceChange(FullHeightKey.self) { fullHeight = $0 }
                .accessibilityIdentifier(identifier)
            if truncated || expanded {
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) { expanded.toggle() }
                } label: {
                    Label(expanded ? L("detail.collapse") : L("detail.expand"),
                          systemImage: expanded ? "chevron.up" : "chevron.down")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(tint)
                .accessibilityIdentifier(identifier + "Toggle")
            }
        }
    }

    private struct ShownHeightKey: PreferenceKey {
        static let defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
    }
    private struct FullHeightKey: PreferenceKey {
        static let defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
    }
}

/// “最佳：6月–8月 / Jun–Aug”这样的月份文字（月份名按界面语言）
enum MonthText {
    static func best(_ months: [Int]) -> String {
        let parts = MonthRanges.ranges(months).map { r in
            r.start == r.end ? name(r.start) : name(r.start) + "–" + name(r.end)
        }
        return L("detail.bestMonths", parts.joined(separator: L("month.separator")))
    }

    static func name(_ m: Int) -> String {
        switch AppLanguage.current {
        case "en":
            let f = DateFormatter()
            f.locale = Locale(identifier: "en")
            return f.shortMonthSymbols[(m - 1) % 12]
        case "ko": return "\(m)월"
        default: return "\(m)月"
        }
    }
}

/// “怎么去”的步行小地图：从车站出口 / 巴士站走到机位，点开可以放大
private struct AccessRouteMap: View {
    let spot: Spot
    @State private var route: MKRoute?
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { expanded = true } label: {
                RouteMapContent(spot: spot, route: route, interactive: false)
                    .frame(height: 170)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.caption.bold())
                            .padding(7)
                            .background(.regularMaterial, in: Circle())
                            .padding(8)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("accessRouteMap")
            if let name = spot.accessPointName {
                Label(routeSummary(from: name), systemImage: "figure.walk")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .task(id: spot.id) { route = await WalkingRoutes.shared.route(for: spot) }
        .sheet(isPresented: $expanded) {
            NavigationStack {
                RouteMapContent(spot: spot, route: route, interactive: true)
                    .ignoresSafeArea(edges: .bottom)
                    .navigationTitle(spot.accessPointName ?? L("detail.access"))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) { Button(L("common.done")) { expanded = false } }
                    }
            }
        }
    }

    private func routeSummary(from name: String) -> String {
        if let route {
            let minutes = max(1, Int((route.expectedTravelTime / 60).rounded()))
            return L("detail.walkFrom", name, NearbySearch.formatDistance(route.distance), minutes)
        }
        return L("detail.walkFromShort", name)
    }
}

private struct RouteMapContent: View {
    let spot: Spot
    let route: MKRoute?
    let interactive: Bool

    var body: some View {
        Map(initialPosition: .automatic, interactionModes: interactive ? .all : []) {
            if let route {
                MapPolyline(route.polyline).stroke(spot.tintColor, style: StrokeStyle(lineWidth: 5, lineCap: .round, dash: [1, 8]))
            }
            if let ap = spot.accessPoint {
                Marker(spot.accessPointName ?? "", systemImage: "tram.fill",
                       coordinate: CLLocationCoordinate2D(latitude: ap.latitude, longitude: ap.longitude))
                    .tint(.gray)
            }
            Marker(spot.sceneTitle, systemImage: "camera.fill", coordinate: spot.clCoordinate)
                .tint(spot.tintColor)
            UserAnnotation()
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
    }
}

/// 步行路线缓存（MKDirections 有频率限制，同一个名场面只算一次）
@MainActor
final class WalkingRoutes {
    static let shared = WalkingRoutes()
    private var cache: [String: MKRoute] = [:]

    func route(for spot: Spot) async -> MKRoute? {
        if let hit = cache[spot.id] { return hit }
        guard let ap = spot.accessPoint else { return nil }
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: ap.latitude, longitude: ap.longitude)))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: spot.clCoordinate))
        request.transportType = .walking
        guard let route = try? await MKDirections(request: request).calculate().routes.first else { return nil }
        cache[spot.id] = route
        return route
    }
}

/// 机位小地图：一个点标出站在哪里，扇形标出朝哪个方向拍
private struct ShotMap: View {
    let spot: Spot

    var body: some View {
        Map(initialPosition: .camera(MapCamera(centerCoordinate: spot.clCoordinate, distance: 380, heading: 0, pitch: 0)),
            interactionModes: []) {
            MapPolygon(coordinates: sector)
                .foregroundStyle(spot.tintColor.opacity(0.28))
                .stroke(spot.tintColor, lineWidth: 1.5)
            Annotation("", coordinate: spot.clCoordinate, anchor: .center) {
                Circle().fill(spot.tintColor).frame(width: 14, height: 14)
                    .overlay(Circle().stroke(.white, lineWidth: 2.5))
                    .shadow(radius: 2)
            }
            .annotationTitles(.hidden)
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .frame(height: 150)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityLabel(L("detail.shotMapA11y", Compass.name(spot.sceneHeading)))
        .accessibilityIdentifier("shotMap")
    }

    /// 机位往拍摄方向展开 ±30°、长 70 m 的扇形
    private var sector: [CLLocationCoordinate2D] {
        let c = spot.coordinate
        var pts = [spot.clCoordinate]
        for a in stride(from: -30.0, through: 30.0, by: 6) {
            let p = GeoMath.destination(from: c, bearing: spot.sceneHeading + a, distance: 70)
            pts.append(CLLocationCoordinate2D(latitude: p.latitude, longitude: p.longitude))
        }
        return pts
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

/// 详情页的一个区块：浅色卡片 + 带主题色圆形图标的标题，区块之间层次分明
struct DetailSection<Content: View>: View {
    let title: String
    let systemImage: String
    let tint: Color
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(tint.gradient, in: Circle())
                Text(title).font(.headline)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

private struct InfoRow: View {
    let title: String
    let text: String
    let systemImage: String
    var emphasis: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: systemImage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                if let emphasis { Text(emphasis).font(.callout.weight(.semibold)) }
                if !text.isEmpty {
                    Text(text).font(.callout).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
