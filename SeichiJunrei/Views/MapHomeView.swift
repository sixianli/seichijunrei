import SwiftUI
import UIKit
import MapKit
import SeichiCore

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

    /// 当前已经站在名场面位置的圣地（最近的一个）
    private var arrivedSpot: NearbySpot? {
        store.nearby.first { $0.hasArrived(accuracy: location.lastLocation?.horizontalAccuracy ?? 0) }
    }

    var body: some View {
        Map(position: $camera) {
            UserAnnotation()
            ForEach(store.spots) { spot in
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
        .safeAreaInset(edge: .top) {
            VStack(spacing: 8) {
                PermissionBanner()
                if let arrived = arrivedSpot {
                    ArrivalBanner(nearby: arrived) { sceneSpot = arrived.spot }
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .padding(.horizontal)
            .animation(.spring, value: arrivedSpot?.id)
        }
        .safeAreaInset(edge: .bottom) {
            NearbyCarousel(items: store.nearbyWithinRadius.isEmpty
                           ? Array(store.nearby.prefix(10)) : store.nearbyWithinRadius,
                           isFallback: store.nearbyWithinRadius.isEmpty) { selected = $0 }
        }
        .navigationTitle("圣地巡礼")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showList = true } label: { Image(systemName: "list.bullet") }
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
                selected = spot
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
                Image(systemName: "sparkles.tv.fill")
                    .font(.system(size: 16, weight: .bold))
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
                    .symbolEffect(.bounce, options: .repeating)
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
    }
}

private struct PermissionBanner: View {
    @Environment(LocationService.self) private var location

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
        case .authorizedWhenInUse:
            Button { location.requestAlwaysAuthorization() } label: {
                Label("开启“始终允许”定位，靠近圣地时提醒你", systemImage: "bell.badge")
                    .font(.caption)
                    .padding(8)
                    .frame(maxWidth: .infinity)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        default:
            EmptyView()
        }
    }
}

private struct NearbyCarousel: View {
    let items: [NearbySpot]
    let isFallback: Bool
    let onSelect: (Spot) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(isFallback ? "离你最近的圣地" : "附近的名场面")
                .font(.headline)
                .padding(.horizontal)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(items) { item in
                        SpotCard(item: item).onTapGesture { onSelect(item.spot) }
                    }
                }
                .padding(.horizontal)
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
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
                Label(NearbySearch.formatDistance(item.distance), systemImage: "location.north.line")
                    .font(.caption)
                    .foregroundStyle(item.spot.tintColor)
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(width: 260)
        .background(.background, in: RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
    }
}
