import Foundation

/// 菜单栏项目的设置（存 UserDefaults）。
enum MenuBarSettings {
    static let enabledKey = "menubar.enabled"
    static let styleKey = "menubar.style"
    static let fieldsKey = "menubar.fields"
    static let panelStyleKey = "menubar.panelStyle"
    static let sectionsKey = "menubar.sections"
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
