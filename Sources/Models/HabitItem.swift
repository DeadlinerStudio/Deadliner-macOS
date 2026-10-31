import Foundation
import Shared

/// 界面使用的习惯快照，来自 Core `HabitPresentationEngine` 为所选日期算好的 `HabitDayStatus`。
struct HabitItem: Identifiable, Equatable {
    enum ActionKind: Equatable { case checkOff, addQuantity }
    enum GoalWindow: String { case scheduledDay = "SCHEDULED_DAY", week = "WEEK", month = "MONTH", lifetime = "LIFETIME" }
    enum ScheduleKind: String { case weeklyDays = "WEEKLY_DAYS", once = "ONCE", algorithm = "ALGORITHM" }

    let id: String
    var name: String
    var note: String
    var colorHex: String?
    var categoryId: String?
    var doneCount: Int
    var targetCount: Int
    var isCompleted: Bool
    var canApplyPrimaryAction: Bool
    var actionKind: ActionKind
    var actionAmount: Int
    var unit: String?
    var goalWindow: GoalWindow
    var scheduleKind: ScheduleKind
    var weekdaysMask: Int?
    /// 所选日期是否需要打卡，以及不需要时的原因（Core `HabitDueReason`）。
    var isDue: Bool
    var dueReason: String
    var hintKind: String?
    var daysUntil: Int?

    var progress: Double { targetCount > 0 ? min(1, Double(doneCount) / Double(targetCount)) : 0 }
}

extension HabitItem {
    init(core status: HabitDayStatus) {
        let habit = status.habit
        let schedule = status.scheduleState
        self.init(
            id: habit.uid,
            name: habit.name,
            note: habit.description_ ?? "",
            colorHex: habit.color.map { Self.hex(fromArgb: $0.intValue) },
            categoryId: habit.categoryUid,
            doneCount: Int(status.doneCount),
            targetCount: Int(status.targetCount),
            isCompleted: status.isCompleted,
            canApplyPrimaryAction: status.canApplyPrimaryAction,
            actionKind: status.primaryAction.kind.name == "ADD_QUANTITY" ? .addQuantity : .checkOff,
            actionAmount: Int(status.primaryAction.amount),
            unit: habit.tracking.unit,
            goalWindow: GoalWindow(rawValue: habit.goal.window.name) ?? .scheduledDay,
            scheduleKind: ScheduleKind(rawValue: habit.schedule.kind.name) ?? .weeklyDays,
            weekdaysMask: habit.schedule.weekdaysMask?.intValue,
            isDue: schedule.isDue,
            dueReason: schedule.reason.name,
            hintKind: schedule.hintKind?.name,
            daysUntil: schedule.daysUntil?.intValue
        )
    }

    /// 习惯颜色在 Core 中是 ARGB 整数。
    static func hex(fromArgb value: Int) -> String {
        String(format: "#%06X", value & 0xFFFFFF)
    }
}

/// 一周概览中的一天（Core `HabitDayOverview`）。
struct HabitDay: Identifiable, Equatable {
    let date: String
    var completed: Int
    var total: Int
    var fraction: Double
    var id: String { date }

    init(date: String, completed: Int, total: Int, fraction: Double) {
        self.date = date
        self.completed = completed
        self.total = total
        self.fraction = fraction
    }

    init(core day: HabitDayOverview_) {
        self.init(date: day.date, completed: Int(day.completedCount), total: Int(day.totalCount), fraction: Double(day.completionRatio))
    }
}
