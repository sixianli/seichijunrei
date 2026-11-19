import SwiftUI
import SeichiCore

/// 按作品浏览 / 搜索全部名场面。
struct NearbyListView: View {
    @Environment(SpotStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let onSelect: (Spot) -> Void

    @State private var query = ""
    @State private var mediaFilter: MediaCategory?

    private var results: [SpotSearch.WorkMatch] {
        SpotSearch.search(query, in: store.spots, category: mediaFilter)
    }

    var body: some View {
        NavigationStack {
            List {
                Picker(L("list.type"), selection: $mediaFilter) {
                    Text(L("map.all")).tag(MediaCategory?.none)
                    ForEach(MediaCategory.allCases, id: \.self) { Text($0.label).tag(MediaCategory?.some($0)) }
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
                        WorkHeader(match: match)
                    }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: Text(L("list.searchPrompt")))
            .navigationTitle(L("map.allScenes"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button(L("common.done")) { dismiss() } }
            }
        }
    }

    private func row(_ item: NearbySpot) -> some View {
        Button { onSelect(item.spot) } label: {
            HStack {
                SceneArtwork(spot: item.spot, compact: true, useLocationPhoto: true)
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading) {
                    if let n = item.spot.sceneNumberLabel {
                        Text(n).font(.caption2.weight(.semibold)).foregroundStyle(item.spot.tintColor)
                    }
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

/// 作品分组标题：封面 + 当前语言的作品名（上）+ 原名（下）
private struct WorkHeader: View {
    let match: SpotSearch.WorkMatch

    var body: some View {
        HStack(spacing: 10) {
            CategoryIcon(category: match.mediaType.category, size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(match.spots.first?.workBadge ?? match.work)
                    .font(.subheadline.bold())
                    .foregroundStyle(.primary)
                if let original = match.spots.first?.originalWorkName {
                    Text(original).font(.caption).foregroundStyle(.secondary)
                }
            }
            .lineLimit(2)
            .textCase(nil)
            Spacer()
            Text(sceneCountText(match.spots.count))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(nil)
        }
        .padding(.vertical, 2)
    }
}
