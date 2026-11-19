import SwiftUI

/// 从左到右排，一行放不下就换到下一行。比一行宽的子视图会按整行宽度排（它自己折行），
/// 所以任何语言下都不会有文字超出屏幕。
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.reduce(0) { $0 + $1.height } + lineSpacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: proposal.width.map { min($0, width) } ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for item in row.items {
                subviews[item.index].place(at: CGPoint(x: x, y: y + (row.height - item.size.height) / 2),
                                           proposal: ProposedViewSize(item.size))
                x += item.size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Item { let index: Int; let size: CGSize }
    private struct Row { var items: [Item] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width maxWidth: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for (i, sub) in subviews.enumerated() {
            var size = sub.sizeThatFits(.unspecified)
            if size.width > maxWidth {
                size = sub.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
                size.width = min(size.width, maxWidth)
            }
            let needed = row.items.isEmpty ? size.width : row.width + spacing + size.width
            if !row.items.isEmpty && needed > maxWidth {
                rows.append(row)
                row = Row()
            }
            row.width = row.items.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.items.append(Item(index: i, size: size))
        }
        if !row.items.isEmpty { rows.append(row) }
        return rows
    }
}

/// 几个等宽按钮：每个按钮的文字都能在等分后的宽度里完整放下就并排，否则上下排（每个占满一行）
struct EqualColumnsOrStack: Layout {
    var spacing: CGFloat = 10
    var stackSpacing: CGFloat = 8

    private func fitsSideBySide(width: CGFloat, subviews: Subviews) -> Bool {
        guard !subviews.isEmpty, width.isFinite else { return true }
        let widest = subviews.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0
        return widest * CGFloat(subviews.count) + spacing * CGFloat(subviews.count - 1) <= width
    }

    private func columnWidth(_ width: CGFloat, _ n: Int) -> CGFloat {
        (width - spacing * CGFloat(n - 1)) / CGFloat(n)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let n = subviews.count
        guard n > 0 else { return .zero }
        let width = proposal.width ?? .infinity
        if fitsSideBySide(width: width, subviews: subviews) {
            let w = width.isFinite ? width : subviews.map { $0.sizeThatFits(.unspecified).width }.reduce(0, +)
                + spacing * CGFloat(n - 1)
            let col = columnWidth(w, n)
            let h = subviews.map { $0.sizeThatFits(ProposedViewSize(width: col, height: nil)).height }.max() ?? 0
            return CGSize(width: w, height: h)
        }
        let heights = subviews.map { $0.sizeThatFits(ProposedViewSize(width: width, height: nil)).height }
        return CGSize(width: width, height: heights.reduce(0, +) + stackSpacing * CGFloat(n - 1))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let n = subviews.count
        guard n > 0 else { return }
        if fitsSideBySide(width: bounds.width, subviews: subviews) {
            let col = columnWidth(bounds.width, n)
            for (i, sub) in subviews.enumerated() {
                sub.place(at: CGPoint(x: bounds.minX + CGFloat(i) * (col + spacing), y: bounds.minY),
                          proposal: ProposedViewSize(width: col, height: bounds.height))
            }
        } else {
            var y = bounds.minY
            for sub in subviews {
                let h = sub.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil)).height
                sub.place(at: CGPoint(x: bounds.minX, y: y), proposal: ProposedViewSize(width: bounds.width, height: h))
                y += h + stackSpacing
            }
        }
    }
}
