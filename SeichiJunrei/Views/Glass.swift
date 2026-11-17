import SwiftUI

// Liquid Glass 适配层
//
// 遵循 Apple Human Interface Guidelines（Materials / Liquid Glass）：
// - 玻璃只用于“浮在内容之上的控制层”（导航、浮动按钮、相机取景上的控件），内容本身保持实底；
// - 不要玻璃叠玻璃；相邻的玻璃元素放进同一个 GlassEffectContainer，共享采样区域；
// - 色调（tint）只用于需要强调的主要操作；
// - 降低透明度 / 增强对比度等辅助功能由系统玻璃自动适配。
//
// iOS 26 起提供 Liquid Glass（iOS 27 沿用同一套 API，并由系统渲染其改进后的效果）；
// 更早的系统退回到 Material，保持相近的层级关系。

extension View {
    /// 控制层玻璃表面
    @ViewBuilder
    func glassSurface<S: Shape>(_ shape: S, tint: Color? = nil, interactive: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(Self.makeGlass(tint: tint, interactive: interactive), in: shape)
        } else if let tint {
            self.background(tint.opacity(0.88), in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
        }
    }

    @available(iOS 26.0, *)
    private static func makeGlass(tint: Color?, interactive: Bool) -> Glass {
        var glass = Glass.regular
        if let tint { glass = glass.tint(tint) }
        if interactive { glass = glass.interactive() }
        return glass
    }

    /// 玻璃按钮：prominent 用于主要操作（带色调），否则为次要操作
    @ViewBuilder
    func glassButton(prominent: Bool = false, tint: Color? = nil) -> some View {
        if #available(iOS 26.0, *) {
            if prominent {
                self.buttonStyle(.glassProminent).tint(tint)
            } else {
                self.buttonStyle(.glass).tint(tint)
            }
        } else if prominent {
            self.buttonStyle(.borderedProminent).tint(tint)
        } else {
            self.buttonStyle(.bordered).tint(tint)
        }
    }
}

/// 把相邻的玻璃元素放进同一个容器（iOS 26+），旧系统直接显示内容
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = 8
    @ViewBuilder var content: Content

    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}

extension View {
    /// HIG：可点击区域至少 44×44pt
    func minimumHitTarget() -> some View {
        frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
    }
}
