import SwiftUI
import SeichiCore

/// 对准名场面时的庆祝画面：“你就是主角！”
struct CelebrationView: View {
    let spot: Spot
    let onCapture: () -> Void
    let onClose: () -> Void

    @State private var appeared = false

    var body: some View {
        ZStack {
            // 电影宽银幕黑边
            VStack {
                Rectangle().fill(.black).frame(height: appeared ? 120 : 0)
                Spacer()
                Rectangle().fill(.black).frame(height: appeared ? 220 : 0)
            }
            .animation(.easeOut(duration: 0.6), value: appeared)

            ConfettiView(colors: [spot.tintColor, .white, .yellow, .pink])
                .allowsHitTesting(false)

            VStack(spacing: 14) {
                Spacer()
                Text("✨ 就是这个画面！✨")
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                Text("此刻，你就是《\(spot.work)》的主角")
                    .font(.headline)
                Text("「\(spot.sceneTitle)」")
                    .font(.title3.bold())
                    .foregroundStyle(spot.tintColor)
                    .padding(.horizontal, 12).padding(.vertical, 4)
                    .background(.white, in: Capsule())
                Spacer()
                HStack(spacing: 14) {
                    Button(action: onCapture) {
                        Label("拍照留念", systemImage: "camera.fill")
                            .padding(.horizontal, 18).padding(.vertical, 12)
                            .background(spot.tintColor, in: Capsule())
                    }
                    Button(action: onClose) {
                        Text("继续欣赏")
                            .padding(.horizontal, 18).padding(.vertical, 12)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                }
                .font(.headline)
                .padding(.bottom, 70)
            }
            .foregroundStyle(.white)
            .shadow(radius: 6)
            .scaleEffect(appeared ? 1 : 0.85)
            .opacity(appeared ? 1 : 0)
            .animation(.spring(response: 0.5, dampingFraction: 0.65), value: appeared)
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
