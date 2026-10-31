import SwiftUI

/// 手机端共享的分类图标语义 ID → SF Symbols。
enum CategoryIcons {
    static let symbols: [String: String] = [
        "folder": "folder", "inbox_tray": "tray", "briefcase": "briefcase", "office_building": "building.2",
        "book": "book", "education": "graduationcap", "edit": "pencil", "home": "house",
        "shopping": "cart", "dining": "fork.knife", "coffee": "cup.and.saucer", "health": "heart",
        "medical": "stethoscope", "running": "figure.run", "fitness": "dumbbell", "payment_card": "creditcard",
        "cash": "banknote", "analytics": "chart.bar", "group": "person.3", "family": "figure.2.and.child.holdinghands",
        "creativity": "paintpalette", "camera": "camera", "music": "music.note", "reading": "book.closed",
        "inspiration": "sparkles", "calendar": "calendar", "time": "clock", "flag": "flag",
        "idea": "lightbulb", "travel": "globe", "flight": "airplane", "gaming": "gamecontroller",
        "tools": "wrench.and.screwdriver", "construction": "hammer", "nature": "leaf", "tag": "tag",
    ]

    static func symbol(for key: String) -> String { symbols[key] ?? "folder" }
}

/// 分类小标签：图标 + 名称，使用分类色的浅色底（对齐安卓卡片元数据行，最宽 128）。
struct CategoryChip: View {
    let category: CategoryItem
    @Environment(\.miuix) private var t

    var body: some View {
        let color = Color(hexString: category.colorHex) ?? t.primary
        HStack(spacing: 4) {
            Image(systemName: CategoryIcons.symbol(for: category.iconKey))
                .font(.system(size: 10, weight: .semibold))
            Text(category.name)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .font(.system(size: 11.5, weight: .semibold))
        .foregroundStyle(color)
        .padding(.horizontal, 6)
        .frame(height: 20)
        .background(color.opacity(t.isDark ? 0.22 : 0.14), in: RoundedRectangle(cornerRadius: 10))
        .modifier(MaxWidth(128))
    }
}

/// 只限制最大宽度、按内容收缩（`.frame(maxWidth:)` 在 HStack 里会撑满到上限）。
struct MaxWidth: ViewModifier {
    let limit: CGFloat
    init(_ limit: CGFloat) { self.limit = limit }

    func body(content: Content) -> some View {
        MaxWidthLayout(limit: limit) { content }
    }
}

private struct MaxWidthLayout: Layout {
    let limit: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let child = subviews.first else { return .zero }
        let width = min(proposal.width ?? limit, limit)
        return child.sizeThatFits(ProposedViewSize(width: width, height: proposal.height))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(width: bounds.width, height: bounds.height))
    }
}

/// 小胶囊（子任务进度、打卡次数等）。
struct CountPill: View {
    let text: String
    @Environment(\.miuix) private var t

    var body: some View {
        Text(text)
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(t.onSurfaceVariant)
            .padding(.horizontal, 6)
            .frame(height: 20)
            .background((t.isDark ? Color.white : Color.black).opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
            .fixedSize()
    }
}
