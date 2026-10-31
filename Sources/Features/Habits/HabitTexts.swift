import Foundation

/// 习惯卡片上的文字。内容来自 Core 已算好的状态，这里只负责转成中文。
enum HabitTexts {
    /// 卡片右上角：需要打卡时显示周期，不需要时显示原因。
    static func side(_ habit: HabitItem) -> String {
        if habit.isDue { return schedule(habit) }
        switch habit.hintKind {
        case "STARTS_IN": return habit.daysUntil.map { "\($0) 天后开始" } ?? "尚未开始"
        case "NEXT_REVIEW_IN": return habit.daysUntil.map { "\($0) 天后复习" } ?? "今天不需复习"
        case "COMPLETED_CYCLE": return "本轮已完成"
        default: break
        }
        switch habit.dueReason {
        case "BEFORE_START": return "尚未开始"
        case "AFTER_END": return "已结束"
        case "WEEKDAY_NOT_SELECTED": return "今天不需打卡"
        case "ALGORITHM_NOT_DUE": return "今天不需复习"
        default: return ""
        }
    }

    static func schedule(_ habit: HabitItem) -> String {
        switch habit.scheduleKind {
        case .once: return "一次"
        case .algorithm: return "复习计划"
        case .weeklyDays:
            guard let mask = habit.weekdaysMask, mask != 0, mask != 0b111_1111 else { return "每天" }
            let names = ["一", "二", "三", "四", "五", "六", "日"]
            let days = names.enumerated().filter { mask & (1 << $0.offset) != 0 }.map(\.element)
            return mask == 0b001_1111 ? "工作日" : "每周" + days.joined(separator: "、")
        }
    }

    /// 目标进度，例如「本周 2/3 次」「1500/2000 ml」。
    static func progress(_ habit: HabitItem) -> String {
        let unit = habit.unit.map { " \($0)" } ?? (habit.actionKind == .checkOff ? " 次" : "")
        let prefix: String = switch habit.goalWindow {
        case .scheduledDay: ""
        case .week: "本周 "
        case .month: "本月 "
        case .lifetime: "累计 "
        }
        return "\(prefix)\(habit.doneCount)/\(habit.targetCount)\(unit)"
    }

    /// 打卡按钮的说明。
    static func actionHelp(_ habit: HabitItem) -> String {
        if !habit.canApplyPrimaryAction { return habit.isDue ? "这一天不能打卡" : side(habit) }
        if habit.isCompleted { return "再次点击会清除这一周期的记录" }
        return habit.actionKind == .addQuantity ? "记录 +\(habit.actionAmount)\(habit.unit ?? "")" : "打卡"
    }
}
