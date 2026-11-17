import SwiftUI
import SeichiCore

/// 按作品浏览 / 搜索全部名场面。
struct NearbyListView: View {
    @Environment(SpotStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let onSelect: (Spot) -> Void

    @State private var query = ""
    @State private var mediaFilter: MediaType?

    private var results: [SpotSearch.WorkMatch] {
        SpotSearch.search(query, in: store.spots, mediaType: mediaFilter)
    }

    var body: some View {
        NavigationStack {
            List {
                Picker("类型", selection: $mediaFilter) {
                    Text("全部").tag(MediaType?.none)
                    ForEach(MediaType.allCases, id: \.self) { Text($0.label).tag(MediaType?.some($0)) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)

                if results.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
                ForEach(results) { match in
                    Section {
                        ForEach(store.items(for: match.spots)) { item in
                            row(item)
                        }
                    } header: {
                        HStack {
                            Label(match.work, systemImage: match.mediaType.symbolName)
                            if let cn = match.workLocalized {
                                Text(cn).foregroundStyle(.secondary)
                            }
                        }
                        .lineLimit(1)
                    }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "动画 / 电影 / 电视剧名称")
            .navigationTitle("全部名场面")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
            }
        }
    }

    private func row(_ item: NearbySpot) -> some View {
        Button { onSelect(item.spot) } label: {
            HStack {
                SceneArtwork(spot: item.spot, compact: true)
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading) {
                    Text(item.spot.sceneTitle).font(.headline)
                    Text(item.spot.placeName).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer()
                if item.distance.isFinite {
                    Text(NearbySearch.formatDistance(item.distance))
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
