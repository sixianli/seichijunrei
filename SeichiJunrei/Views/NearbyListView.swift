import SwiftUI
import SeichiCore

struct NearbyListView: View {
    @Environment(SpotStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let onSelect: (Spot) -> Void

    var body: some View {
        NavigationStack {
            List {
                if store.nearby.isEmpty {
                    // 还没有定位时按作品列出
                    ForEach(store.spots) { spot in
                        row(spot: spot, distance: nil)
                    }
                } else {
                    ForEach(store.nearby) { item in
                        row(spot: item.spot, distance: item.distance)
                    }
                }
            }
            .navigationTitle("全部圣地")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
            }
        }
    }

    private func row(spot: Spot, distance: Double?) -> some View {
        Button { onSelect(spot) } label: {
            HStack {
                SceneArtwork(spot: spot, compact: true)
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading) {
                    Text(spot.sceneTitle).font(.headline)
                    Text("\(spot.work) · \(spot.placeName)").font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer()
                if let d = distance {
                    Text(NearbySearch.formatDistance(d)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
