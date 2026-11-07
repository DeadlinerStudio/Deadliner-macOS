import SwiftUI

/// 设置左侧的分类（参照「系统设置」）。选中的分类记在 `storageKey`。
enum SettingsCategory: String, CaseIterable, Identifiable {
    case sync, notifications, backup, menuBar, taskCard, appearance, about

    static let storageKey = "settings.category"
    var id: String { rawValue }

    var title: String {
        switch self {
        case .sync: "同步"
        case .notifications: "通知"
        case .backup: "备份"
        case .menuBar: "菜单栏"
        case .taskCard: "任务卡片"
        case .appearance: "外观"
        case .about: "关于"
        }
    }

    /// 分类标题下的一句说明。
    var subtitle: String {
        switch self {
        case .sync: "通过 WebDAV 与手机同步任务、习惯和专注记录。"
        case .notifications: "任务到期与习惯打卡的系统通知。"
        case .backup: "导出或导入与手机端格式一致的完整备份。"
        case .menuBar: "菜单栏图标与下拉面板的内容。"
        case .taskCard: "任务卡片的进度条、剩余时间与状态颜色。"
        case .appearance: "深浅色、顶部浮光、字体与主题色。"
        case .about: "版本信息与新手引导。"
        }
    }

    var systemImage: String {
        switch self {
        case .sync: "arrow.triangle.2.circlepath"
        case .notifications: "bell.badge.fill"
        case .backup: "externaldrive.fill"
        case .menuBar: "menubar.rectangle"
        case .taskCard: "rectangle.stack.fill"
        case .appearance: "paintpalette.fill"
        case .about: "info"
        }
    }

    var tint: Color {
        switch self {
        case .sync: .blue
        case .notifications: .red
        case .backup: .teal
        case .menuBar: .indigo
        case .taskCard: .orange
        case .appearance: .pink
        case .about: .gray
        }
    }
}

/// 状态颜色与主题色的实时预览：每种状态一张示例任务卡片（只读）。
struct TaskStatusPreview: View {
    var statuses: [IndicatorStatus] = IndicatorStatus.allCases
    @Environment(\.palette) private var t

    var body: some View {
        let now = Date()
        VStack(alignment: .leading, spacing: 8) {
            Text("预览").font(.caption.weight(.semibold)).foregroundStyle(t.onSurfaceVariant)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(statuses) { TaskCard(task: Self.sample($0, now: now), category: nil, now: now) }
            }
        }
        .padding(.vertical, 4)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("任务卡片预览")
    }

    /// 处于指定状态的示例任务（占位内容）。
    static func sample(_ status: IndicatorStatus, now: Date) -> TaskItem {
        let day: TimeInterval = 86400
        let (title, start, due, state, starred): (String, TimeInterval?, TimeInterval, TaskItem.State, Bool) = switch status {
        case .notStarted: ("准备演讲", day * 2, day * 6, .active, false)
        case .undergo: ("阅读论文", nil, day * 4, .active, true)
        case .near: ("提交作业", nil, 3600 * 5, .active, false)
        case .passed: ("整理笔记", nil, -day, .active, false)
        case .completed: ("购买咖啡豆", nil, 60, .completed, false)
        case .completedAhead: ("预习下周课程", day * 2, day * 5, .completed, false)
        case .completedEarly: ("交实验报告", nil, day * 3, .completed, false)
        case .abandoned: ("旧的计划", nil, day, .abandoned, false)
        }
        // 已完成的示例都在「现在」完成：「已完成」示例在截止前一分钟完成（按时完成）。
        return TaskItem(id: "preview-\(status.rawValue)", title: title, note: status.title,
                        startAt: start.map { now.addingTimeInterval($0) }, dueAt: now.addingTimeInterval(due),
                        state: state, isStarred: starred, categoryId: nil, subtaskDone: 0, subtaskTotal: 0,
                        createdAt: now.addingTimeInterval(-day * 3), updatedAt: nil,
                        completedAt: state == .completed ? now : nil)
    }
}
