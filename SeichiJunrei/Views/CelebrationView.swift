import SwiftUI
import SeichiCore

/// 对准名场面时的庆祝画面：“你就是主角！”
struct CelebrationView: View {
    let spot: Spot
    let onCapture: () -> Void
    let onShare: () -> Void
    let onClose: () -> Void

    @State private var appeared = false

    var body: some View {
        ZStack {
            ConfettiView(colors: [spot.tintColor, .white, .yellow, .pink])
                .allowsHitTesting(false)

            // 电影宽银幕：上下黑边，文字和按钮放在下方黑边里，中间留给名场面画面
            VStack(spacing: 0) {
                Rectangle().fill(.black).frame(height: appeared ? 110 : 0)
                Spacer(minLength: 0)
                VStack(spacing: 12) {
                    Text(L("celebrate.title"))
                        .font(.system(size: 28, weight: .heavy, design: .rounded))
                        .accessibilityIdentifier("celebrationTitle")
                    Text(L("celebrate.subtitle", spot.workTitle))
                        .font(.headline)
                        .multilineTextAlignment(.center)
                    Text(spot.quotedSceneTitle)
                        .font(.title3.bold())
                        .foregroundStyle(spot.tintColor)
                        .padding(.horizontal, 12).padding(.vertical, 4)
                        .background(.white, in: Capsule())
                    HStack(spacing: 10) {
                        Button(action: onCapture) {
                            Label(L("celebrate.photo"), systemImage: "camera.fill")
                                .padding(.horizontal, 16).padding(.vertical, 12)
                                .background(spot.tintColor, in: Capsule())
                        }
                        .accessibilityIdentifier("celebratePhoto")
                        Button(action: onShare) {
                            Label(L("share.share"), systemImage: "square.and.arrow.up")
                                .padding(.horizontal, 16).padding(.vertical, 12)
                                .background(Color.white.opacity(0.18), in: Capsule())
                        }
                        .accessibilityIdentifier("celebrateShare")
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    Button(action: onClose) {
                        Text(L("celebrate.continue"))
                            .font(.subheadline)
                            .opacity(0.8)
                    }
                    .font(.headline)
                    .padding(.top, 6)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .padding(.top, 22)
                .padding(.bottom, 44)
                .frame(maxWidth: .infinity)
                .background(.black)
                .offset(y: appeared ? 0 : 320)
            }
            .animation(.spring(response: 0.55, dampingFraction: 0.8), value: appeared)
        }
        .onAppear { appeared = true }
    }
}

/// 轻量级彩纸动画（TimelineView + Canvas，无需第三方库）。
struct ConfettiView: View {
    let colors: [Color]
    // 用 @State 保存，避免父视图每帧重建时彩纸位置被重新随机
    @State private var pieces: [Piece] = (0..<90).map { _ in Piece() }
    @State private var start = Date()

    struct Piece {
        let x = Double.random(in: 0...1)
        let delay = Double.random(in: 0...0.8)
        let speed = Double.random(in: 0.25...0.55)
        let sway = Double.random(in: 10...40)
        let spin = Double.random(in: 2...8)
        let size = Double.random(in: 6...12)
        let colorIndex = Int.random(in: 0..<100)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: Date().timeIntervalSince(start) > 4)) { timeline in
            Canvas { ctx, size in
                let t = timeline.date.timeIntervalSince(start)
                for p in pieces {
                    let life = t - p.delay
                    guard life > 0 else { continue }
                    let y = CGFloat(life * p.speed) * size.height - 20
                    guard y < size.height + 20 else { continue }
                    let x = CGFloat(p.x) * size.width + CGFloat(sin(life * 3 + p.x * 10) * p.sway)
                    var c = ctx
                    c.translateBy(x: x, y: y)
                    c.rotate(by: .radians(life * p.spin))
                    let s = CGFloat(p.size)
                    let rect = CGRect(x: -s / 2, y: -s / 4, width: s, height: s / 2)
                    c.fill(Path(rect), with: .color(colors[p.colorIndex % colors.count]))
                }
            }
        }
    }
}
