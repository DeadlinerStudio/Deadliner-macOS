import Foundation

/// 自动归档（与安卓、iOS 相同）：完成超过设定天数的任务自动移入归档。
/// 只处理「已完成」且记录了完成时刻的任务（与安卓相同：放弃的任务没有完成时刻，不自动归档）。
/// 归档是一次普通写入，会随同步到其他设备。默认关闭，打开后才处理。
enum AutoArchive {
    static let enabledKey = "tasks.autoArchive"
    static let daysKey = "tasks.autoArchiveDays"
    static let defaultDays = 7
    static let dayOptions = [1, 3, 7, 14, 30, 60, 90]
    /// 设置中开关或天数变化后发出，AppModel 立即检查一次。
    static let settingsChanged = Notification.Name("deadliner.autoArchiveSettingsChanged")

    static func settings(_ defaults: UserDefaults = .standard) -> (enabled: Bool, days: Int) {
        let days = defaults.object(forKey: daysKey) as? Int ?? defaultDays
        return (defaults.bool(forKey: enabledKey), max(0, days))
    }

    /// 需要归档的任务：已完成，且完成时刻距今超过 `days` 个整天（与安卓 `Duration.toDays() > N` 相同）。
    static func due(_ tasks: [TaskItem], days: Int, now: Date) -> [String] {
        tasks.filter { task in
            guard task.state == .completed, let completed = task.completedAt else { return false }
            return Int(now.timeIntervalSince(completed) / 86400) > days
        }
        .map(\.id)
    }
}
