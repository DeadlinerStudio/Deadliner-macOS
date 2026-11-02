import Foundation

/// 菜单栏项目的设置（存 UserDefaults）。
enum MenuBarSettings {
    static let enabledKey = "menubar.enabled"
    static let styleKey = "menubar.style"
    static let fieldsKey = "menubar.fields"
    static let panelStyleKey = "menubar.panelStyle"
    static let sectionsKey = "menubar.sections"
    static let focusChartKey = "menubar.focusChart"
    static let statsKey = "menubar.stats"
    static let upcomingRangeKey = "menubar.upcomingRange"
    static let upcomingCustomRangeKey = "menubar.upcomingCustomRange"
}

/// 面板顶部的数据格（最多 4 个）。
enum PanelStat: String, CaseIterable, Identifiable {
    case dueToday, dueTomorrow, dueThisWeek, overdue
    case active, activeToday, activeThisWeek, pendingThisWeek
    case habits, focusToday, focusThisWeek

    var id: String { rawValue }
    static let maxCount = 4
    static let defaults: [PanelStat] = [.dueToday, .overdue, .active, .focusToday]

    var title: String {
        switch self {
        case .dueToday: "今天到期"
        case .dueTomorrow: "明天到期"
        case .dueThisWeek: "本周到期"
        case .overdue: "已逾期"
        case .active: "进行中"
        case .activeToday: "今日进行中"
        case .activeThisWeek: "本周进行中"
        case .pendingThisWeek: "本周待完成"
        case .habits: "今日习惯"
        case .focusToday: "今日专注"
        case .focusThisWeek: "本周专注"
        }
    }

    /// 设置中的说明。
    var detail: String {
        switch self {
        case .dueToday: "今天剩余时间内到期的任务"
        case .dueTomorrow: "明天到期的任务"
        case .dueThisWeek: "从现在到本周日结束前到期的任务"
        case .overdue: "已过截止时间、尚未完成的任务"
        case .active: "所有未完成、未放弃的任务"
        case .activeToday: "时间段（开始到截止）覆盖今天的任务"
        case .activeThisWeek: "时间段（开始到截止）覆盖本周的任务"
        case .pendingThisWeek: "本周日结束前到期、尚未完成的任务（含已逾期）"
        case .habits: "今天已完成 / 需要完成的习惯"
        case .focusToday: "今天的专注时长"
        case .focusThisWeek: "本周（周一起）的专注时长"
        }
    }

    static func decode(_ raw: String?) -> [PanelStat] {
        guard let raw else { return defaults }
        return raw.split(separator: ",").compactMap { PanelStat(rawValue: String($0)) }
    }

    static func encode(_ stats: [PanelStat]) -> String { stats.map(\.rawValue).joined(separator: ",") }
}

/// 「即将到期」列表的时间范围（逾期的任务始终显示）。
enum UpcomingRange: String, CaseIterable, Identifiable {
    case today, threeDays, week, all, custom
    var id: String { rawValue }
    var title: String {
        switch self {
        case .today: "今天"
        case .threeDays: "3 天内"
        case .week: "本周"
        case .all: "全部"
        case .custom: "自定义"
        }
    }
}

/// 面板中「最近 7 天专注」的排列方向。
enum FocusChartOrientation: String, CaseIterable, Identifiable {
    /// 竖向柱子，日期在下方。
    case vertical
    /// 横向条，每天一行，右侧显示时长。
    case horizontal

    var id: String { rawValue }
    var title: String {
        switch self {
        case .vertical: "竖向"
        case .horizontal: "横向"
        }
    }
}

/// 菜单栏上显示的样式。
enum StatusItemStyle: String, CaseIterable, Identifiable {
    /// 只显示图标。
    case icon
    /// 图标 + 待处理数量（今天到期 + 已逾期）。
    case iconCount
    /// 多项小数据横排（上方小字标签、下方数值）。
    case stats
    /// 胶囊：图标 + 下一个截止的剩余时间。
    case capsule

    var id: String { rawValue }

    var title: String {
        switch self {
        case .icon: "只显示图标"
        case .iconCount: "图标和数量"
        case .stats: "多项数据"
        case .capsule: "胶囊（下一个截止）"
        }
    }
}

/// 「多项数据」样式中可选的数据项。
enum StatusField: String, CaseIterable, Identifiable {
    case today, overdue, habits, focus, next

    var id: String { rawValue }

    /// 菜单栏上方的小字标签。
    var label: String {
        switch self {
        case .today: "今日"
        case .overdue: "逾期"
        case .habits: "习惯"
        case .focus: "专注"
        case .next: "下一个"
        }
    }

    /// 设置中的说明。
    var title: String {
        switch self {
        case .today: "今天到期的任务数"
        case .overdue: "已逾期的任务数"
        case .habits: "今日习惯完成情况"
        case .focus: "今日专注时长"
        case .next: "下一个截止的剩余时间"
        }
    }

    static let defaults: [StatusField] = [.today, .overdue, .habits]

    /// 以逗号分隔的存储值 ↔ 有序字段列表。
    static func decode(_ raw: String) -> [StatusField] {
        let fields = raw.split(separator: ",").compactMap { StatusField(rawValue: String($0)) }
        return fields.isEmpty ? defaults : fields
    }

    static func encode(_ fields: [StatusField]) -> String { fields.map(\.rawValue).joined(separator: ",") }
}

/// 点开后的面板风格。
enum PanelStyle: String, CaseIterable, Identifiable {
    /// 仪表盘：完成度圆环、数据块、本周专注柱状图。
    case dashboard
    /// 列表菜单：任务与习惯列表，下方是菜单项。
    case list

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: "仪表盘"
        case .list: "列表菜单"
        }
    }
}

/// 面板中可选的模块。
enum PanelSection: String, CaseIterable, Identifiable {
    case overview, tasks, habits, focusChart, quickAdd, sync

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "今日概况"
        case .tasks: "即将到期的任务"
        case .habits: "今日习惯"
        case .focusChart: "最近 7 天专注"
        case .quickAdd: "快速新建"
        case .sync: "同步状态"
        }
    }

    static let defaults: [PanelSection] = [.overview, .tasks, .habits, .focusChart, .quickAdd, .sync]

    static func decode(_ raw: String?) -> [PanelSection] {
        guard let raw else { return defaults }
        return raw.split(separator: ",").compactMap { PanelSection(rawValue: String($0)) }
    }

    static func encode(_ sections: [PanelSection]) -> String { sections.map(\.rawValue).joined(separator: ",") }
}
