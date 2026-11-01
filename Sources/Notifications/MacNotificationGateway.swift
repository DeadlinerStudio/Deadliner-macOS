import Foundation
import Shared
import UserNotifications

/// 通知设置（存 UserDefaults）。提醒时间由 Core 的 NotificationMetadataPlanner 决定，
/// 这里只选择开启哪几类：任务提前一天、任务到期、习惯打卡。
enum NotificationSettings {
    static let enabledKey = "notifications.enabled"
    static let taskNearbyKey = "notifications.taskNearby"
    static let taskDueKey = "notifications.taskDue"
    static let habitsKey = "notifications.habits"

    static func policy(_ defaults: UserDefaults = .standard) -> NotificationPolicy {
        let enabled = defaults.bool(forKey: enabledKey)
        return NotificationPolicy(
            taskRealtime: false, // 手机的实时通知（Live Update）在 Mac 上没有对应形式
            taskNearby: enabled && (defaults.object(forKey: taskNearbyKey) as? Bool ?? true),
            taskDue: enabled && (defaults.object(forKey: taskDueKey) as? Bool ?? true),
            habitMode: HabitNotificationMode.due
        )
    }

    /// Core 的策略没有「关闭习惯提醒」，由 Mac 端在排程时过滤。
    static func habitsEnabled(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: enabledKey) && (defaults.object(forKey: habitsKey) as? Bool ?? true)
    }
}

/// 一条要排进系统通知中心的提醒。
struct PlannedNotification: Equatable {
    let id: String
    let ownerUid: String
    let kind: String
    let title: String
    let body: String
    let fireAt: Date
}

/// 通知的去处：正式应用是系统通知中心，测试中是内存记录。
protocol NotificationSink: AnyObject {
    func replaceAll(with notifications: [PlannedNotification])
    func removeAll()
}

/// 实现 Core 的 `NotificationGateway`：Core 计算出要提醒的条目（`applyNotificationMetadata`），
/// Mac 端只负责转成系统通知。Core 会从任意线程调用这些方法。
final class MacNotificationGateway: NSObject, NotificationGateway {
    private let sink: NotificationSink
    private let habitsEnabled: () -> Bool

    init(sink: NotificationSink, habitsEnabled: @escaping () -> Bool = { NotificationSettings.habitsEnabled() }) {
        self.sink = sink
        self.habitsEnabled = habitsEnabled
    }

    func applyNotificationMetadata(metadata: NotificationMetadata) {
        let includeHabits = habitsEnabled()
        let planned = metadata.alarms.compactMap { entry -> PlannedNotification? in
            let kind = entry.kind.name
            if !includeHabits && kind.hasPrefix("HABIT") { return nil }
            guard let fireAt = CoreDates.parseInstant(entry.triggerAt), let body = Self.body(kind: kind, dueAt: entry.dueAt) else { return nil }
            return PlannedNotification(id: "deadliner.\(entry.key)", ownerUid: entry.ownerUid, kind: kind,
                                       title: entry.title, body: body, fireAt: fireAt)
        }
        sink.replaceAll(with: planned)
    }

    func cancelAll() { sink.removeAll() }

    // 以下是 Core 旧的逐条接口；提供了 policyProvider 时 Core 只走 applyNotificationMetadata。
    func cancelAllHabitNotifications() {}
    func cancelAllTaskNotifications() {}
    func cancelDailySummaryNotification() {}
    func cancelHabitNotification(habitUid: String) {}
    func cancelTaskNotification(taskUid: String) {}
    func cancelUpcomingLiveUpdate(taskUid: String) {}
    func refreshAll(tasks: [TaskNotificationInfo], habits: [HabitNotificationInfo]) {}
    func setDailySummaryNotification(config: DailySummaryConfig) {}
    func setHabitNotification(config: HabitNotificationConfig) {}
    func setTaskNotification(config: TaskNotificationConfig) {}
    func setUpcomingLiveUpdate(config: UpcomingLiveUpdateConfig) {}

    static func body(kind: String, dueAt: String) -> String? {
        switch kind {
        case "TASK_NEARBY":
            guard let due = CoreDates.parseInstant(dueAt) else { return "还有 1 天到期" }
            return "还有 1 天到期（\(due.formatted(.dateTime.month().day().hour().minute()))）"
        case "TASK_DUE": return "已到截止时间"
        case "HABIT_DUE", "HABIT_START": return "该打卡了"
        default: return nil
        }
    }
}

/// 系统通知中心。只管理带 `deadliner.` 前缀的请求。
final class UserNotificationSink: NotificationSink {
    /// 系统对每个应用待发送的通知数量有上限，只保留最近的这些。
    private static let limit = 60

    func replaceAll(with notifications: [PlannedNotification]) {
        let upcoming = notifications.filter { $0.fireAt > Date() }.sorted { $0.fireAt < $1.fireAt }.prefix(Self.limit)
        UNUserNotificationCenter.current().getPendingNotificationRequests { pending in
            let center = UNUserNotificationCenter.current()
            let keep = Set(upcoming.map(\.id))
            let stale = pending.map(\.identifier).filter { $0.hasPrefix("deadliner.") && !keep.contains($0) }
            center.removePendingNotificationRequests(withIdentifiers: stale)
            for item in upcoming {
                let content = UNMutableNotificationContent()
                content.title = item.title
                content.body = item.body
                content.sound = .default
                content.userInfo = ["ownerUid": item.ownerUid, "kind": item.kind]
                let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: item.fireAt)
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                // 同一标识的请求会被替换，时间或标题变化后无需先删除。
                center.add(UNNotificationRequest(identifier: item.id, content: content, trigger: trigger))
            }
        }
    }

    func removeAll() {
        UNUserNotificationCenter.current().getPendingNotificationRequests { pending in
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix("deadliner.") })
        }
    }
}
