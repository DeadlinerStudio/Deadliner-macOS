import SwiftUI

/// MIUIX 分组块：圆角 20 的卡片背景，组标题在块外。
struct MiuixGroup<Content: View>: View {
    var title: String?
    @ViewBuilder var content: Content
    @Environment(\.miuix) private var t

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
struct MiuixRow<Trailing: View>: View {
    let title: String
    var systemImage: String?
    var tint: Color?
    @ViewBuilder var trailing: Trailing
    @Environment(\.miuix) private var t

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

/// 填充式输入框：无边框、圆角 16。
struct MiuixTextField: View {
    let placeholder: String
    @Binding var text: String
    var axis: Axis = .horizontal
    var font: Font = .system(size: 14)
    @Environment(\.miuix) private var t
    @FocusState private var focused: Bool

    var body: some View {
        TextField(placeholder, text: $text, axis: axis)
            .textFieldStyle(.plain)
            .font(font)
            .foregroundStyle(t.onSurface)
            .lineLimit(axis == .vertical ? 3...8 : 1...1)
            .focused($focused)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(t.fieldBg, in: RoundedRectangle(cornerRadius: MiuixRadius.field, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: MiuixRadius.field, style: .continuous)
                    .strokeBorder(t.primary.opacity(focused ? 0.45 : 0), lineWidth: 1.5)
            )
    }
}

/// 胶囊按钮：主按钮为主题色填充，次按钮为浅色填充，危险按钮为 Error 色。
struct MiuixButton: View {
    enum Kind { case primary, secondary, destructive }
    let title: String
    var kind: Kind = .secondary
    var action: () -> Void
    @Environment(\.miuix) private var t
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .padding(.horizontal, 20)
                .frame(minWidth: 88, minHeight: 38)
                .foregroundStyle(foreground)
                .background(background, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.45)
    }

    private var foreground: Color {
        switch kind {
        case .primary: .white
        case .secondary: t.onSurface
        case .destructive: t.isDark ? .black : .white
        }
    }

    private var background: Color {
        switch kind {
        case .primary: t.primary
        case .secondary: t.fieldBg
        case .destructive: t.error
        }
    }
}

/// 撞色主页按钮（安卓「撞色主页按钮」：珊瑚红圆形 +）。
struct AccentFab: View {
    let label: String
    var action: () -> Void
    @Environment(\.miuix) private var t
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(t.accentFab, in: Circle())
                .shadow(color: t.accentFab.opacity(0.4), radius: 12, y: 8)
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

/// MIUIX 开关：50×30，开启时轨道为主题色。
struct MiuixToggleStyle: ToggleStyle {
    @Environment(\.miuix) private var t

    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                Capsule()
                    .fill(configuration.isOn ? t.primary : t.onSurfaceVariant.opacity(0.28))
                    .frame(width: 50, height: 30)
                Circle()
                    .fill(.white)
                    .frame(width: 24, height: 24)
                    .shadow(color: .black.opacity(0.15), radius: 1.5, y: 1)
                    .padding(3)
            }
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: configuration.isOn)
        }
        .buttonStyle(.plain)
        .accessibilityValue(configuration.isOn ? "开" : "关")
    }
}

extension ToggleStyle where Self == MiuixToggleStyle {
    static var miuix: MiuixToggleStyle { MiuixToggleStyle() }
}
