import Foundation

/// 完成时机：只在 Mac 上由开始时间、截止时间和完成时间推算，不写回数据，不影响同步和手机。
/// 完成时间是勾选完成的那一刻（Core 的 `completedAt`）；取消完成后清空，归档后保留。
/// 四种互不重叠：
/// - 超前完成：开始时间还没到就完成；
/// - 提前完成：开始后完成，且比截止日早至少一天（按本地日期）；
/// - 按时完成：截止当天、截止时间之前完成；
/// - 逾期完成：截止时间之后才完成。
/// 没有截止时间、也不是超前完成的任务没有完成时机。
enum CompletionTiming: String, CaseIterable, Identifiable {
    case ahead, early, onTime, late

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ahead: "超前完成"
        case .early: "提前完成"
        case .onTime: "按时完成"
        case .late: "逾期完成"
        }
    }

    /// 卡片和图表使用的状态色（超前、提前可以在设置中自定义颜色）。
    var status: IndicatorStatus {
        switch self {
        case .ahead: .completedAhead
        case .early: .completedEarly
        case .onTime: .completed
        case .late: .passed
        }
    }

}

extension IndicatorStatus {
    /// 已完成卡片的状态：超前、提前完成用各自的颜色，按时、逾期完成仍是「已完成」。
    var completedVariant: IndicatorStatus {
        self == .completedAhead || self == .completedEarly ? self : .completed
    }
}

extension CompletionTiming {
    static func of(_ task: TaskItem, calendar: Calendar = .current) -> CompletionTiming? {
        guard task.isCompleted, let done = task.completedAt else { return nil }
        if let start = task.startAt, done < start { return .ahead }
        guard let due = task.dueAt else { return nil }
        if done > due { return .late }
        return calendar.startOfDay(for: done) < calendar.startOfDay(for: due) ? .early : .onTime
    }

    /// 完成日比截止日早几天（按本地日期）；没有截止时间时为 nil。
    static func daysBeforeDue(_ task: TaskItem, calendar: Calendar = .current) -> Int? {
        guard let done = task.completedAt, let due = task.dueAt else { return nil }
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: done), to: calendar.startOfDay(for: due)).day
    }

    /// 每种完成时机的数量（只统计完成时间在 `[start, end)` 内的任务）。
    static func counts(_ tasks: [TaskItem], from start: Date, to end: Date) -> [CompletionTiming: Int] {
        var result: [CompletionTiming: Int] = [:]
        for task in tasks {
            guard let done = task.completedAt, done >= start, done < end, let timing = of(task) else { continue }
            result[timing, default: 0] += 1
        }
        return result
    }
}
