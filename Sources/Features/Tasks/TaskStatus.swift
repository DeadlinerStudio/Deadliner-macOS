import Foundation

/// 卡片的状态、进度与剩余时间文字（对齐安卓 DeadlineStatusResolver 与主界面卡片）。
///
/// 进度：手机的「主界面正向进度条」关闭，所以显示剩余时间比例——
/// 未开始为满格，越接近截止越短，逾期为空。
enum TaskStatus {
    /// 剩余不足 24 小时视为即将到期。
    static let nearThreshold: TimeInterval = 24 * 3600

    static func indicator(_ task: TaskItem, now: Date) -> IndicatorStatus {
        if task.isAbandoned { return .abandoned }
        if task.isCompleted { return .completed }
        guard let due = task.dueAt else { return .undergo }
        if now > due { return .passed }
        if due.timeIntervalSince(now) <= nearThreshold { return .near }
        return .undergo
    }

    /// 剩余时间比例，范围 0...1。
    static func remainingProgress(_ task: TaskItem, now: Date) -> Double {
        if task.isAbandoned || task.isCompleted { return 0 }
        guard let due = task.dueAt, now < due else { return 0 }
        if let start = task.startAt, now < start { return 1 }
        guard let begin = task.startAt ?? task.createdAt, due > begin else { return 1 }
        return min(1, max(0, due.timeIntervalSince(now) / due.timeIntervalSince(begin)))
    }

    /// 卡片右上角的文字。
    static func remainingText(_ task: TaskItem, now: Date) -> String {
        if task.isAbandoned { return "已放弃" }
        if task.isCompleted { return "已完成" }
        if let start = task.startAt, now < start { return "\(span(start.timeIntervalSince(now)))后开始" }
        guard let due = task.dueAt else { return "" }
        if now > due { return "已逾期 \(span(now.timeIntervalSince(due)))" }
        return span(due.timeIntervalSince(now))
    }

    static func span(_ interval: TimeInterval) -> String {
        let minutes = max(1, Int(interval / 60))
        let days = minutes / 1440
        let hours = (minutes % 1440) / 60
        if days > 0 { return hours > 0 ? "\(days)天 \(hours)小时" : "\(days)天" }
        if hours > 0 { return "\(hours)小时" }
        return "\(minutes)分钟"
    }
}
