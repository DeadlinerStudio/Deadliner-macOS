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
        var dueAt: Date?
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
    var focusWeekSeconds = 0
    var focusDays: [FocusDay] = []
    var dueTomorrow = 0
    var dueThisWeek = 0
    var activeToday = 0
    var activeThisWeek = 0
    var pendingThisWeek = 0
    /// 本周结束时间（周一为一周的第一天），用于「即将到期」的范围。
    var weekEnd: Date = .distantFuture

    /// 需要处理的数量：今天到期 + 已逾期。
    var pending: Int { dueToday + overdue }
    var habitFraction: Double { habitsTotal > 0 ? Double(habitsDone) / Double(habitsTotal) : 0 }

    static func make(tasks: [TaskItem], habits: [HabitItem], today: HabitDay?, focusTodaySeconds: Int,
                     focusDays: [FocusStore.DayPoint], now: Date, focusWeekSeconds: Int = 0,
                     calendar: Calendar = .current, upcomingLimit: Int = 50) -> MenuBarSummary {
        var summary = MenuBarSummary()
        let active = tasks.filter { $0.state == .active }
        summary.activeCount = active.count
        summary.overdue = active.filter { ($0.dueAt.map { $0 < now }) ?? false }.count
        summary.dueToday = active.filter { task in
            guard let due = task.dueAt else { return false }
            return due >= now && calendar.isDate(due, inSameDayAs: now)
        }.count

        var weekCalendar = calendar
        weekCalendar.firstWeekday = 2
        let todayStart = calendar.startOfDay(for: now)
        let todayEnd = calendar.date(byAdding: .day, value: 1, to: todayStart) ?? now
        let tomorrowEnd = calendar.date(byAdding: .day, value: 1, to: todayEnd) ?? now
        let week = weekCalendar.dateInterval(of: .weekOfYear, for: now) ?? DateInterval(start: todayStart, end: todayEnd)
        summary.weekEnd = week.end
        func due(_ task: TaskItem, in range: Range<Date>) -> Bool { task.dueAt.map { range.contains($0) } ?? false }
        /// 任务的时间段（开始或创建 → 截止）与区间有重叠。
        func spans(_ task: TaskItem, _ start: Date, _ end: Date) -> Bool {
            let begin = task.startAt ?? task.createdAt ?? .distantPast
            return begin < end && (task.dueAt.map { $0 >= start } ?? true)
        }
        summary.dueTomorrow = active.filter { due($0, in: todayEnd..<tomorrowEnd) }.count
        summary.dueThisWeek = active.filter { due($0, in: now..<max(now, week.end)) }.count
        summary.activeToday = active.filter { spans($0, todayStart, todayEnd) }.count
        summary.activeThisWeek = active.filter { spans($0, week.start, week.end) }.count
        summary.pendingThisWeek = active.filter { ($0.dueAt.map { $0 < week.end }) ?? false }.count
        summary.focusWeekSeconds = focusWeekSeconds

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
                 status: TaskStatus.indicator(task, now: now), isStarred: task.isStarred, isCompleted: task.isCompleted,
                 dueAt: task.dueAt)
    }

    /// 「即将到期」列表在所选范围内的任务。预设范围总是包含已逾期的任务；
    /// 自定义范围只包含截止日期落在范围内的任务。
    func upcoming(in range: UpcomingRange, now: Date, custom: DateRange? = nil, calendar: Calendar = .current) -> [TaskLine] {
        if range == .custom, let custom {
            return upcoming.filter { $0.dueAt.map { custom.contains($0, calendar: calendar) } ?? false }
        }
        let todayStart = calendar.startOfDay(for: now)
        let end: Date? = switch range {
        case .today: calendar.date(byAdding: .day, value: 1, to: todayStart)
        case .threeDays: calendar.date(byAdding: .day, value: 3, to: todayStart)
        case .week: weekEnd
        case .all, .custom: nil
        }
        guard let end else { return upcoming }
        return upcoming.filter { ($0.dueAt ?? .distantFuture) < end }
    }

    /// 面板数据格的数值文字。
    func value(for stat: PanelStat) -> String {
        switch stat {
        case .dueToday: "\(dueToday)"
        case .dueTomorrow: "\(dueTomorrow)"
        case .dueThisWeek: "\(dueThisWeek)"
        case .overdue: "\(overdue)"
        case .active: "\(activeCount)"
        case .activeToday: "\(activeToday)"
        case .activeThisWeek: "\(activeThisWeek)"
        case .pendingThisWeek: "\(pendingThisWeek)"
        case .habits: "\(habitsDone)/\(habitsTotal)"
        case .focusToday: FocusTexts.compact(focusTodaySeconds)
        case .focusThisWeek: FocusTexts.compact(focusWeekSeconds)
        }
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
