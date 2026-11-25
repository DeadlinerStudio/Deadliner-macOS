import SwiftUI

/// 菜单栏标签的排版参数（与系统图标对齐用）。
enum StatusLabelLayout {
    /// 内容两侧的留白。
    static let sidePadding: CGFloat = 2
    /// 内容在按钮中的竖直偏移（正数向下）。SF Symbol 与数字的墨迹比几何中心略高，
    /// 下移 1pt 后与相邻系统图标的视觉中线一致。
    static let verticalOffset: CGFloat = 1
}

/// 菜单栏上的内容。颜色使用 `.primary`，随菜单栏的深浅外观变化。
struct StatusLabelView: View {
    let summary: MenuBarSummary
    let style: StatusItemStyle
    let fields: [StatusField]
    let now: Date

    var body: some View {
        Group {
            switch style {
            case .icon:
                glyph
            case .iconCount:
                HStack(spacing: 3) {
                    glyph
                    if summary.pending > 0 {
                        Text("\(summary.pending)")
                            .font(.system(size: 13, weight: .semibold).monospacedDigit())
                            .foregroundStyle(summary.overdue > 0 ? Color.red : Color.primary)
                    }
                }
            case .stats:
                HStack(spacing: 12) {
                    ForEach(fields) { field in
                        VStack(alignment: .leading, spacing: -1) {
                            Text(field.label)
                                .font(.system(size: 8.5, weight: .medium))
                                .foregroundStyle(.secondary)
                            Text(summary.value(for: field, now: now))
                                .font(.system(size: 12.5, weight: .bold).monospacedDigit())
                                .foregroundStyle(field == .overdue && summary.overdue > 0 ? Color.red : Color.primary)
                        }
                    }
                }
            case .capsule:
                HStack(spacing: 5) {
                    Image(systemName: "hourglass")
                        .font(.system(size: 11, weight: .semibold))
                    Text(capsuleText)
                        .font(.system(size: 12, weight: .semibold).monospacedDigit())
                        .lineLimit(1)
                }
                .padding(.horizontal, 9)
                .frame(height: 20)
                .background(Color.primary.opacity(0.12), in: Capsule())
            }
        }
        // 两侧只留很小的空白：菜单栏项目之间本身已有系统间距，再加宽会显得比相邻图标松散。
        .padding(.horizontal, StatusLabelLayout.sidePadding)
        .fixedSize()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var glyph: some View {
        Image(systemName: summary.overdue > 0 ? "calendar.badge.exclamationmark" : "calendar.badge.clock")
            .font(.system(size: 14, weight: .medium))
            .symbolRenderingMode(.hierarchical)
    }

    private var capsuleText: String {
        guard let next = summary.next, let due = summary.nextDueAt else {
            return summary.overdue > 0 ? String(localized: "逾期 \(summary.overdue)") : String(localized: "无待办")
        }
        return "\(next.title.prefix(10)) · \(TaskStatus.span(due.timeIntervalSince(now)))"
    }

    private var accessibilityText: String {
        String(localized: "Deadliner：今天到期 \(summary.dueToday) 个，已逾期 \(summary.overdue) 个，习惯 \(summary.habitsDone)/\(summary.habitsTotal)")
    }
}

/// 读取 AppModel 与设置，每分钟刷新一次。
struct LiveStatusLabel: View {
    let model: AppModel
    @AppStorage(MenuBarSettings.styleKey) private var styleRaw = StatusItemStyle.iconCount.rawValue
    @AppStorage(MenuBarSettings.fieldsKey) private var fieldsRaw = StatusField.encode(StatusField.defaults)

    var body: some View {
        if let running = model.focusTimer.running {
            FocusStatusLabel(running: running)
        } else {
            summaryLabel
        }
    }

    private var summaryLabel: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            StatusLabelView(
                summary: model.menuBarSummary(now: context.date),
                style: StatusItemStyle(rawValue: styleRaw) ?? .iconCount,
                fields: StatusField.decode(fieldsRaw),
                now: context.date
            )
        }
    }
}
