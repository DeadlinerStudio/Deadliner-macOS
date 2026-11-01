import SwiftUI

/// 分组块：圆角 20、系统控件背景，组标题在块外（用于卡片页面中的少量列表，例如归档的习惯）。
struct GroupedSection<Content: View>: View {
    var title: String?
    @ViewBuilder var content: Content
    @Environment(\.palette) private var t

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(t.onSurfaceVariant)
                    .padding(.leading, 14)
            }
            VStack(alignment: .leading, spacing: 0) { content }
                .padding(.vertical, 6)
                .background(t.groupBg, in: RoundedRectangle(cornerRadius: MiuixRadius.group, style: .continuous))
        }
    }
}

/// 分组内的一行：左侧标题，右侧控件。
struct GroupedRow<Trailing: View>: View {
    let title: String
    var systemImage: String?
    var tint: Color?
    @ViewBuilder var trailing: Trailing
    @Environment(\.palette) private var t

    var body: some View {
        HStack(spacing: 12) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(tint ?? t.primary, in: Circle())
            }
            Text(title)
                .font(.system(size: 14))
                .foregroundStyle(t.onSurface)
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 44)
    }
}

/// 撞色「+」按钮（安卓「撞色主页按钮」）：珊瑚色玻璃圆形。
struct AccentFab: View {
    let label: String
    var action: () -> Void
    @Environment(\.palette) private var t
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .contentShape(Circle())
                // 着色留出透明度，让背后的内容透过来；不另加彩色阴影（阴影透过玻璃会显脏）。
                .deadlinerGlass(in: Circle(), tint: t.accentFab.opacity(0.72), interactive: true)
                .scaleEffect(hovering ? 1.05 : 1)
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }
}

/// 自动换行的横向排列（分类标签、图标选择）。
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private struct Row { var indices: [Int] = []; var y: CGFloat = 0; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            var row = rows[rows.count - 1]
            if !row.indices.isEmpty && row.width + spacing + size.width > width {
                let y = row.y + row.height + spacing
                rows.append(Row(y: y))
                row = rows[rows.count - 1]
            }
            row.width += (row.indices.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows
    }
}
