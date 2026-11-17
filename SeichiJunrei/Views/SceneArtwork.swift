import SwiftUI
import UIKit
import SeichiCore

/// 名场面画面。sceneImage 可以是 Asset 名称或 https URL；
/// 没有授权图片时显示插画风占位图（请勿随意打包未经授权的动画截图）。
struct SceneArtwork: View {
    let spot: Spot
    var compact = false

    var body: some View {
        Group {
            if let userImage = SceneImageStore.shared.image(for: spot.id) {
                Image(uiImage: userImage).resizable().scaledToFill()
            } else if let src = spot.sceneImage, src.hasPrefix("http"), let url = URL(string: src) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image): image.resizable().scaledToFill()
                    default: placeholder
                    }
                }
            } else if let name = spot.sceneImage, UIImage(named: name) != nil {
                Image(name).resizable().scaledToFill()
            } else {
                placeholder
            }
        }
        .clipped()
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(colors: [spot.tintColor.opacity(0.95), spot.tintColor.opacity(0.45), .black.opacity(0.85)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            // 胶片齿孔装饰
            VStack {
                filmStrip
                Spacer()
                filmStrip
            }
            VStack(spacing: compact ? 4 : 10) {
                Image(systemName: "film.stack")
                    .font(compact ? .title3 : .system(size: 44, weight: .light))
                Text(spot.sceneTitle)
                    .font(compact ? .caption.bold() : .title2.bold())
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                if !compact {
                    Text(spot.work).font(.subheadline).opacity(0.85)
                }
            }
            .foregroundStyle(.white)
            .padding()
        }
    }

    private var filmStrip: some View {
        HStack(spacing: compact ? 6 : 10) {
            ForEach(0..<14, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(.white.opacity(0.25))
                    .frame(width: compact ? 5 : 9, height: compact ? 4 : 7)
            }
        }
        .padding(.vertical, compact ? 4 : 8)
    }
}
