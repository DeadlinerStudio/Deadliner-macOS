import Foundation
import UserNotifications

/// 任务提醒上的操作按钮（与安卓相同）：完成、稍后提醒、删除。
enum TaskNotificationActions {
    static let categoryId = "deadliner.task"
    static let complete = "deadliner.action.complete"
    static let later = "deadliner.action.later"
    static let delete = "deadliner.action.delete"
    /// 「稍后提醒」排出的通知，不归 `UserNotificationSink` 管理（它只管 `deadliner.` 开头的请求）。
    static let snoozePrefix = "snooze."

    enum Action: Equatable { case complete, later, delete }

    static func action(for identifier: String) -> Action? {
        switch identifier {
        case complete: .complete
        case later: .later
        case delete: .delete
        default: nil
        }
    }

    /// 只有任务提醒带按钮；习惯和每日摘要没有。
    static func category(forKind kind: String) -> String {
        kind.hasPrefix("TASK") ? categoryId : ""
    }

    static func register(on center: UNUserNotificationCenter = .current()) {
        let actions = [
            UNNotificationAction(identifier: complete, title: String(localized: "完成"), options: []),
            UNNotificationAction(identifier: later, title: String(localized: "稍后提醒"), options: []),
            UNNotificationAction(identifier: delete, title: String(localized: "删除"), options: [.destructive]),
        ]
        center.setNotificationCategories([UNNotificationCategory(identifier: categoryId, actions: actions, intentIdentifiers: [])])
    }

    /// 稍后提醒的间隔（与安卓相同）：剩余时间的一半，至少 1 小时；已经过了截止时间时为 1 小时。
    static func laterDelayHours(dueAt: Date?, now: Date = Date()) -> Int {
        guard let dueAt else { return 1 }
        let remaining = Int(dueAt.timeIntervalSince(now) / 3600)
        return max(1, remaining / 2)
    }

    static func snoozeId(_ uid: String) -> String { snoozePrefix + uid }
}
