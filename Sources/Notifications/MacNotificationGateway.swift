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
    /// 23:59 截止的任务改在白天提醒（默认开启），以及白天提醒的时间（分钟，默认 9:00）。
    static let daytimeKey = "notifications.daytimeForEndOfDay"
    static let daytimeMinutesKey = "notifications.daytimeMinutes"
    /// 临近提醒提前多少小时（默认 24，即 Core 的「提前一天」）。
    static let nearbyHoursKey = "notifications.nearbyHours"
    static let nearbyHourOptions = [1, 2, 3, 6, 12, 24, 48, 72]

    /// Mac 端排任务提醒用的设置。临近提醒由 Mac 按截止时间自己推算（Core 固定为提前一天），
    /// 所以向 Core 只要「到期」这一种，再由它派生临近提醒。
    static func taskReminders(_ defaults: UserDefaults = .standard) -> TaskReminderOptions {
        let enabled = defaults.bool(forKey: enabledKey)
        return TaskReminderOptions(
            nearby: enabled && (defaults.object(forKey: taskNearbyKey) as? Bool ?? true),
            due: enabled && (defaults.object(forKey: taskDueKey) as? Bool ?? true),
            nearbyHours: max(1, defaults.object(forKey: nearbyHoursKey) as? Int ?? 24)
        )
    }

    static func shaping(_ defaults: UserDefaults = .standard) -> NotificationShaping.Options {
        NotificationShaping.Options(
            daytime: defaults.object(forKey: daytimeKey) as? Bool ?? true,
            daytimeMinutes: defaults.object(forKey: daytimeMinutesKey) as? Int ?? 9 * 60
        )
    }

    static func policy(_ defaults: UserDefaults = .standard) -> NotificationPolicy {
        let reminders = taskReminders(defaults)
        return NotificationPolicy(
            taskRealtime: false, // 手机的实时通知（Live Update）在 Mac 上没有对应形式
            taskNearby: false,   // 由 Mac 从「到期」提醒派生，可以自定义提前的小时数
            taskDue: reminders.nearby || reminders.due,
            habitMode: HabitNotificationMode.due
        )
    }

    /// Core 的策略没有「关闭习惯提醒」，由 Mac 端在排程时过滤。
    static func habitsEnabled(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: enabledKey) && (defaults.object(forKey: habitsKey) as? Bool ?? true)
    }
}

struct TaskReminderOptions: Equatable {
    var nearby = true
    var due = true
    var nearbyHours = 24

    /// 「1 天」「3 小时」。
    static func phrase(hours: Int) -> String {
        hours % 24 == 0 ? String(localized: "\(hours / 24) 天") : String(localized: "\(hours) 小时")
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
    /// 任务的截止时间（习惯为 nil），用于把 23:59 截止的提醒挪到白天。
    var dueAt: Date? = nil
}

/// Mac 端对 Core 提醒的整理（不改 Core 的计算）：
/// - 23:59 截止的任务：Core 在截止时和提前一天各提醒一次，都落在午夜前后。开启后改在截止当天 / 前一天的白天提醒；
/// - 同一时刻、同一种类的多条任务提醒合并成一条，避免一次弹出一串。
enum NotificationShaping {
    struct Options: Equatable {
        var daytime = true
        var daytimeMinutes = 9 * 60
    }

    static func apply(_ items: [PlannedNotification], options: Options, now: Date = Date(),
                      calendar: Calendar = .current) -> [PlannedNotification] {
        var shaped: [PlannedNotification] = []
        for var item in items {
            if options.daytime, item.kind.hasPrefix("TASK_"), let due = item.dueAt, isEndOfDay(due, calendar) {
                let dueDay = calendar.startOfDay(for: due)
                // 临近提醒移到它原本那一天的白天；原本就在截止当天（提前不到一天）的保持原时间。
                let day = item.kind == "TASK_NEARBY" ? calendar.startOfDay(for: item.fireAt) : dueDay
                let daysBefore = calendar.dateComponents([.day], from: day, to: dueDay).day ?? 0
                if item.kind == "TASK_NEARBY" && daysBefore < 1 {
                    shaped.append(item)
                    continue
                }
                let fire = calendar.date(byAdding: .minute, value: options.daytimeMinutes, to: day)!
                // 白天的时间已经过了：不再补发（否则每次刷新都会立刻弹出）。
                guard fire > now else { continue }
                let body = item.kind != "TASK_NEARBY" ? String(localized: "今天 23:59 截止") : daysBefore == 1 ? String(localized: "明天 23:59 截止") : String(localized: "\(daysBefore) 天后 23:59 截止")
                item = PlannedNotification(id: item.id, ownerUid: item.ownerUid, kind: item.kind, title: item.title,
                                           body: body, fireAt: fire, dueAt: item.dueAt)
            }
            shaped.append(item)
        }
        // 合并：任务提醒按（种类, 分钟）分组，多于一条时合成一条。
        var result: [PlannedNotification] = []
        let groups = Dictionary(grouping: shaped) { item -> String in
            item.kind.hasPrefix("TASK_") ? "\(item.kind)|\(Int(item.fireAt.timeIntervalSince1970 / 60))" : item.id
        }
        for (key, group) in groups {
            guard group.count > 1, let first = group.first else { result += group; continue }
            let titles = group.map(\.title).sorted()
            let names = titles.prefix(5).joined(separator: "、") + (titles.count > 5 ? String(localized: " 等") : "")
            let endOfDay = group.allSatisfy { $0.body.contains("23:59") }
            let title: String = switch first.kind {
            case "TASK_NEARBY": group.allSatisfy { $0.body == String(localized: "明天 23:59 截止") } ? String(localized: "明天有 \(group.count) 项任务截止") : String(localized: "\(group.count) 项任务即将到期")
            default: endOfDay ? String(localized: "今天有 \(group.count) 项任务截止") : String(localized: "\(group.count) 项任务已到截止时间")
            }
            result.append(PlannedNotification(id: "deadliner.group.\(key)", ownerUid: "", kind: first.kind, title: title,
                                              body: names, fireAt: first.fireAt))
        }
        return result.sorted { $0.fireAt < $1.fireAt }
    }

    /// 截止时间是当天 23:59（全天截止）。
    static func isEndOfDay(_ date: Date, _ calendar: Calendar) -> Bool {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return c.hour == 23 && c.minute == 59
    }
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
    private let shaping: () -> NotificationShaping.Options
    /// 为 nil 时原样使用 Core 的任务提醒；提供时由 Mac 从「到期」提醒派生临近提醒（可自定义提前小时数）。
    private let taskReminders: (() -> TaskReminderOptions)?

    init(sink: NotificationSink, habitsEnabled: @escaping () -> Bool = { NotificationSettings.habitsEnabled() },
         shaping: @escaping () -> NotificationShaping.Options = { NotificationSettings.shaping() },
         taskReminders: (() -> TaskReminderOptions)? = nil) {
        self.sink = sink
        self.habitsEnabled = habitsEnabled
        self.shaping = shaping
        self.taskReminders = taskReminders
    }

    func applyNotificationMetadata(metadata: NotificationMetadata) {
        let includeHabits = habitsEnabled()
        var planned = metadata.alarms.compactMap { entry -> PlannedNotification? in
            let kind = entry.kind.name
            if !includeHabits && kind.hasPrefix("HABIT") { return nil }
            guard let fireAt = CoreDates.parseInstant(entry.triggerAt), let body = Self.body(kind: kind, dueAt: entry.dueAt) else { return nil }
            return PlannedNotification(id: "deadliner.\(entry.key)", ownerUid: entry.ownerUid, kind: kind,
                                       title: entry.title, body: body, fireAt: fireAt, dueAt: CoreDates.parseInstant(entry.dueAt))
        }
        if let options = taskReminders?() { planned = Self.derivingNearby(planned, options: options) }
        sink.replaceAll(with: NotificationShaping.apply(planned, options: shaping()))
    }

    /// 从「到期」提醒派生临近提醒：截止前 `nearbyHours` 小时（已经过了的不排）；不需要「到期」提醒时去掉它。
    static func derivingNearby(_ items: [PlannedNotification], options: TaskReminderOptions, now: Date = Date()) -> [PlannedNotification] {
        var result: [PlannedNotification] = []
        for item in items {
            switch item.kind {
            case "TASK_NEARBY":
                continue // 由下面重新派生
            case "TASK_DUE":
                if options.nearby, let due = item.dueAt {
                    let fire = due.addingTimeInterval(-Double(options.nearbyHours) * 3600)
                    if fire > now {
                        result.append(PlannedNotification(
                            id: item.id.replacingOccurrences(of: "deadliner.", with: "deadliner.nearby."), ownerUid: item.ownerUid,
                            kind: "TASK_NEARBY", title: item.title,
                            body: String(localized: "还有 \(TaskReminderOptions.phrase(hours: options.nearbyHours))到期（\(due.formatted(.dateTime.month().day().hour().minute()))）"),
                            fireAt: fire, dueAt: due))
                    }
                }
                if options.due { result.append(item) }
            default:
                result.append(item)
            }
        }
        return result
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
            guard let due = CoreDates.parseInstant(dueAt) else { return String(localized: "还有 1 天到期") }
            return String(localized: "还有 1 天到期（\(due.formatted(.dateTime.month().day().hour().minute()))）")
        case "TASK_DUE": return String(localized: "已到截止时间")
        case "HABIT_DUE", "HABIT_START": return String(localized: "该打卡了")
        default: return nil
        }
    }
}
