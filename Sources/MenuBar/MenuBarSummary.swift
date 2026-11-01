import Foundation

/// 菜单栏与面板显示的汇总。只做展示层的统计，数据都来自已经由 Core 算好的任务、习惯与专注状态。
struct MenuBarSummary: Equatable {
    struct TaskLine: Identifiable, Equatable {
        let id: String
        let title: String
        let remaining: String
        let status: IndicatorStatus
        let isStarred: Bool
        let isCompleted: Bool
    }

    struct FocusDay: Identifiable, Equatable {
        let label: String
        let seconds: Int
        var id: String { label }
    }

    var dueToday = 0
    var overdue = 0
    var activeCount = 0
    var next: TaskLine?
    var nextDueAt: Date?
    var upcoming: [TaskLine] = []
    var habitsDone = 0
    var habitsTotal = 0
    var habits: [HabitItem] = []
    var focusTodaySeconds = 0
    var focusDays: [FocusDay] = []

    /// 需要处理的数量：今天到期 + 已逾期。
    var pending: Int { dueToday + overdue }
    var habitFraction: Double { habitsTotal > 0 ? Double(habitsDone) / Double(habitsTotal) : 0 }

    static func make(tasks: [TaskItem], habits: [HabitItem], today: HabitDay?, focusTodaySeconds: Int,
                     focusDays: [FocusStore.DayPoint], now: Date, calendar: Calendar = .current, upcomingLimit: Int = 6) -> MenuBarSummary {
        var summary = MenuBarSummary()
        let active = tasks.filter { $0.state == .active }
        summary.activeCount = active.count
        summary.overdue = active.filter { ($0.dueAt.map { $0 < now }) ?? false }.count
        summary.dueToday = active.filter { task in
            guard let due = task.dueAt else { return false }
            return due >= now && calendar.isDate(due, inSameDayAs: now)
        }.count

        // 逾期的在前，其余按截止时间；没有截止时间的不进入列表。
        let dated = active.filter { $0.dueAt != nil }.sorted { ($0.dueAt ?? .distantFuture) < ($1.dueAt ?? .distantFuture) }
        summary.upcoming = dated.prefix(upcomingLimit).map { line($0, now: now) }
        if let next = dated.first(where: { ($0.dueAt ?? .distantPast) >= now }) {
            summary.next = line(next, now: now)
            summary.nextDueAt = next.dueAt
        }

        summary.habits = habits
        summary.habitsDone = today?.completed ?? habits.filter(\.isCompleted).count
        summary.habitsTotal = today?.total ?? habits.count
        summary.focusTodaySeconds = focusTodaySeconds
        summary.focusDays = focusDays.map { point in
            let label = HabitDates.date(point.date).map { HabitDates.weekday(HabitDates.string($0)) } ?? point.date
            return FocusDay(label: label.replacingOccurrences(of: "周", with: ""), seconds: point.seconds)
        }
        return summary
    }

    private static func line(_ task: TaskItem, now: Date) -> TaskLine {
        TaskLine(id: task.id, title: task.title, remaining: TaskStatus.remainingText(task, now: now),
                 status: TaskStatus.indicator(task, now: now), isStarred: task.isStarred, isCompleted: task.isCompleted)
    }

    /// 菜单栏「多项数据」中某一项的数值文字。
    func value(for field: StatusField, now: Date) -> String {
        switch field {
        case .today: "\(dueToday)"
        case .overdue: "\(overdue)"
        case .habits: "\(habitsDone)/\(habitsTotal)"
        case .focus: FocusTexts.compact(focusTodaySeconds)
        case .next: nextDueAt.map { TaskStatus.span($0.timeIntervalSince(now)) } ?? "—"
        }
    }
}
