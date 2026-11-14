import Foundation
import UserNotifications

/// 每日摘要通知（与安卓「每日摘要通知」相同）：每天固定时间推送一条任务概况——
/// 今天到期、已逾期、进行中各有多少。系统通知的内容在排程时就固定了，所以每次数据变化、
/// 应用激活和每 30 分钟都按最新任务重新排下一次（只排一条，替换旧的）。
enum DailySummary {
    static let enabledKey = "notifications.dailySummary"
    static let minutesKey = "notifications.dailySummaryMinutes"
    static let identifier = "daily-summary.next"
    static let kind = "DAILY_SUMMARY"

    struct Counts: Equatable {
        var dueToday = 0
        var overdue = 0
        var inProgress = 0
    }

    /// 下一次推送的时间：今天的设定时间还没到就是今天，否则是明天。
    static func nextFire(minutes: Int, now: Date, calendar: Calendar = .current) -> Date {
        let today = calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: now)!
        return today > now ? today : calendar.date(byAdding: .day, value: 1, to: today)!
    }

    /// 按推送时刻统计进行中的任务（与安卓相同：已过截止为逾期，截止在当天为今天到期，其余为进行中）。
    static func counts(_ tasks: [TaskItem], at fire: Date, calendar: Calendar = .current) -> Counts {
        var counts = Counts()
        for task in tasks where task.state == .active {
            guard let due = task.dueAt else { counts.inProgress += 1; continue }
            if due < fire { counts.overdue += 1 }
            else if calendar.isDate(due, inSameDayAs: fire) { counts.dueToday += 1 }
            else { counts.inProgress += 1 }
        }
        return counts
    }

    static func title(_ counts: Counts) -> String {
        counts.dueToday == 0 ? "今日任务概览" : "今日任务概览 - \(counts.dueToday) 个任务今日到期"
    }

    static func body(_ counts: Counts) -> String {
        "🔥逾期 \(counts.overdue) ｜ ⌛️进行中 \(counts.inProgress)"
    }

    /// 设置：是否开启（需要同时开启通知）与推送时间（分钟，默认 9:00，与安卓相同）。
    static func settings(_ defaults: UserDefaults = .standard) -> (enabled: Bool, minutes: Int) {
        (defaults.bool(forKey: NotificationSettings.enabledKey) && defaults.bool(forKey: enabledKey),
         defaults.object(forKey: minutesKey) as? Int ?? 9 * 60)
    }

    /// 按当前任务重新排下一条摘要；关闭时移除。
    static func schedule(tasks: [TaskItem], now: Date = Date(), defaults: UserDefaults = .standard,
                         center: UNUserNotificationCenter = .current()) {
        let setting = settings(defaults)
        guard setting.enabled else {
            center.removePendingNotificationRequests(withIdentifiers: [identifier])
            return
        }
        let fire = nextFire(minutes: setting.minutes, now: now)
        let counts = counts(tasks, at: fire)
        let content = UNMutableNotificationContent()
        content.title = title(counts)
        content.body = body(counts)
        content.sound = .default
        content.userInfo = ["ownerUid": "", "kind": kind]
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
        center.add(UNNotificationRequest(identifier: identifier, content: content,
                                         trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)))
    }
}
